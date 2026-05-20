param(
    [string]$Device = "",
    [string]$Adb = "D:\android\platform-tools\adb.exe",
    [string]$Package = "com.playwithme.godot",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$Action = "com.playwithme.godot.TTS_DEBUG_SNAPSHOT"
$Receiver = "$Package/com.playwithme.godot.TtsDebugReceiver"

function Invoke-AdbText {
    param([string[]]$Arguments)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $Adb @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($exitCode -ne 0) {
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

function Get-BroadcastData {
    param([string]$Output)

    $dataLine = ($Output -split "`n" | Where-Object { $_ -match '\bdata=' } | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($dataLine)) {
        throw "Debug broadcast did not return result data.`n$Output"
    }
    if ($dataLine -match 'data="(.*)"') {
        return [System.Text.RegularExpressions.Regex]::Unescape($Matches[1])
    }
    if ($dataLine -match 'data=(.*)$') {
        return $Matches[1].Trim()
    }
    throw "Could not parse debug broadcast result data.`n$Output"
}

$targets = if ([string]::IsNullOrWhiteSpace($Device)) { Get-OnlineDevices } else { @($Device) }
if ($targets.Count -eq 0) {
    throw "No online adb device. Run adb devices -l after connecting a device."
}

foreach ($target in $targets) {
    $output = Invoke-AdbText -Arguments @(
        "-s", $target,
        "shell", "am", "broadcast",
        "--include-stopped-packages",
        "-n", $Receiver,
        "-a", $Action
    )
    $jsonText = Get-BroadcastData -Output $output
    $snapshot = $jsonText | ConvertFrom-Json
    if (-not [bool]$snapshot.ok) {
        throw "TTS debug API failed on ${target}: $($snapshot.error)`n$jsonText"
    }
    if ($Json) {
        Write-Output $jsonText
        continue
    }

    Write-Host "Device: $target"
    Write-Host "Debug API: ok=$($snapshot.ok) api=$($snapshot.api) debuggable=$($snapshot.debuggable)"
    Write-Host "Mode: $($snapshot.mode) systemTtsServiceDiscovery=$($snapshot.systemTtsServiceDiscovery)"
    Write-Host "Native runtime: available=$($snapshot.nativeRuntimeAvailable) reason=$($snapshot.nativeRuntimeReason)"
    Write-Host "Model assets: available=$($snapshot.modelAssets.available) dir=$($snapshot.modelAssets.assetDir) reason=$($snapshot.modelAssets.reason)"
    foreach ($engine in $snapshot.localEngines) {
        Write-Host ("- {0}: available={1} backend={2} voices={3} reason={4}" -f $engine.id, $engine.available, $engine.backend, $engine.voiceCount, $engine.reason)
    }
}
