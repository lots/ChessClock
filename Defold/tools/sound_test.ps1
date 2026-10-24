# sound_test.ps1 — 播一遍三份音效，用来判断「听不到声音」到底卡在哪一层
#
#   powershell -ExecutionPolicy Bypass -File tools/sound_test.ps1
#
# 它做三件事：
#   1) 用 --config=chessclock.test_sound=1 启动打包产物（会自动播 click / tick / alarm）；
#   2) 读 log.txt，确认游戏**真的发出了播放请求**（DBG sound test …）；
#   3) 把「听到 / 没听到」两种结果对应的下一步打印出来。
#
# 为什么需要它：无声可能卡在好几层（设置开关 / 播放代码 / 引擎音频输出 / 系统默认播放设备），
# 靠听只能判断最后一层，靠日志只能判断前面几层，两个一起看才定位得准。

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$exe = Get-ChildItem (Join-Path $root 'bundle') -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) { Write-Output 'FAIL: 没找到 bundle 里的 exe，请先跑 tools/build_and_run.ps1'; exit 1 }

$workDir = $exe.DirectoryName          # 引擎把日志写在启动进程的工作目录，所以就在 exe 目录启动
$log = Join-Path $workDir 'log.txt'
if (Test-Path $log) { Remove-Item $log -Force }

Write-Output "启动：$($exe.FullName)"
Write-Output '参数：--config=chessclock.test_sound=1（click → tick → alarm，间隔 1.2 秒）'
Write-Output ''
Write-Output '>>> 现在请听三声：短滴答（走子）/ 短滴答（读秒）/ 五连响（超时警报）'
Write-Output ''

$p = Start-Process -FilePath $exe.FullName -ArgumentList '--config=chessclock.test_sound=1' -WorkingDirectory $workDir -PassThru
Start-Sleep -Seconds 7
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
Start-Sleep -Milliseconds 300

$lines = @()
if (Test-Path $log) { $lines = Get-Content $log }
$text = [string]::Join([Environment]::NewLine, $lines)

Write-Output '--- 日志里的关键行 ---'
$key = $lines | Where-Object { $_ -match 'Initialised sound device|sound self-test|DBG sound test|Failed to|WASAPI' }
if ($key) { $key | ForEach-Object { Write-Output ('  ' + $_.TrimEnd()) } } else { Write-Output '  （没有相关行，可能没启动成功）' }

$device = ($text -match 'Initialised sound device')
$played = ($text -match 'DBG sound test click') -and ($text -match 'DBG sound test tick') -and ($text -match 'DBG sound test alarm')

Write-Output ''
Write-Output '--- 结论 ---'
if (-not $device) {
  Write-Output '  [FAIL] 引擎没有初始化音频设备：这不是棋钟代码的问题，是音频驱动 / 会话异常。'
} elseif (-not $played) {
  Write-Output '  [FAIL] 引擎起来了，但游戏没有发出播放请求：检查设置里的 sound 开关与自检代码。'
} else {
  Write-Output '  [OK]   引擎初始化了音频设备，三次播放请求也都发出去了。'
  Write-Output ''
  Write-Output '  接下来只看一层：你有没有听到三声？'
  Write-Output '   - 听到了 -> 音效链路是通的（走子 / 读秒 / 超时都会响）。'
  Write-Output '   - 没听到 -> 与棋钟代码无关了，按顺序查：'
  Write-Output '       1) Windows 默认播放设备是不是接了音箱/耳机的那个（本机默认是 DigitalOutput）；'
  Write-Output '       2) 音量合成器里这个 exe 有没有被单独静音；'
  Write-Output '       3) 最小 Defold 工程在同一台机器上也无声（实测：系统会话列表里没有该进程、'
  Write-Output '          默认输出端口峰值一直是 0，而系统播放器播同一个 wav 峰值 0.717）'
  Write-Output '          -> 那就是「引擎音频输出 / 系统音频」这一层的问题，换机器或换输出设备复测。'
}
Write-Output ''
Write-Output "日志：$log"
