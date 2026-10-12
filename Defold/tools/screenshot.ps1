# screenshot.ps1 — 抓 Defold 游戏窗口的截图（只截游戏窗口自身区域，不截整个桌面）
#
#   powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Scene menu
#   powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 -Scene clock -Out tests/screenshots/clock.png
#
# 前提：先跑过 tools/build_and_run.ps1（生成 bundle/）。本脚本会：
#   启动打包好的 exe → 等它画完 → 把窗口挪到固定位置 → 截图 → 关掉进程
# 说明：Defold 的游戏窗口是 OpenGL 窗口，用 PrintWindow 抓会黑屏，所以这里用
#       CopyFromScreen 抓窗口所在的屏幕区域（因此窗口不能被别的窗口遮挡）。
param(
  [ValidateSet('menu', 'clock')]
  [string]$Scene = 'menu',
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
using System.Runtime.InteropServices;
public class ClockShot {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool repaint);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
Add-Type -TypeDefinition $sig

$args2 = @()
if ($Scene -eq 'clock') { $args2 = @('--config=chessclock.autostart=1') }
if ($args2.Count -gt 0) {
  $p = Start-Process -FilePath $exe.FullName -ArgumentList $args2 `
    -WorkingDirectory $exe.DirectoryName -PassThru
} else {
  $p = Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru
}
Start-Sleep -Seconds $WaitSeconds
$p.Refresh()
$h = $p.MainWindowHandle
if ($h -eq 0) { Stop-Process -Id $p.Id -Force; Write-Output 'FAIL: 拿不到窗口句柄'; exit 1 }

[void][ClockShot]::MoveWindow($h, 40, 20, $Width, $Height, $true)
[void][ClockShot]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 1500

$r = New-Object ClockShot+RECT
[void][ClockShot]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left
$hh = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $hh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Stop-Process -Id $p.Id -Force

Write-Output "OK   $Out  ${w}x${hh}"
