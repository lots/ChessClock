# screenshot.ps1 — 抓 Defold 游戏窗口的截图（只截游戏窗口自身区域，不截整个桌面）
#
#   powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Scene menu
#   powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Scene clock -Out tests/screenshots/clock.png
#   powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Scene clock-swapped
#
# 前提：先跑过 tools/build_and_run.ps1（生成 bundle/）。本脚本会：
#   启动打包好的 exe → 等它画完 → 把窗口挪到固定位置 → 截图 → 关掉进程
# 说明：Defold 的游戏窗口是 OpenGL 窗口，用 PrintWindow 抓会黑屏，所以这里用
#       CopyFromScreen 抓窗口所在的屏幕区域（因此窗口不能被别的窗口遮挡）。
param(
  [ValidateSet('menu', 'help', 'preset-open', 'clock', 'clock-byoyomi', 'clock-swapped', 'overlay')]
  [string]$Scene = 'menu',
  [ValidateSet('', 'light', 'medium', 'dark')]
  [string]$Theme = '',
  [string]$Out = '',
  [int]$Width = 720,
  [int]$Height = 1040,
  [int]$WaitSeconds = 6
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Out) { $Out = "tests/screenshots/$Scene.png" }
$outPath = Join-Path $root $Out
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outPath) | Out-Null

$exe = Get-ChildItem (Join-Path $root 'bundle') -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue |
       Select-Object -First 1
if (-not $exe) { Write-Output 'FAIL: 没找到 bundle 里的 exe，请先跑 tools/build_and_run.ps1'; exit 1 }

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
$sig = @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class ClockWin {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool repaint);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
  // SetForegroundWindow 在「调用者不是前台进程」时会被系统拒绝（实测就发生了：
  // 游戏窗口留在最大化浏览器后面，截出来的是浏览器）。HWND_TOPMOST 一般仍能成功，
  // 所以截图前先把游戏窗口顶到最前，拍完再取消置顶。
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
  public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
  public static void Raise(IntPtr h) {
    SetWindowPos(h, HWND_TOPMOST, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);   // NOSIZE|NOMOVE|SHOWWINDOW
  }
  public static void Drop(IntPtr h) {
    SetWindowPos(h, HWND_NOTOPMOST, 0, 0, 0, 0, 0x0001 | 0x0002);
  }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  public struct RECT { public int Left, Top, Right, Bottom; }

  // 给窗口发一个按键（WM_KEYDOWN/WM_KEYUP）。键盘不依赖光标位置，
  // 比注入鼠标可靠：棋钟界面的 A 键就是「白方按键」，按一下就把钟开起来。
  public static void SendKey(IntPtr h, int vk) {
    PostMessageW(h, 0x0100, (IntPtr)vk, (IntPtr)0x001E0001);
    System.Threading.Thread.Sleep(60);
    PostMessageW(h, 0x0101, (IntPtr)vk, unchecked((IntPtr)(int)0xC01E0001));
  }

  // 调试版 exe 的控制台窗口会挡在游戏窗口前面，截图（是抓屏幕）就会被它盖住 ——
  // 先把标题里带 .exe 的那个窗口（= 控制台）藏起来。
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
  // 调试版 exe 会先弹一个控制台窗口，Process.MainWindowHandle 很可能拿到它，
  // 于是截到的是控制台而不是游戏。控制台窗口的标题是启动命令行（带 .exe），
  // 游戏窗口的标题是 project.title —— 用这一点把两者分开，再取面积最大的那个窗口。
  public static IntPtr FindGame(uint pid) {
    IntPtr best = IntPtr.Zero;
    long bestArea = 0;
    EnumWindows(delegate(IntPtr h, IntPtr p) {
      uint wpid; GetWindowThreadProcessId(h, out wpid);
      if (wpid != pid || !IsWindowVisible(h)) { return true; }
      var sb = new StringBuilder(512);
      GetWindowTextW(h, sb, 512);
      string t = sb.ToString();
      if (t.IndexOf(".exe", StringComparison.OrdinalIgnoreCase) >= 0) { return true; }
      RECT r;
      if (!GetWindowRect(h, out r)) { return true; }
      long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
      if (area > bestArea) { bestArea = area; best = h; }
      return true;
    }, IntPtr.Zero);
    return best;
  }
}
'@
Add-Type -TypeDefinition $sig

$args2 = @()
if ($Scene -eq 'clock') { $args2 = @('--config=chessclock.autostart=1') }
# -Theme light|medium|dark：用 demo_theme 开关指定主题（截图 / 人工核对三套配色）
if ($Theme -ne '') { $args2 += ('--config=chessclock.demo_theme=' + $Theme) }
# clock-swapped：进棋钟界面并打开「交换两侧」（白方在上并被旋转），
# 用来验证「旋转跟着视觉上第一块走」这条规则
if ($Scene -eq 'clock-swapped') {
  $args2 += @('--config=chessclock.autostart=1 --config=chessclock.demo_swapped=1')
  if (-not $Out) { $Out = 'tests/screenshots/clock-swapped.png' }
}
# clock-byoyomi：直接把表拨到读秒阶段（主时间用尽 + 跨过 1 段），拍到段数条暗掉一段的样子
if ($Scene -eq 'clock-byoyomi') {
  $args2 += @('--config=chessclock.autostart=1', '--config=chessclock.demo_byoyomi=1')
}
# help：「怎么用」单独一页（用 demo_page 直接打开，省得脚本去点按钮）
if ($Scene -eq 'help') {
  $args2 += '--config=chessclock.demo_page=help'
}
# preset-open：把时间预设的下拉浮层展开（验证弹层排版与命中区域）
if ($Scene -eq 'preset-open') {
  $args2 += '--config=chessclock.demo_preset_open=1'
}
# overlay：1 分钟无加秒 + 用键盘 A 开表，等一方超时后截结算层（不用动鼠标）
if ($Scene -eq 'overlay') {
  $args2 += @('--config=chessclock.autostart=1 --config=chessclock.demo_quick=1')
  if (-not $Out) { $Out = 'tests/screenshots/overlay.png' }
  # 先快速起来，按 A 开表之后再等 62 秒（1 分钟无加秒，60 秒时就该判超时）
  $WaitSeconds = 6
}
if ($args2.Count -gt 0) {
  $p = Start-Process -FilePath $exe.FullName -ArgumentList $args2 `
    -WorkingDirectory $exe.DirectoryName -PassThru
} else {
  $p = Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru
}
Start-Sleep -Seconds $WaitSeconds

# 调试版进程会带一个控制台窗口：挑「不是控制台」的那个窗口，而不是 MainWindowHandle
$h = [ClockWin]::FindGame([uint32]$p.Id)
if ($h -eq [IntPtr]::Zero) {
  $p.Refresh()
  $h = $p.MainWindowHandle
  if ($h -ne [IntPtr]::Zero) { Write-Output 'WARN: 没找到游戏窗口，退回 MainWindowHandle' }
}
if ($h -eq [IntPtr]::Zero) { Stop-Process -Id $p.Id -Force; Write-Output 'FAIL: 拿不到窗口句柄'; exit 1 }

[void][ClockWin]::HideConsole([uint32]$p.Id)
Start-Sleep -Milliseconds 400
if ($Scene -eq 'overlay') {
  # A 键 = 白方按键：未开表时按一下就是开表（对侧开始计时），这一步之前必须隐藏控制台
  [void][ClockWin]::MoveWindow($h, 40, 20, $Width, $Height, $true)
  [void][ClockWin]::SetForegroundWindow($h)
  [ClockWin]::SendKey($h, 0x41)                 # VK 'A'
  Start-Sleep -Milliseconds 600
  Write-Output '已按 A 键开表，等待一方超时…'
  Start-Sleep -Seconds 62
}
[void][ClockWin]::MoveWindow($h, 40, 20, $Width, $Height, $true)
[void][ClockWin]::SetForegroundWindow($h)
[ClockWin]::Raise($h)          # 顶到最前：SetForegroundWindow 被系统拒绝时也能拍到
Start-Sleep -Milliseconds 1500

$r = New-Object ClockWin+RECT
[void][ClockWin]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left
$hh = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $hh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
[ClockWin]::Drop($h)
Stop-Process -Id $p.Id -Force

Write-Output "OK   $Out  ${w}x${hh}"
