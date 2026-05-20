param(
    [string]$Device = "",
    [string]$Adb = "D:\android\platform-tools\adb.exe",
    [string]$Package = "com.playwithme.godot",
    [string]$Engine = "neko_tts",
    [string]$Voice = "zf_001",
    [string]$Text = "这是调试接口播放测试，用于验证本地语音引擎可以完成中文文本推理和播放。",
    [double]$Speed = 0.9,
    [double]$Volume = 1.0,
    [int]$TimeoutSec = 45,
    [switch]$WarmUp,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$Action = "com.playwithme.godot.TTS_DEBUG_SPEAK"
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
        throw "Debug speak broadcast did not return result data.`n$Output"
    }
    if ($dataLine -match 'data="(.*)"') {
        return [System.Text.RegularExpressions.Regex]::Unescape($Matches[1])
    }
    if ($dataLine -match 'data=(.*)$') {
        return $Matches[1].Trim()
    }
    throw "Could not parse debug speak broadcast result data.`n$Output"
}

function Convert-AmStringExtra {
    param([string]$Value)

    return $Value.Replace(" ", "%s")
}

$targets = if ([string]::IsNullOrWhiteSpace($Device)) { Get-OnlineDevices } else { @($Device) }
if ($targets.Count -eq 0) {
    throw "No online adb device. Run adb devices -l after connecting a device."
}

$timeoutMs = [Math]::Max(1000, $TimeoutSec * 1000)
$speedText = [System.Globalization.CultureInfo]::InvariantCulture.NumberFormat
$speedValue = $Speed.ToString($speedText)
$volumeValue = $Volume.ToString($speedText)
$textValue = Convert-AmStringExtra -Value $Text
foreach ($target in $targets) {
    $arguments = @(
        "-s", $target,
        "shell", "am", "broadcast",
        "--include-stopped-packages",
        "-n", $Receiver,
        "-a", $Action,
        "--es", "engine", $Engine,
        "--es", "voice", $Voice,
        "--es", "text", $textValue,
        "--ef", "speed", $speedValue,
        "--ef", "volume", $volumeValue,
        "--el", "timeout_ms", ([string]$timeoutMs)
    )
    if ($WarmUp) {
        $arguments += @("--ez", "warm_up", "true")
    }

    $output = Invoke-AdbText -Arguments $arguments
    $jsonText = Get-BroadcastData -Output $output
    $result = $jsonText | ConvertFrom-Json
    if ($Json) {
        Write-Output $jsonText
        continue
    }

    Write-Host "Device: $target"
    Write-Host "Debug speak: ok=$($result.ok) engine=$($result.engine) voice=$($result.voice) textChars=$($result.textChars) elapsedMs=$($result.elapsedMs)"
    Write-Host "Accepted: warmUp=$($result.warmUpAccepted) speak=$($result.speakAccepted) started=$($result.started) completed=$($result.completed) timedOut=$($result.timedOut)"
    if (-not [string]::IsNullOrWhiteSpace([string]$result.error)) {
        Write-Host "Error: $($result.error)"
    }
    foreach ($event in $result.events) {
        if ($event.type -eq "progress") {
            Write-Host ("- {0}: {1:P0}" -f $event.type, [double]$event.ratio)
        } elseif ($event.type -eq "failed") {
            Write-Host "- failed: $($event.error)"
        } else {
            Write-Host "- $($event.type)"
        }
    }
    if (-not [bool]$result.ok) {
        throw "TTS debug speak failed on ${target}: $($result.error)`n$jsonText"
    }
}
