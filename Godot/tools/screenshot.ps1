# screenshot.ps1 — 抓界面截图（视觉回归用）
#
#   powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1
#   powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Only clock,overlay
#   powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Only menu -Lang zh -OutDir tests/screenshots
#
# 原理：游戏本身就支持「摆好某个画面 → 存一张 PNG → 退出」的截图模式
# （ui/main.gd 里的 --shot=… / --shot-out=…），脚本只是用不同参数把它跑一遍。
# 好处是截图就是**运行时真实渲染**的结果，不是编辑器里的预览。
#
# -Only 支持前缀匹配：-Only menu 会拍 menu、menu-light、menu-medium、menu-zh、menu-landscape。

param(
    [string]$Godot = "",
    [string[]]$Only = @(),
    [string]$Lang = "",
    [string]$Theme = "",
    [string]$OutDir = ""
)

# 用 Continue：Godot 会往 stderr 写一行无害的告警，Stop 会把它当成致命错误
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot

# -Only 经 -File 传进来时是「一个含逗号的字符串」，这里拆开，让 -Only menu,help 也能用
$Only = @($Only | ForEach-Object { "$_" -split ',' } | Where-Object { $_ -ne '' })
if ($OutDir -eq "") { $OutDir = Join-Path $Root "tests\screenshots" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 让 Godot 的 user:// 落在工程目录里（沙箱/CI 下 AppData 可能不可写）
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
            "C:\Apps\Godot_451\Godot_v4.5.1-stable_win64.exe")) {
        if (Test-Path $c) { return $c }
    }
    throw "找不到 Godot 可执行文件。请用 -Godot <路径> 指定。"
}
$GodotExe = Find-Godot $Godot

# 名单：名字 → 参数（分辨率不写就是竖屏手机 390×844）
$Shots = @(
    @{ Name = "menu";            Args = @("--shot=menu") },
    @{ Name = "menu-light";      Args = @("--shot=menu", "--theme=light") },
    @{ Name = "menu-medium";     Args = @("--shot=menu", "--theme=medium") },
    @{ Name = "menu-zh";         Args = @("--shot=menu", "--lang=zh") },
    @{ Name = "menu-landscape";  Args = @("--shot=menu", "--resolution", "844x390") },
    @{ Name = "menu-bottom";   Args = @("--shot=menu-bottom") },
    @{ Name = "help";            Args = @("--shot=help") },
    @{ Name = "help-light";      Args = @("--shot=help", "--theme=light") },
    @{ Name = "clock";           Args = @("--shot=clock") },
    @{ Name = "clock-swapped";   Args = @("--shot=clock-swapped") },
    @{ Name = "clock-paused";    Args = @("--shot=clock-paused") },
    @{ Name = "clock-byoyomi";   Args = @("--shot=clock-byoyomi") },
    @{ Name = "clock-light";     Args = @("--shot=clock", "--theme=light") },
    @{ Name = "clock-zh";        Args = @("--shot=clock", "--lang=zh") },
    @{ Name = "clock-landscape"; Args = @("--shot=clock", "--resolution", "844x390") },
    @{ Name = "overlay";         Args = @("--shot=overlay") },
    @{ Name = "confirm";         Args = @("--shot=confirm") }
)

function Wanted {
    param([string]$Name)
    if ($Only.Count -eq 0) { return $true }
    foreach ($want in $Only) {
        if ($Name -like ($want + "*")) { return $true }
    }
    return $false
}

$made = 0
foreach ($shot in $Shots) {
    if (-not (Wanted $shot.Name)) { continue }

    $args = @("--path", $Root) + $shot.Args
    if ($shot.Args -notcontains "--resolution") { $args = @("--path", $Root, "--resolution", "390x844") + $shot.Args }
    if ($Lang -ne "" -and $shot.Args -notmatch "--lang") { $args += "--lang=$Lang" }
    if ($Theme -ne "" -and $shot.Args -notmatch "--theme") { $args += "--theme=$Theme" }

    $out = Join-Path $OutDir ($shot.Name + ".png")
    $args += "--shot-out=$out"

    $log = & $GodotExe @args 2>&1 | ForEach-Object { "$_" }
    $line = $log | Where-Object { $_ -match "SHOT " } | Select-Object -First 1
    if ($line) {
        Write-Host ("  OK   " + $shot.Name.PadRight(16) + (Split-Path -Leaf $out)) -ForegroundColor Green
        $made += 1
    } else {
        Write-Host ("  FAIL " + $shot.Name) -ForegroundColor Red
        $log | Where-Object { $_ -match "SCRIPT ERROR|ERROR" } | Select-Object -First 5 |
            ForEach-Object { Write-Host ("       " + $_) -ForegroundColor DarkGray }
    }
}

Write-Host ""
Write-Host ("RESULT: " + $made + " 张截图 → " + $OutDir) -ForegroundColor Cyan
