param(
    [string]$Apk = "builds\android\play-with-me-debug-arm64-v8a.apk",
    [string]$Device = "",
    [string]$Adb = "D:\android\platform-tools\adb.exe",
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

function Test-NetworkDevice {
    param([string]$Serial)
    return $Serial -match '^[^\\/\s:]+:\d+$'
}

function Invoke-AdbText {
    param(
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $Adb @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "adb $($Arguments -join ' ') failed with exit code $exitCode.`n$text"
    }
    return $text.Trim()
}

function Get-OnlineDevices {
    $lines = & $Adb devices -l
    if ($LASTEXITCODE -ne 0) {
        throw "adb devices -l failed"
    }
    $devices = @()
    foreach ($line in $lines) {
        $text = $line.ToString().Trim()
        if ($text -match '^(\S+)\s+device\b') {
            $devices += $Matches[1]
        }
    }
    return $devices
}

function Resolve-TargetDevices {
    if (-not [string]::IsNullOrWhiteSpace($Device)) {
        if (Test-NetworkDevice $Device) {
            & $Adb connect $Device | Out-Host
        }
        return @($Device)
    }
    $devices = Get-OnlineDevices
    if ($devices.Count -eq 0) {
        throw "No online adb device. Run adb devices -l after connecting a device."
    }
    return $devices
}

$apkPath = if ([System.IO.Path]::IsPathRooted($Apk)) { $Apk } else { Join-Path $root $Apk }
if (-not (Test-Path $apkPath)) {
    throw "APK not found: $apkPath"
}

$targets = Resolve-TargetDevices
foreach ($target in $targets) {
    Write-Host "Installing APK to $target"
    Invoke-AdbText -Arguments @("-s", $target, "shell", "am", "force-stop", "com.playwithme.godot") -AllowFailure | Out-Null
    $installOutput = Invoke-AdbText -Arguments @("-s", $target, "install", "--no-streaming", "-r", "-d", "-t", "-g", $apkPath)
    $installOutput | Out-Host
    if ($installOutput -notmatch "(?m)^Success\b") {
        throw "adb install did not report success for $target.`n$installOutput"
    }
    if (-not $NoLaunch) {
        $launchOutput = Invoke-AdbText -Arguments @("-s", $target, "shell", "am", "start", "-n", "com.playwithme.godot/com.godot.game.GodotAppLauncher")
        $launchOutput | Out-Host
    }
}
