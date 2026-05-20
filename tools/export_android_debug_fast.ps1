param(
    [ValidateSet("arm64-v8a", "x86_64", "universal")]
    [string]$Abi = "arm64-v8a",
    [string]$Godot = "D:\ProgramData\Godot_v4.6.2\Godot_v4.6.2-stable_win64_console.exe",
    [string]$Apk = "",
    [switch]$BuildPlugin,
    [switch]$WaitForExit
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
    $Apk = "builds\android\play-with-me-debug-$Abi.apk"
}

$apkPath = if ([System.IO.Path]::IsPathRooted($Apk)) { $Apk } else { Join-Path $root $Apk }
$apkDir = Split-Path -Parent $apkPath
New-Item -ItemType Directory -Force -Path $apkDir | Out-Null

if ($BuildPlugin) {
    Write-Host "Building Android debug plugin AAR"
    & (Join-Path $PSScriptRoot "build_android_plugin.ps1") -Configuration Debug
}

$logDir = Join-Path $root "builds\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stdout = Join-Path $logDir "godot-export-debug-fast.out.log"
$stderr = Join-Path $logDir "godot-export-debug-fast.err.log"

$presetPath = Join-Path $root "export_presets.cfg"
$originalPreset = [System.IO.File]::ReadAllText($presetPath)
$patchedPreset = Set-ExportPresetAbi -Content $originalPreset -TargetAbi $Abi
$patchedPreset = Set-PresetLine -Content $patchedPreset -Key "export_path" -Value "`"$(Get-PresetExportPath -FullApkPath $apkPath)`""
$patchedPreset = Set-PresetLine -Content $patchedPreset -Key "gradle_build/compress_native_libraries" -Value "false"
$patchedPreset = Set-PresetLine -Content $patchedPreset -Key "shader_baker/enabled" -Value "false"

$proc = $null
$presetPatched = $false
$start = Get-Date
$stoppedAfterApkReady = $false

try {
    if ($patchedPreset -ne $originalPreset) {
        [System.IO.File]::WriteAllText($presetPath, $patchedPreset, $utf8NoBom)
        $presetPatched = $true
    }

    Write-Host "Exporting Android debug-fast APK"
    Write-Host "ABI: $Abi"
    Write-Host "APK: $apkPath"
    Write-Host "Debug-fast options: shader_baker=false, compress_native_libraries=false"

    $args = @("--headless", "--path", $root, "--export-debug", "Android", $apkPath)
    $proc = Start-Process -FilePath $Godot -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

    if ($WaitForExit) {
        $proc.WaitForExit()
        if ($proc.ExitCode -ne 0) {
            throw "Godot export failed with exit code $($proc.ExitCode). See $stderr"
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
            throw "Godot export failed with exit code $($proc.ExitCode). See $stderr"
        }
    }

    if (-not (Test-Path $apkPath)) {
        throw "APK was not created. See $stdout and $stderr"
    }

    $apkItem = Get-Item $apkPath
    if ($apkItem.LastWriteTime -le $start -or $apkItem.Length -le 1MB) {
        throw "APK was not updated. See $stdout and $stderr"
    }

    Write-Host "APK ready: $apkPath"
    Write-Host "Size: $([Math]::Round($apkItem.Length / 1MB, 1)) MB"
} finally {
    if ($presetPatched) {
        [System.IO.File]::WriteAllText($presetPath, $originalPreset, $utf8NoBom)
    }

    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}
