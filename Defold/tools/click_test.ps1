# click_test.ps1 — 往运行中的游戏窗口注入真实鼠标点击与按键，端到端验证输入链路
#
#   powershell -ExecutionPolicy Bypass -File tools/click_test.ps1
#
# 为什么这么做：截图只能证明"画出来了"，证明不了"点得动、打得进去"。
# 这套注入式验证已经抓到过：输入焦点发错对象、命中用错坐标空间、
# 超时结算层调用未导出的 API、以及测试脚本自己的窗口摆位顺序错误。
#
# 坐标不写死：游戏在 --config=chessclock.debug_input=1 时会把每个可点控件的
# 锚点用「窗口像素坐标（原点左下）」打进日志（DBG pos <id> <x> <y>），
# 本脚本读出来换算成客户区坐标（原点左上）再点，因此窗口大小/DPI/留边怎么变都不怕。
#
# 默认流程：
#   1) 点 Sudden 模式按钮        → 期望 DBG menu mode sudden
#   2) 点 START GAME             → 期望 clock screen ready
#   3) 点白方面板两次            → 期望 DBG clock press ... result=move
# 任何一次点击注入期间请勿操作鼠标键盘（窗口会被置顶）。

param(
  # 先点哪个预设（1=1+0，2=3+2，…，空=不点）。配合 -FlagWaitSeconds 用来让棋钟跑到超时。
  [string]$PresetId = '',
  # >0 时：点完面板再等这么多秒，等一方超时，验证结算层并截图留证
  [int]$FlagWaitSeconds = 0,
  [int]$Width = 720,
  [int]$Height = 1040,
  [int]$WaitSeconds = 6
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$exe = Get-ChildItem (Join-Path $root 'bundle') -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue |
       Select-Object -First 1
if (-not $exe) { Write-Output 'FAIL: 没找到 bundle 里的 exe，请先跑 tools/build_and_run.ps1'; exit 1 }

$sig = @'
using System;
using System.Runtime.InteropServices;
public class ClockInput {
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int t, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool repaint);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extra);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public struct POINT { public int X, Y; }
}
'@
Add-Type -TypeDefinition $sig

# 引擎按「当前工作目录」写 ./log.txt，未必是 exe 目录，两处都找
$logCandidates = @((Join-Path $exe.DirectoryName 'log.txt'), (Join-Path $root 'log.txt'))
foreach ($f in $logCandidates) { if (Test-Path $f) { Remove-Item $f -Force } }

$p = Start-Process -FilePath $exe.FullName `
  -ArgumentList '--config=chessclock.debug_input=1' `
  -WorkingDirectory $exe.DirectoryName -PassThru
Start-Sleep -Seconds $WaitSeconds
$p.Refresh()
$h = $p.MainWindowHandle
if ($h -eq 0) { Stop-Process -Id $p.Id -Force; Write-Output 'FAIL: 拿不到窗口句柄'; exit 1 }

# 顺序很重要：先让窗口恢复正常大小，再摆位置，最后置顶并抢焦点。
# （反过来的话 ShowWindow(SW_RESTORE) 会把窗口还原回原位，点击全部落偏）
[void][ClockInput]::ShowWindow($h, 9)
Start-Sleep -Milliseconds 400
[void][ClockInput]::MoveWindow($h, 40, 20, $Width, $Height, $true)
Start-Sleep -Milliseconds 400
[void][ClockInput]::SetWindowPos($h, [IntPtr](-1), 40, 20, $Width, $Height, 0x0040)  # TOPMOST
[void][ClockInput]::SetWindowPos($h, [IntPtr](-2), 40, 20, $Width, $Height, 0x0040)  # NOTOPMOST
[void][ClockInput]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 2500
Write-Output ("前台窗口匹配: {0}" -f ([ClockInput]::GetForegroundWindow() -eq $h))

$client = New-Object ClockInput+RECT
[void][ClockInput]::GetClientRect($h, [ref]$client)
$clientW = $client.Right - $client.Left
$clientH = $client.Bottom - $client.Top
$origin = New-Object ClockInput+POINT
[void][ClockInput]::ClientToScreen($h, [ref]$origin)
Write-Output ("客户区: {0}x{1}  原点: ({2},{3})" -f $clientW, $clientH, $origin.X, $origin.Y)

$logFile = $null
function Get-LogPath {
  $script:logFile = @($logCandidates | Where-Object { Test-Path $_ })[0]
  return $script:logFile
}

# 从日志里读出控件坐标（窗口像素，原点左下）；layout 可能跑多次，取最后一次
function Read-Positions {
  $map = @{}
  $lf = Get-LogPath
  if (-not $lf) { return $map }
  foreach ($line in Get-Content $lf) {
    if ($line -match 'DBG pos (\S+) ([\-\d\.]+) ([\-\d\.]+)') {
      $map[$Matches[1]] = @([double]$Matches[2], [double]$Matches[3])
    }
    if ($line -match 'DBG window ([\d\.]+) ([\d\.]+)') {
      $map['__window'] = @([double]$Matches[1], [double]$Matches[2])
    }
  }
  return $map
}

# 窗口像素(左下原点，场景尺度) → 客户区像素(左上原点)。
# 引擎报的是 gui.get_screen_position 的窗口像素；实测 on_input 的 action.y 是
# 「场景坐标、从上往下」，所以两轴要分别按 宽/宽、高/高 换算，别用一个比例。
function Get-ScaleX($map) {
  if ($map.ContainsKey('__window') -and $map['__window'][0] -gt 0) {
    $s = $clientW / $map['__window'][0]
    if ($s -gt 0.5 -and $s -lt 2) { return $s }
  }
  return 1.0
}
function Get-ScaleY($map) {
  if ($map.ContainsKey('__window') -and $map['__window'][1] -gt 0) {
    $s = $clientH / $map['__window'][1]
    if ($s -gt 0.5 -and $s -lt 2) { return $s }
  }
  return 1.0
}

function Focus-Window {
  if ([ClockInput]::GetForegroundWindow() -ne $h) {
    [void][ClockInput]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 500
  }
}

# 每次点击前重新读一次客户区原点：窗口刚被摆位时还在动，
# 用同一个旧原点连点会整体落偏（实测头几次点击就是这么偏掉的）
function Get-Origin {
  $o = New-Object ClockInput+POINT
  [void][ClockInput]::ClientToScreen($h, [ref]$o)
  return $o
}

function Click-Point([int]$cx, [int]$cy) {
  Focus-Window
  $o = Get-Origin
  [void][ClockInput]::SetCursorPos($o.X + $cx, $o.Y + $cy)
  Start-Sleep -Milliseconds 250
  [ClockInput]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 90
  [ClockInput]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 500
}

# 日志计数：用来判断"这一次点击游戏到底有没有收到"。
# 比"看效果"更可靠——窗口刚激活时的第一次点击常被系统吃掉（只激活不投递），
# 只按时间盲点就会出现"同一份代码有时过有时不过"。
function Count-MenuPresses {
  $raw = Get-Content (Get-LogPath) -Raw -ErrorAction SilentlyContinue
  if (-not $raw) { return 0 }
  return ([regex]::Matches($raw, 'DBG menu input action=\S+ pressed=true')).Count
}
function Count-ClockPresses {
  $raw = Get-Content (Get-LogPath) -Raw -ErrorAction SilentlyContinue
  if (-not $raw) { return 0 }
  return ([regex]::Matches($raw, 'DBG clock press')).Count
}

# 点某个控件：$verify='menu'|'clock' 表示"必须看到这类日志多一条"，$expect 是额外的内容核对。
# 没生效就重新聚焦再点（最多 5 次），并把每次的结果打出来。
function Click-Id($id, $map, [string]$expect = '', [string]$verify = 'menu') {
  if (-not $map.ContainsKey($id)) { Write-Output ("  跳过 {0}：日志里没有它的坐标" -f $id); return $false }
  $sx = Get-ScaleX $map
  $sy = Get-ScaleY $map
  $cx = [int]($map[$id][0] * $sx)
  $cy = [int]($clientH - $map[$id][1] * $sy)
  for ($try = 1; $try -le 5; $try++) {
    $before = if ($verify -eq 'clock') { Count-ClockPresses } else { Count-MenuPresses }
    Click-Point $cx $cy
    Write-Output ("  点击 {0} -> 客户区({1},{2}){3}" -f $id, $cx, $cy, $(if ($try -gt 1) { "  第 $try 次" } else { '' }))
    Start-Sleep -Milliseconds 350
    $after = if ($verify -eq 'clock') { Count-ClockPresses } else { Count-MenuPresses }
    if ($verify -ne 'none' -and $after -le $before) {
      Write-Output '    （这次点击游戏没收到，多半被窗口激活吃掉，重试）'
      continue
    }
    if (-not $expect) { return $true }
    Start-Sleep -Milliseconds 700   # 等引擎把日志刷到磁盘，免得误判成"没生效"而重复点击
    $raw = Get-Content (Get-LogPath) -Raw -ErrorAction SilentlyContinue
    if ($raw -match $expect) { return $true }
  }
  Write-Output ("  警告：{0} 点了几次都没达到预期 {1}" -f $id, $expect)
  return $false
}

# ---- 等日志出现控件坐标 ----
$pos = @{}
for ($try = 0; $try -lt 10; $try++) {
  $pos = Read-Positions
  if ($pos.ContainsKey('start')) { break }
  Start-Sleep -Milliseconds 500
}
if (-not $pos.ContainsKey('start')) { Stop-Process -Id $p.Id -Force; Write-Output 'FAIL: 日志里没有控件坐标（是不是没开 debug_input？）'; exit 1 }
Write-Output ("菜单控件坐标已读取: {0} 个" -f ($pos.Keys | Where-Object { $_ -notmatch '^__' }).Count)

Write-Output ''
Write-Output '[0/3] 先点几下标题区空白处（热焦点：实测窗口刚摆好时头三次点击会落偏）'
1..3 | ForEach-Object { Click-Point 350 60; Start-Sleep -Milliseconds 400 }

Write-Output '[1/3] 点模式按钮 Sudden'
[void](Click-Id 'mode_sudden' $pos 'DBG menu mode sudden')

if ($PresetId -ne '') {
  Write-Output ("[1b] 点预设 " + $PresetId + "（用来把时间调短，便于验证超时结算）")
  [void](Click-Id ("preset_" + $PresetId) $pos)
}

Write-Output '[2/3] 点 START GAME'
[void](Click-Id 'start' $pos 'clock screen ready')
Start-Sleep -Milliseconds 1200

Write-Output '[3/3] 在棋钟界面点白方面板两次（开表 + 走一步）'
$pos2 = @{}
for ($try = 0; $try -lt 10; $try++) {
  $pos2 = Read-Positions
  if ($pos2.ContainsKey('pane_w')) { break }
  Start-Sleep -Milliseconds 500
}
[void](Click-Id 'pane_w' $pos2 '' 'clock')
[void](Click-Id 'pane_w' $pos2 '' 'clock')

# 可选：等一方超时，验证结算层（这一层曾经因为 E.other 没导出而崩溃）
if ($FlagWaitSeconds -gt 0) {
  Write-Output ("[5/5] 等 {0} 秒让一方超时（验证结算层）" -f $FlagWaitSeconds)
  Start-Sleep -Seconds $FlagWaitSeconds
  $wr = New-Object ClockInput+RECT
  [void][ClockInput]::GetWindowRect($h, [ref]$wr)
  $bw = $wr.Right - $wr.Left
  $bh = $wr.Bottom - $wr.Top
  Add-Type -AssemblyName System.Drawing
  $bmp = New-Object System.Drawing.Bitmap $bw, $bh
  $gr = [System.Drawing.Graphics]::FromImage($bmp)
  $gr.CopyFromScreen($wr.Left, $wr.Top, 0, 0, $bmp.Size)
  $shot = Join-Path $root 'tests\screenshots\overlay.png'
  $bmp.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
  $gr.Dispose(); $bmp.Dispose()
  Write-Output ("  已截图: {0}  ({1}x{2})" -f $shot, $bw, $bh)
}

Start-Sleep -Milliseconds 800
Stop-Process -Id $p.Id -Force
Start-Sleep -Milliseconds 300

$logFile = Get-LogPath
if (-not $logFile) { Write-Output 'FAIL: 没有生成 log.txt'; exit 1 }
$lines = Get-Content $logFile
$text = $lines -join "`n"

Write-Output ''
Write-Output "--- 关键日志（$logFile）---"
$lines | Select-String -Pattern 'DBG menu (mode|name|select|start)|clock screen ready|DBG clock press|ERROR:SCRIPT' |
  Select-Object -First 25 | ForEach-Object { Write-Output $_ }

$checks = [ordered]@{
  '按钮响应（mode=sudden）'                = ($text -match 'DBG menu mode sudden')
  '面板点击生效（走了一步）'               = ($text -match 'DBG clock press .*result=move')
  '运行期没有脚本错误'                     = -not ($text -match 'ERROR:SCRIPT')
}
if ($FlagWaitSeconds -gt 0) {
  $checks['超时结算层出现（历史上这里崩过 E.other）'] = ($text -match 'DBG clock flag loser=')
}
Write-Output ''
foreach ($k in $checks.Keys) { Write-Output ("  [{0}] {1}" -f ($(if ($checks[$k]) { 'OK' } else { 'FAIL' })), $k) }
$bad = @($checks.Keys | Where-Object { -not $checks[$_] })
Write-Output ''
if ($bad.Count -eq 0) { Write-Output 'RESULT: 输入链路端到端通过'; exit 0 }
Write-Output ('RESULT: 有 {0} 项未通过' -f $bad.Count)
exit 1
