# build_and_run.ps1 — 用本机已安装的 Defold 做「解析依赖 → 编译 → 打包 → 冒烟运行 → 检查日志」
#
#   powershell -ExecutionPolicy Bypass -File tools/build_and_run.ps1
#
# 为什么需要它：Defold 编辑器是 GUI，但编辑器自带的 bob（命令行构建器）可以直接调用，
# 于是不用打开编辑器也能验证「资源格式对不对、Lua 有没有语法/运行时错误」。
# 本脚本会：
#   1) 自动找到本机 Defold 的 bob 与内置 JDK（读 %LOCALAPPDATA%\Defold\installations.json）
#   2) bob resolve          → 下载 game.project 里声明的库依赖（本项目用了 Druid）
#   3) bob --archive build  → 编译全部资源与 Lua
#   4) bob bundle           → 打包成可运行的 Windows 程序
#   5) 运行约 10 秒后结束，读 log.txt，打印 SCRIPT 错误并给出结论
#
# 退出码：0 = 全部通过；1 = 有问题（细节打印在上面）

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot          # 项目根目录（本脚本在 tools/ 下）
$runSeconds = 10

function Fail($msg) { Write-Output "FAIL: $msg"; exit 1 }

# ---------- 1. 找 bob / JDK ----------
$installations = Join-Path $env:LOCALAPPDATA 'Defold\installations.json'
if (-not (Test-Path $installations)) { Fail "没找到 Defold 安装记录：$installations（请先用 Defold 编辑器打开过一次项目）" }
$installs = Get-Content $installations -Raw | ConvertFrom-Json
$installPath = $null
foreach ($i in $installs) { if (Test-Path $i.installPath) { $installPath = $i.installPath; break } }
if (-not $installPath) { Fail 'installations.json 里的安装目录都不存在' }

$jar = Get-ChildItem (Join-Path $installPath 'packages') -Filter '*.jar' -ErrorAction SilentlyContinue |
       Sort-Object Length -Descending | Select-Object -First 1
if (-not $jar) { Fail "在 $installPath\packages 下没找到 Defold 的 jar" }
$java = Get-ChildItem (Join-Path $installPath 'packages') -Directory -Filter 'jdk*' -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'bin\java.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $java) { $java = 'java' }   # 退回系统 java（需要 17+）

# ---------- 2. 找平台 SDK（bundle 需要引擎可执行文件） ----------
$sha = $null
if ($jar.Name -match 'defold-([0-9a-f]{40})\.jar') { $sha = $Matches[1] }
$sdk = $null
if ($sha) {
  $cand = Join-Path $env:LOCALAPPDATA "Defold\unpack\$sha-x86_64"
  if (Test-Path $cand) { $sdk = $cand }
}
if (-not $sdk) {
  $sdk = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Defold\unpack') -Directory -ErrorAction SilentlyContinue |
         Where-Object { Test-Path (Join-Path $_.FullName 'x86_64-win32') } | Select-Object -First 1 |
         ForEach-Object { $_.FullName }
}
if (-not $sdk) { Fail '没找到 x86_64-win32 的平台 SDK（用编辑器 Build 过一次即可生成）' }

Write-Output "bob : $($jar.FullName)"
Write-Output "java: $java"
Write-Output "sdk : $sdk"

# ---------- 3. 解析库依赖 ----------
# 本项目是「零第三方依赖」，这一步现在什么都不下载；保留它是为了以后
# 万一在 game.project 里加了 dependencies#N，构建脚本不用改就能直接用。
& $java -cp $jar.FullName com.dynamo.bob.Bob --root $root --platform x86_64-win32 resolve *> (Join-Path $root 'build-resolve.log')
if ($LASTEXITCODE -ne 0) {
  Write-Output '--- bob resolve 失败（检查网络 / 依赖 URL）---'
  Get-Content (Join-Path $root 'build-resolve.log') | Select-String -Pattern 'ERROR|SEVERE' |
    Where-Object { $_ -notmatch 'protobuf|makeExtensions|unsafe_pre22|advisories|NativeCommand' } |
    Select-Object -First 12 | ForEach-Object { Write-Output $_ }
  Fail 'bob resolve'
}
Write-Output 'resolve: OK'

# ---------- 4. 编译 ----------
# 日志策略（game.project 的 write_log_file）：
#   1 = 仅调试版   2 = 总是写
# 本项目用 2：打包产物会往「启动目录」写一份很小的 log.txt，
# 这样自动化验证（tools/click_test.ps1）能核对行为，比赛现场出问题时
# 用户手边也直接有一份日志可以发过来。想安静就把 game.project 里改成 1，
# 但注意那样打包产物不写日志，第五节的两个脚本会因此失败。
$bobLog = Join-Path $root 'build-bob.log'
& $java -cp $jar.FullName com.dynamo.bob.Bob --root $root --platform x86_64-win32 --archive build *> $bobLog
if ($LASTEXITCODE -ne 0) {
  Write-Output '--- bob build 失败 ---'
  Get-Content $bobLog | Select-String -Pattern 'ERROR|SEVERE' |
    Where-Object { $_ -notmatch 'protobuf|makeExtensions|unsafe_pre22|advisories|NativeCommand' } |
    Select-Object -First 20 | ForEach-Object { Write-Output $_ }
  Fail 'bob build'
}
Write-Output 'build : OK'

# ---------- 5. 打包 ----------
$bundleDir = Join-Path $root 'bundle'
if (Test-Path $bundleDir) { Remove-Item $bundleDir -Recurse -Force }
& $java -cp $jar.FullName com.dynamo.bob.Bob --root $root --platform x86_64-win32 `
  --variant debug --defoldsdk $sdk --bundle-output $bundleDir bundle *> (Join-Path $root 'build-bundle.log')
if ($LASTEXITCODE -ne 0) { Fail 'bundle（详见 build-bundle.log）' }
$exe = Get-ChildItem $bundleDir -Recurse -Filter '*.exe' | Select-Object -First 1
if (-not $exe) { Fail '打包目录里没有 exe' }
Write-Output "bundle: OK  ->  $($exe.Name)"

# ---------- 6. 冒烟运行 + 查日志 ----------
# chessclock.autostart=1 让游戏跳过设置页直接进棋钟界面，
# 这样「两块面板 + 操作条 + 计时循环」的代码路径也会被运行期覆盖到。
# 日志来自 game.project 的 write_log_file（1=仅调试版，2=总是）。
# 注意：引擎是往「当前工作目录」写 ./log.txt 的，而它未必等于 exe 目录
# （实测会落到项目根目录），所以两个位置都要找。
$logCandidates = @((Join-Path $exe.DirectoryName 'log.txt'), (Join-Path $root 'log.txt'))
foreach ($f in $logCandidates) { if (Test-Path $f) { Remove-Item $f -Force } }
$p = Start-Process -FilePath $exe.FullName `
  -ArgumentList '--config=chessclock.autostart=1' `
  -WorkingDirectory $exe.DirectoryName -PassThru
Start-Sleep -Seconds $runSeconds
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; Write-Output "run   : 已运行 $runSeconds 秒（未崩溃）" }
else { Write-Output "run   : 提前退出 code=$($p.ExitCode)" }

$logFile = $logCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $logFile) { Fail "没有生成 log.txt（找过：$($logCandidates -join ' , ')）" }
$scriptErrors = Get-Content $logFile | Select-String -Pattern 'ERROR:SCRIPT|Traceback|attempt to'
if ($scriptErrors) {
  Write-Output '--- 运行期脚本错误 ---'
  Get-Content $logFile | Select-String -Pattern 'ERROR|DEBUG:SCRIPT|Traceback|attempt to' | ForEach-Object { Write-Output $_ }
  Fail '运行期有 Lua 错误'
}
Write-Output '--- 启动日志 ---'
Get-Content $logFile | Select-String -Pattern 'DEBUG:SCRIPT|ERROR:' | Select-Object -First 10 | ForEach-Object { Write-Output $_ }
Write-Output ''
Write-Output 'RESULT: 解析依赖、编译、打包、运行期无脚本错误'
exit 0
