param(
    [string]$Device = "",
    [string]$Adb = "D:\android\platform-tools\adb.exe",
    [string]$Package = "com.playwithme.godot",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$SnapshotPath = "files/werewolf_room_debug_snapshot.json"

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
    return @{
        ExitCode = $exitCode
        Text = $text.Trim()
    }
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

function Read-SnapshotJson {
    param([string]$Target)

    $attempts = @(
        @("shell", "run-as", $Package, "cat", $SnapshotPath),
        @("shell", "run-as", $Package, "cat", "/data/data/$Package/$SnapshotPath"),
        @("shell", "cat", "/sdcard/Android/data/$Package/files/werewolf_room_debug_snapshot.json")
    )
    $errors = @()
    foreach ($args in $attempts) {
        $result = Invoke-AdbText -Arguments (@("-s", $Target) + $args) -AllowFailure
        if ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($result.Text) -and $result.Text.TrimStart().StartsWith("{")) {
            return $result.Text
        }
        $errors += "adb $($args -join ' '): $($result.Text)"
    }
    throw "Could not read werewolf room debug snapshot from $Target. Open the room once, then rerun.`n$($errors -join "`n")"
}

function Get-Count {
    param($Value)
    if ($null -eq $Value) {
        return 0
    }
    return @($Value).Count
}

function Write-Summary {
    param(
        [string]$Target,
        $Snapshot
    )

    Write-Host "Device: $Target"
    Write-Host "Debug API: ok=$($Snapshot.ok) api=$($Snapshot.api) generatedAtUnix=$($Snapshot.generatedAtUnix)"
    Write-Host "Room: $($Snapshot.activeRoomId) $($Snapshot.room.name) phase=$($Snapshot.werewolf.phase) day=$($Snapshot.werewolf.day) system='$($Snapshot.runtime.systemMessage)'"
    Write-Host "Counts: occupied=$($Snapshot.counts.occupiedPlayers) humans=$($Snapshot.counts.humans) bots=$($Snapshot.counts.bots) observers=$($Snapshot.counts.observers) history=$($Snapshot.counts.history) wolfPrivate=$($Snapshot.counts.wolfPrivateHistory) center=$($Snapshot.counts.centerSpeechItems)"
    Write-Host "Players:"
    foreach ($player in @($Snapshot.players)) {
        $seat = if ($null -ne $player.seatNumber) { $player.seatNumber } else { "?" }
        Write-Host ("- #{0} owner={1} name={2} role={3}/{4} alive={5} ready={6} tts={7}" -f $seat, $player.owner, $player.name, $player.role, $player.role_key, $player.alive, $player.ready, $player.ttsEnabled)
    }
    Write-Host "Views:"
    foreach ($view in @($Snapshot.views)) {
        $action = if ($null -ne $view.currentAction -and $view.currentAction.PSObject.Properties.Count -gt 0) { "$($view.currentAction.key):$($view.currentAction.viewerCanControl)" } else { "-" }
        $speech = if ($null -ne $view.speechPrompt -and $view.speechPrompt.PSObject.Properties.Count -gt 0) { "$($view.speechPrompt.speakerSeatNumber):$($view.speechPrompt.viewerCanSpeak)" } else { "-" }
        Write-Host ("- {0} kind={1} seat={2} history={3} wolfPrivate={4} hidden={5} action={6} speech={7}" -f $view.key, $view.kind, $view.seatIndex, (Get-Count $view.visibleHistory), (Get-Count $view.wolfPrivateHistory), $view.hiddenHistoryCount, $action, $speech)
    }
    $botCounts = $Snapshot.botDebug.requestTracker.counts
    Write-Host "Bot pending: action=$($botCounts.action) speech=$($botCounts.speech) waitingAction=$($Snapshot.botDebug.waitingAction) waitingSpeech=$($Snapshot.botDebug.waitingSpeech) auto=$($Snapshot.botDebug.autoResolving)"
    Write-Host "TTS: historyQueue=$(Get-Count $Snapshot.ttsDebug.historyQueue) runtimePending=$($Snapshot.ttsDebug.runtime.pending_count) current='$($Snapshot.ttsDebug.runtime.current.text)'"
    Write-Host "Memory scopes: $(Get-Count $Snapshot.memoryDebug.scopes)"
}

$targets = if ([string]::IsNullOrWhiteSpace($Device)) { Get-OnlineDevices } else { @($Device) }
if ($targets.Count -eq 0) {
    throw "No online adb device. Run adb devices -l after connecting a device."
}

foreach ($target in $targets) {
    $jsonText = Read-SnapshotJson -Target $target
    if ($Json) {
        Write-Output $jsonText
        continue
    }
    $snapshot = $jsonText | ConvertFrom-Json
    Write-Summary -Target $target -Snapshot $snapshot
}
