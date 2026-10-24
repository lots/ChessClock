# install-android-sdk.ps1 — 用 cmdline-tools 装 Android SDK（不用装整个 Android Studio）
#
#   powershell -ExecutionPolicy Bypass -File tools/install-android-sdk.ps1
#   powershell -ExecutionPolicy Bypass -File tools/install-android-sdk.ps1 -IncludeNdk
#   powershell -ExecutionPolicy Bypass -File tools/install-android-sdk.ps1 -SdkDir "D:\Android\Sdk"
#
# 它做五件事：
#   1. 把 JDK 17 设成这次会话的 JAVA_HOME（机器上默认的 java 是 Java 8，sdkmanager 会拒绝启动）
#   2. 下载 commandlinetools 并解压成 <Sdk>\cmdline-tools\latest\（**latest 这一层不能省**，
#      zip 里只有 cmdline-tools\bin\...，直接解压到 cmdline-tools 下 sdkmanager 会找不到自己）
#   3. sdkmanager 装 Godot 4.5 需要的包（platform-tools / build-tools;35.0.0 / platforms;android-35）
#   4. 自动接受 SDK 许可协议（不接受到处都是 "license not accepted" 的构建失败）
#   5. 打印已装清单，并把 ANDROID_HOME 写进用户环境变量
#
# -IncludeNdk 会额外装 NDK r28b 与 CMake 3.10.2（Godot 文档把它们列为必装，
# 但只有「自定义构建模板 / 自己编译引擎」时才真的用到；只出 APK 可以先不装，省 3 GB 以上）。

param(
    [string]$SdkDir = "$env:LOCALAPPDATA\Android\Sdk",
    [string]$JavaHome = "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot",
    [switch]$IncludeNdk,
    [switch]$SkipLicenses
)

# 不用 Stop：sdkmanager 会把进度与告警写到 stderr，Stop 会当成致命错误中断
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'      # Invoke-WebRequest 的进度条会拖慢 10 倍

function Fail($msg) {
    Write-Host ""
    Write-Host "FAIL: $msg" -ForegroundColor Red
    exit 1
}

Write-Host "== 1/5 检查 JDK ==" -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $JavaHome 'bin\javac.exe'))) {
    Fail "找不到完整 JDK：$JavaHome（需要含 javac.exe；用 -JavaHome 指定）"
}
$env:JAVA_HOME = $JavaHome
$env:PATH = (Join-Path $JavaHome 'bin') + ';' + $env:PATH
$ver = & (Join-Path $JavaHome 'bin\javac.exe') -version 2>&1
Write-Host "  JAVA_HOME = $JavaHome  ($ver)"

Write-Host "== 2/5 准备 cmdline-tools ==" -ForegroundColor Cyan
$toolsRoot = Join-Path $SdkDir 'cmdline-tools'
$latest = Join-Path $toolsRoot 'latest'
$sdkmanager = Join-Path $latest 'bin\sdkmanager.bat'

if (Test-Path $sdkmanager) {
    Write-Host "  已有：$sdkmanager"
} else {
    # 版本号会变，先从官网页面抓当前的 Windows 包地址，抓不到再用兜底地址
    $url = $null
    try {
        $page = Invoke-WebRequest -Uri 'https://developer.android.com/studio' -UseBasicParsing -TimeoutSec 30
        $m = [regex]::Match($page.Content, 'https://dl\.google\.com/android/repository/commandlinetools-win-[0-9]+_latest\.zip')
        if ($m.Success) { $url = $m.Value }
    } catch {
        Write-Host "  （抓官网页面失败，改用兜底地址）" -ForegroundColor DarkYellow
    }
    if (-not $url) { $url = 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip' }

    $zip = Join-Path $env:TEMP 'commandlinetools-win.zip'
    Write-Host "  下载 $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 600
    } catch {
        Fail "下载失败：$($_.Exception.Message)（这台机器需要能访问 dl.google.com）"
    }
    $tmp = Join-Path $env:TEMP 'cmdline-tools-extract'
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Force -Path $toolsRoot | Out-Null
    if (Test-Path $latest) { Remove-Item $latest -Recurse -Force }
    Move-Item (Join-Path $tmp 'cmdline-tools') $latest
    Write-Host "  已解压到 $latest"
}

if (-not (Test-Path $sdkmanager)) { Fail "sdkmanager 仍不存在：$sdkmanager" }

Write-Host "== 3/5 安装 SDK 包 ==" -ForegroundColor Cyan
$packages = @(
    'platform-tools',
    'build-tools;35.0.0',
    'platforms;android-35',
    'cmdline-tools;latest'
)
if ($IncludeNdk) {
    $packages += 'ndk;28.1.13356709'
    $packages += 'cmake;3.10.2.4988404'
    Write-Host "  （含 NDK r28b 与 CMake 3.10.2，约 3 GB 以上，会慢）"
}
Write-Host ("  装：" + ($packages -join ' '))
& $sdkmanager "--sdk_root=$SdkDir" @packages
if ($LASTEXITCODE -ne 0) { Fail "sdkmanager 安装失败（exit $LASTEXITCODE），先看上面第一条报错" }

Write-Host "== 4/5 接受许可协议 ==" -ForegroundColor Cyan
if ($SkipLicenses) {
    Write-Host "  跳过（-SkipLicenses）；之后要手动跑：sdkmanager --licenses"
} else {
    # sdkmanager 会逐个问 y/n，这里一次性喂足够多的 y
    (('y' + [Environment]::NewLine) * 80) | & $sdkmanager "--sdk_root=$SdkDir" --licenses | Out-Null
    Write-Host "  已全部接受"
}

Write-Host "== 5/5 结果 ==" -ForegroundColor Cyan
& $sdkmanager "--sdk_root=$SdkDir" --list_installed
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $SdkDir, 'User')
Write-Host ""
Write-Host "SDK 目录：$SdkDir" -ForegroundColor Green
Write-Host "已把 ANDROID_HOME 写进用户环境变量（新开终端生效）"
Write-Host ""
Write-Host "接下来在 Godot 里填两项（Editor Settings → Export → Android）："
Write-Host "  Java SDK Path    = $JavaHome"
Write-Host "  Android Sdk Path = $SdkDir"
Write-Host ""
Write-Host "然后还需要：Editor → Manage Export Templates → Download（约 1 GB）"
Write-Host "RESULT: OK"
