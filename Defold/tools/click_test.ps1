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
using System.Text;
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
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public struct POINT { public int X, Y; }

  // 调试版 exe 会先弹一个控制台窗口（标题是启动命令行，带 .exe）：
  // 它既可能被 MainWindowHandle 选错，也会挡住游戏窗口、吃掉点击。
  // 所以：① 按「不是控制台」找游戏窗口；② 把控制台藏起来。
  public static IntPtr FindGame(uint pid) {
    IntPtr best = IntPtr.Zero;
    long bestArea = 0;
    EnumWindows(delegate(IntPtr h, IntPtr p) {
      uint wpid; GetWindowThreadProcessId(h, out wpid);
      if (wpid != pid || !IsWindowVisible(h)) { return true; }
      var sb = new StringBuilder(512);
      GetWindowTextW(h, sb, 512);
      if (sb.ToString().IndexOf(".exe", StringComparison.OrdinalIgnoreCase) >= 0) { return true; }
      RECT r;
      if (!GetWindowRect(h, out r)) { return true; }
      long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
      if (area > bestArea) { bestArea = area; best = h; }
      return true;
    }, IntPtr.Zero);
    return best;
  }

  public static int HideConsole(uint pid) {
    int n = 0;
    EnumWindows(delegate(IntPtr h, IntPtr p) {
      uint wpid; GetWindowThreadProcessId(h, out wpid);
      if (wpid != pid || !IsWindowVisible(h)) { return true; }
      var sb = new StringBuilder(512);
      GetWindowTextW(h, sb, 512);
      if (sb.ToString().IndexOf(".exe", StringComparison.OrdinalIgnoreCase) >= 0) {
        ShowWindow(h, 0);
        n++;
      }
      return true;
    }, IntPtr.Zero);
    return n;
  }
}
'@
Add-Type -TypeDefinition $sig

# 引擎按「当前工作目录」写 ./log.txt，未必是 exe 目录，两处都找
$logCandidates = @((Join-Path $exe.DirectoryName 'log.txt'), (Join-Path $root 'log.txt'))
foreach ($f in $logCandidates) { if (Test-Path $f) { Remove-Item $f -Force } }

# 清掉上一局留下的设置：设置是「记住上一次的选择」的，如果上一轮测试把「交换两侧」
# 打开了，这一轮的上下两块面板就是反的（点 pane_b 会点到白方那块）。
$settingsFile = Join-Path $exe.DirectoryName 'chessclock_settings'
if (Test-Path $settingsFile) { Remove-Item $settingsFile -Force }

# reset_settings=1：每轮都从「首次启动的默认设置」开始（否则上一轮点开的
# 「交换两侧」会留在存档里，这一轮的上下两块面板就是反的，点击全对不上）。
$p = Start-Process -FilePath $exe.FullName `
  -ArgumentList '--config=chessclock.debug_input=1 --config=chessclock.reset_settings=1' `
  -WorkingDirectory $exe.DirectoryName -PassThru
Start-Sleep -Seconds $WaitSeconds
$h = [ClockInput]::FindGame([uint32]$p.Id)
if ($h -eq [IntPtr]::Zero) {
  $p.Refresh()
  $h = $p.MainWindowHandle
  if ($h -ne [IntPtr]::Zero) { Write-Output 'WARN: 没找到游戏窗口，退回 MainWindowHandle' }
}
if ($h -eq [IntPtr]::Zero) { Stop-Process -Id $p.Id -Force; Write-Output 'FAIL: 拿不到窗口句柄'; exit 1 }
$hidden = [ClockInput]::HideConsole([uint32]$p.Id)
if ($hidden -gt 0) { Write-Output ("已隐藏控制台窗口 {0} 个" -f $hidden) }

# 顺序很重要：先让窗口恢复正常大小，再摆位置，最后置顶并抢焦点。
# （反过来的话 ShowWindow(SW_RESTORE) 会把窗口还原回原位，点击全部落偏）
[void][ClockInput]::ShowWindow($h, 9)
Start-Sleep -Milliseconds 400
[void][ClockInput]::MoveWindow($h, 40, 20, $Width, $Height, $true)
Start-Sleep -Milliseconds 400
# 整个测试期间让游戏窗口保持 TOPMOST：窗口是否拿到前台焦点会随环境变化，
# 而 mouse_event 是「点屏幕」，只要有别的窗口压在它上面，点击就会跑到别人那里去。
[void][ClockInput]::SetWindowPos($h, [IntPtr](-1), 40, 20, $Width, $Height, 0x0040)  # TOPMOST
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

# 每次点击前都把窗口重新顶到最前：SetForegroundWindow 在这种「非交互会话」里
# 经常被 Windows 拒绝（日志里显示 前台窗口匹配: False），只靠前台焦点不可靠，
# 所以额外重新声明 TOPMOST —— mouse_event 点的是屏幕，窗口必须真的在最上面。
# 把窗口抬到最前：光标落在它上面时，激活/悬停才正常（截图也不会被别的窗口挡住）
function Focus-Window {
  [void][ClockInput]::SetWindowPos($h, [IntPtr](-1), 40, 20, $Width, $Height, 0x0040)  # TOPMOST
  if ([ClockInput]::GetForegroundWindow() -ne $h) {
    [void][ClockInput]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 150
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
  [ClockInput]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)   # LEFTDOWN
  Start-Sleep -Milliseconds 90
  [ClockInput]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)   # LEFTUP
  Start-Sleep -Milliseconds 350
}

# 点某个控件，并核对日志里是否出现了预期的那一行。
# 为什么不数「收到了几次输入」：引擎是**缓冲写日志**的，计数法会在刷盘前误判成
# "没收到"从而重复点击（于是同一个按钮被点两三次）。以「预期内容出现」为准最稳。
# 没生效就重试（最多 8 次），每次都会把点击坐标打出来。
function Click-Id($id, [string]$expect = '') {
  # 每次都重新读坐标：窗口尺寸变化、界面切换、模式切换都会让 layout 重算位置，
  # 用开头读一次的旧坐标去点，会点到别的地方（本脚本踩过这个坑）。
  $map = Read-Positions
  if (-not $map.ContainsKey($id)) { Write-Output ("  跳过 {0}：日志里没有它的坐标" -f $id); return }
  $sx = Get-ScaleX $map
  $sy = Get-ScaleY $map
  $cx = [int]($map[$id][0] * $sx)
  $cy = [int]($clientH - $map[$id][1] * $sy)
  for ($try = 1; $try -le 8; $try++) {
    Click-Point $cx $cy
    Write-Output ("  点击 {0} -> 客户区({1},{2}){3}" -f $id, $cx, $cy, $(if ($try -gt 1) { "  第 $try 次" } else { '' }))
    if (-not $expect) { return }
    for ($w = 0; $w -lt 10; $w++) {
      Start-Sleep -Milliseconds 300
      $raw = Get-Content (Get-LogPath) -Raw -ErrorAction SilentlyContinue
      if ($raw -and $raw -match $expect) { return }
    }
    Write-Output '    （这次点击没生效，重试）'
  }
  Write-Output ("  警告：{0} 点了几次都没达到预期 {1}" -f $id, $expect)
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
Write-Output '[0/6] 先点几下标题区空白处（热焦点：实测窗口刚摆好时头三次点击会落偏）'
1..3 | ForEach-Object { Click-Point 350 60; Start-Sleep -Milliseconds 400 }

function Save-Shot([string]$name) {
  Add-Type -AssemblyName System.Drawing
  $wr = New-Object ClockInput+RECT
  [void][ClockInput]::GetWindowRect($h, [ref]$wr)
  $bw = $wr.Right - $wr.Left
  $bh = $wr.Bottom - $wr.Top
  $bmp = New-Object System.Drawing.Bitmap $bw, $bh
  $gr = [System.Drawing.Graphics]::FromImage($bmp)
  $gr.CopyFromScreen($wr.Left, $wr.Top, 0, 0, $bmp.Size)
  $shot = Join-Path $root ("tests\screenshots\" + $name)
  $bmp.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
  $gr.Dispose(); $bmp.Dispose()
  Write-Output ("  已截图: {0}  ({1}x{2})" -f $shot, $bw, $bh)
}

Write-Output '[1/6] 点模式按钮 Sudden'
Click-Id 'mode_sudden' 'DBG menu mode sudden'

if ($PresetId -ne '') {
  # 预设改成下拉框了：先点开（浮层里会打出 preset_opt_<n> 的坐标），再点第 n 档
  Write-Output ("[1b] 打开预设下拉框，点第 " + $PresetId + " 档（用来把时间调短，便于验证超时结算）")
  Click-Id 'preset_select' 'DBG menu preset_select true'
  Click-Id ("preset_opt_" + $PresetId) 'DBG menu preset'
}

Write-Output '[2/6] 点 START GAME'
Click-Id 'start' 'clock screen ready'
Start-Sleep -Milliseconds 1200

# 开局方式（与网页版一致）：没有 Start 按钮，拍**对侧**面板开表 ——
# 白先走，所以拍黑方那一侧 → **白方的钟开始走**，这一下不算步数（仍是 0/0）。
Write-Output '[3/6] 点黑方面板开表（白方的钟开始走，不算步数）'
for ($try = 0; $try -lt 10; $try++) {
  $tmp = Read-Positions
  if ($tmp.ContainsKey('pane_w') -and $tmp.ContainsKey('pane_b')) { break }
  Start-Sleep -Milliseconds 500
}
Click-Id 'pane_b' 'DBG clock press side=b target=w result=start'

Write-Output '[4/6] 点白方面板 = 走完一手（时间交给黑方）'
Click-Id 'pane_w' 'DBG clock press side=w target=w result=move'

# 开表后操作条里会多出 P / C（未开表时它是隐藏的）
for ($try = 0; $try -lt 10; $try++) {
  $tmp = Read-Positions
  if ($tmp.ContainsKey('bar_toggle')) { break }
  Start-Sleep -Milliseconds 400
}

Write-Output '[5/6] 点操作条「交换两侧」（两块面板的上下位置对调，旋转跟着视觉第一块走）'
Click-Id 'bar_swap' 'DBG clock swap swapped=true'
Start-Sleep -Milliseconds 600
Save-Shot 'clock-running.png'

Write-Output '[6/6] 点操作条 P 暂停、再点一次继续（按钮上只有 P / C）'
Click-Id 'bar_toggle' 'DBG clock pause paused=true'
Click-Id 'bar_toggle' 'DBG clock pause paused=false'

# 可选：等一方超时，验证结算层（这一层曾经因为 E.other 没导出而崩溃）
if ($FlagWaitSeconds -gt 0) {
  Write-Output ("[5/5] 等 {0} 秒让一方超时（验证结算层）" -f $FlagWaitSeconds)
  Start-Sleep -Seconds $FlagWaitSeconds
  Save-Shot 'overlay.png'
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
$lines | Select-String -Pattern 'DBG menu (mode|preset|start)|clock screen ready|DBG clock (press|pause|swap|facing)|ERROR:SCRIPT' |
  Select-Object -First 25 | ForEach-Object { Write-Output $_ }

$checks = [ordered]@{
  '按钮响应（mode=sudden）'                  = ($text -match 'DBG menu mode sudden')
  '拍对侧开表（黑方 → 白方的钟开始走）'      = ($text -match 'DBG clock press side=b target=w result=start')
  '面板点击生效（白方走了一步）'             = ($text -match 'DBG clock press side=w target=w result=move')
  '交换两侧生效'                            = ($text -match 'DBG clock swap swapped=true')
  '暂停 / 继续生效（P ↔ C）'                 = (($text -match 'DBG clock pause paused=true') -and ($text -match 'DBG clock pause paused=false'))
  '运行期没有脚本错误'                       = -not ($text -match 'ERROR:SCRIPT')
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