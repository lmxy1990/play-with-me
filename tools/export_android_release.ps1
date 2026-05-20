param(
    [ValidateSet("arm64-v8a", "x86_64", "universal")]
    [string]$Abi = "universal",
    [string]$Godot = "D:\ProgramData\Godot_v4.6.2\Godot_v4.6.2-stable_win64_console.exe",
    [string]$Apk = "",
    [string]$ReleaseKeystore = "",
    [string]$ReleaseKeystoreUser = "",
    [string]$ReleaseKeystorePassword = "",
    [switch]$WaitForExit,
    [switch]$BuildPlugin
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

$env:Path = "D:\android\gradle\gradle-8.10.2\bin;C:\Program Files\Java\jdk-21.0.10\bin;D:\android\platform-tools;$env:Path"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Set-PresetLine {
    param(
        [string]$Content,
        [string]$Key,
        [string]$Value
    )

    $pattern = "(?m)^$([regex]::Escape($Key))=.*$"
    if (-not [regex]::IsMatch($Content, $pattern)) {
        throw "Missing export preset key: $Key"
    }
    return [regex]::Replace($Content, $pattern, "$Key=$Value")
}

function Set-ExportPresetAbi {
    param(
        [string]$Content,
        [string]$TargetAbi
    )

    $enabled = @{
        "armeabi-v7a" = "false"
        "arm64-v8a" = "false"
        "x86" = "false"
        "x86_64" = "false"
    }

    if ($TargetAbi -eq "universal") {
        $enabled["arm64-v8a"] = "true"
        $enabled["x86_64"] = "true"
    } else {
        $enabled[$TargetAbi] = "true"
    }

    foreach ($arch in @("armeabi-v7a", "arm64-v8a", "x86", "x86_64")) {
        $Content = Set-PresetLine -Content $Content -Key "architectures/$arch" -Value $enabled[$arch]
    }
    return $Content
}

function Get-PresetExportPath {
    param([string]$FullApkPath)

    $fullRoot = [System.IO.Path]::GetFullPath($root).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $fullApk = [System.IO.Path]::GetFullPath($FullApkPath)
    if ($fullApk.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($fullApk.Substring($fullRoot.Length) -replace "\\", "/")
    }
    return ($fullApk -replace "\\", "/")
}

function Test-ApkReady {
    param(
        [string]$Path,
        [datetime]$StartTime,
        [ref]$LastLength,
        [ref]$StableCount
    )

    if (-not (Test-Path $Path)) {
        return $false
    }
    $item = Get-Item $Path
    if ($item.LastWriteTime -le $StartTime -or $item.Length -le 1MB) {
        return $false
    }
    if ($item.Length -eq $LastLength.Value) {
        $StableCount.Value += 1
    } else {
        $StableCount.Value = 0
        $LastLength.Value = $item.Length
    }
    return $StableCount.Value -ge 2
}

if ([string]::IsNullOrWhiteSpace($Apk)) {
    $Apk = "builds\android\play-with-me-release-$Abi.apk"
}

$apkPath = if ([System.IO.Path]::IsPathRooted($Apk)) { $Apk } else { Join-Path $root $Apk }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $apkPath) | Out-Null

if ([string]::IsNullOrWhiteSpace($ReleaseKeystore)) {
    $ReleaseKeystore = if ([string]::IsNullOrWhiteSpace($env:PLAY_WITH_ME_RELEASE_KEYSTORE)) {
        "builds\android\play-with-me-release.keystore"
    } else {
        $env:PLAY_WITH_ME_RELEASE_KEYSTORE
    }
}
if ([string]::IsNullOrWhiteSpace($ReleaseKeystoreUser)) {
    $ReleaseKeystoreUser = if ([string]::IsNullOrWhiteSpace($env:PLAY_WITH_ME_RELEASE_KEYSTORE_USER)) {
        "playwithme"
    } else {
        $env:PLAY_WITH_ME_RELEASE_KEYSTORE_USER
    }
}
if ([string]::IsNullOrWhiteSpace($ReleaseKeystorePassword)) {
    $ReleaseKeystorePassword = $env:PLAY_WITH_ME_RELEASE_KEYSTORE_PASSWORD
}

$releaseKeystorePath = if ([System.IO.Path]::IsPathRooted($ReleaseKeystore)) { $ReleaseKeystore } else { Join-Path $root $ReleaseKeystore }
if (-not (Test-Path $releaseKeystorePath)) {
    throw "Release keystore not found: $releaseKeystorePath"
}
if ([string]::IsNullOrWhiteSpace($ReleaseKeystoreUser)) {
    throw "Release keystore user is required. Pass -ReleaseKeystoreUser or set PLAY_WITH_ME_RELEASE_KEYSTORE_USER."
}
if ([string]::IsNullOrWhiteSpace($ReleaseKeystorePassword)) {
    throw "Release keystore password is required. Pass -ReleaseKeystorePassword or set PLAY_WITH_ME_RELEASE_KEYSTORE_PASSWORD."
}

if ($BuildPlugin) {
    & (Join-Path $PSScriptRoot "build_android_plugin.ps1") -Configuration Release
}

$logDir = Join-Path $root "builds\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stdout = Join-Path $logDir "godot-export-release.out.log"
$stderr = Join-Path $logDir "godot-export-release.err.log"

$presetPath = Join-Path $root "export_presets.cfg"
$originalPreset = [System.IO.File]::ReadAllText($presetPath)
$patchedPreset = Set-ExportPresetAbi -Content $originalPreset -TargetAbi $Abi
$patchedPreset = Set-PresetLine -Content $patchedPreset -Key "export_path" -Value "`"$(Get-PresetExportPath -FullApkPath $apkPath)`""
$patchedPreset = Set-PresetLine -Content $patchedPreset -Key "keystore/release" -Value "`"$(Get-PresetExportPath -FullApkPath $releaseKeystorePath)`""
$patchedPreset = Set-PresetLine -Content $patchedPreset -Key "keystore/release_user" -Value "`"$ReleaseKeystoreUser`""
$patchedPreset = Set-PresetLine -Content $patchedPreset -Key "keystore/release_password" -Value "`"$ReleaseKeystorePassword`""
$patchedPreset = Set-PresetLine -Content $patchedPreset -Key "gradle_build/compress_native_libraries" -Value "true"
$patchedPreset = Set-PresetLine -Content $patchedPreset -Key "shader_baker/enabled" -Value "true"

$presetPatched = $false
$proc = $null
$start = Get-Date
$stoppedAfterApkReady = $false
try {
    if ($patchedPreset -ne $originalPreset) {
        [System.IO.File]::WriteAllText($presetPath, $patchedPreset, $utf8NoBom)
        $presetPatched = $true
    }

    Write-Host "Exporting Android release APK"
    Write-Host "ABI: $Abi"
    Write-Host "APK: $apkPath"
    Write-Host "Release options: shader_baker=true, compress_native_libraries=true"

    $args = @("--headless", "--path", $root, "--export-release", "Android", $apkPath)
    $proc = Start-Process -FilePath $Godot -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    if ($WaitForExit) {
        $proc.WaitForExit()
        if ($proc.ExitCode -ne 0) {
            throw "Godot release export failed with exit code $($proc.ExitCode). See $stderr"
        }
    } else {
        $stableCount = 0
        $lastLength = -1
        while (-not $proc.HasExited) {
            Start-Sleep -Seconds 3
            if (Test-ApkReady -Path $apkPath -StartTime $start -LastLength ([ref]$lastLength) -StableCount ([ref]$stableCount)) {
                Write-Host "APK file is stable; stopping Godot exporter to skip slow post-export wait."
                $stoppedAfterApkReady = $true
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                break
            }
        }
        if (-not $stoppedAfterApkReady -and $proc.HasExited -and $proc.ExitCode -ne 0) {
            throw "Godot release export failed with exit code $($proc.ExitCode). See $stderr"
        }
    }
    if (-not (Test-Path $apkPath)) {
        throw "Release APK was not created. See $stdout and $stderr"
    }

    $apkItem = Get-Item $apkPath
    if ($apkItem.LastWriteTime -le $start -or $apkItem.Length -le 1MB) {
        throw "Release APK was not updated. See $stdout and $stderr"
    }
    Write-Host "Release APK ready: $apkPath"
    Write-Host "Size: $([Math]::Round($apkItem.Length / 1MB, 1)) MB"
} finally {
    if ($presetPatched) {
        [System.IO.File]::WriteAllText($presetPath, $originalPreset, $utf8NoBom)
    }
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}
