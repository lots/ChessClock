# run_tests.ps1 — 一键跑完 Godot 版的全部检查
#
#   powershell -ExecutionPolicy Bypass -File tests/run_tests.ps1
#   powershell -ExecutionPolicy Bypass -File tests/run_tests.ps1 -Godot "C:\Apps\Godot_451\Godot_v4.5.1-stable_win64_console.exe"
#
# 依次做四件事：
#   1. 刷新资源导入与脚本类缓存（新加 .gd 文件后必须，否则 class_name 找不到）
#   2. 导出关键数据 → tests/out/spec_dump.json（供 Node 与网页版比对）
#   3. 跑引擎单测（30 个用例，与 tests/engine.test.js 一一对应）
#   4. 跑界面集成测试（无头，21 个用例）
#   5. 跑 Node 静态一致性检查（与网页版 engine.js / i18n.js / app.js / styles.css 比对）
#
# 退出码 0 = 全部通过。

param(
    [string]$Godot = ""
)

# 用 Continue：Godot 会往 stderr 写一行无害的告警，Stop 会把它当成致命错误
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot          # ...\ChessClock\Godot

# user:// 指到工程目录里：既不受系统限制，也方便沙箱/CI 里跑
$env:APPDATA = Join-Path $Root ".userdata"
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null

function Find-Godot {
    param([string]$Hint)
    if ($Hint -and (Test-Path $Hint)) { return (Resolve-Path $Hint).Path }
    if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
    $cmd = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    foreach ($c in @(
            "C:\Apps\Godot_451\Godot_v4.5.1-stable_win64_console.exe",
            "C:\Apps\Godot_451\Godot_v4.5.1-stable_win64.exe",
            "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.5.1-stable_win64_console.exe")) {
        if (Test-Path $c) { return $c }
    }
    $found = Get-ChildItem -Path "C:\Apps", "C:\Program Files", "$env:LOCALAPPDATA\Programs" `
        -Filter "Godot*_console.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "找不到 Godot 可执行文件。请用 -Godot <路径> 指定，或把 godot 加进 PATH。"
}

$GodotExe = Find-Godot $Godot
Write-Host "Godot: $GodotExe" -ForegroundColor DarkGray
Write-Host ""

$script:Failures = 0
$script:Rows = @()

function Invoke-Step {
    param([string]$Name, [string]$File, [string[]]$Arguments)

    $output = & $GodotExe @Arguments 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    # Godot 在没有证书存储的环境里会打一行无害的告警，过滤掉免得吓人
    $output = $output | Where-Object { $_ -notmatch "root certificate store|platform/windows/os_windows" }
    $output | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    if ($code -eq 0) {
        Write-Host ("[ OK ] " + $Name) -ForegroundColor Green
    } else {
        Write-Host ("[FAIL] " + $Name + "（exit $code）") -ForegroundColor Red
        $script:Failures += 1
    }
    $script:Rows += [pscustomobject]@{ 检查 = $Name; 结果 = $(if ($code -eq 0) { "PASS" } else { "FAIL" }) }
}

Write-Host "1/5 刷新资源导入与类缓存 ..." -ForegroundColor Cyan
Invoke-Step "刷新导入（--import）" "godot" @("--headless", "--path", $Root, "--import")

Write-Host "2/5 导出对照数据 ..." -ForegroundColor Cyan
Invoke-Step "导出 spec_dump.json" "godot" @("--headless", "--path", $Root, "--script", "res://tests/dump_spec.gd")

Write-Host "3/5 计时引擎单测 ..." -ForegroundColor Cyan
Invoke-Step "engine_tests（31 个用例）" "godot" @("--headless", "--path", $Root, "--script", "res://tests/engine_tests.gd")

Write-Host "4/5 界面集成测试 ..." -ForegroundColor Cyan
Invoke-Step "ui_tests（21 个用例）" "godot" @("--headless", "--path", $Root, "--script", "res://tests/ui_tests.gd")

Write-Host "5/5 与网页版逐个比对 ..." -ForegroundColor Cyan
Push-Location $Root
try {
    $out = & node "tests/project_spec.js" 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
$out | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
if ($code -eq 0) {
    Write-Host "[ OK ] project_spec.js（网页版对照）" -ForegroundColor Green
} else {
    Write-Host ("[FAIL] project_spec.js（exit " + $code + "）") -ForegroundColor Red
    $script:Failures += 1
}
$script:Rows += [pscustomobject]@{ 检查 = "project_spec（网页版对照）"; 结果 = $(if ($code -eq 0) { "PASS" } else { "FAIL" }) }

Write-Host ""
$script:Rows | Format-Table -AutoSize | Out-String | Write-Host
if ($script:Failures -gt 0) {
    Write-Host ("RESULT: " + $script:Failures + " 项失败") -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: 全部通过" -ForegroundColor Green
exit 0
