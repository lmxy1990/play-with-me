param(
    [string]$Device = "",
    [string]$Package = "com.playwithme.godot",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutDir = Join-Path $repoRoot "exports\werewolf_prompt_logs_$stamp"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$adb = $env:ADB_PATH
if ([string]::IsNullOrWhiteSpace($adb)) {
    $defaultAdb = "D:\android\platform-tools\adb.exe"
    $adb = if (Test-Path $defaultAdb) { $defaultAdb } else { "adb" }
}

$adbArgs = @()
if (-not [string]::IsNullOrWhiteSpace($Device)) {
    $adbArgs += @("-s", $Device)
}

function Read-AppFileText([string]$Path) {
    $output = & $adb @adbArgs exec-out run-as $Package cat $Path 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ""
    }
    return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

$textOut = Join-Path $OutDir "actual_model_prompts_by_identity.txt"

$rawJsonl = Read-AppFileText "files/werewolf_bot_prompts.jsonl"
if ([string]::IsNullOrWhiteSpace($rawJsonl)) {
    $textLog = Read-AppFileText "files/werewolf_bot_prompts_by_identity.txt"
    if (-not [string]::IsNullOrWhiteSpace($textLog)) {
        Set-Content -Path $textOut -Value $textLog -Encoding UTF8
        Write-Host "exported $textOut"
        exit 0
    }
    throw "No werewolf prompt log found on device. Run a fresh werewolf round first."
}

$rawOut = Join-Path $OutDir "raw_werewolf_bot_prompts.jsonl"
Set-Content -Path $rawOut -Value $rawJsonl -Encoding UTF8

$records = @()
foreach ($line in ($rawJsonl -split "`r?`n")) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        continue
    }
    try {
        $records += ($trimmed | ConvertFrom-Json)
    } catch {
        $records = @()
        break
    }
}

if ($records.Count -eq 0) {
    $jsonArrayText = "[" + ($rawJsonl -replace "}\s*{", "},{") + "]"
    $records = @($jsonArrayText | ConvertFrom-Json)
}

function Safe-FileName([string]$Value) {
    $name = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "unknown"
    }
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $name = $name.Replace([string]$char, "_")
    }
    $name = ($name -replace "\s+", "_")
    if ($name.Length -gt 80) {
        $name = $name.Substring(0, 80)
    }
    return $name
}

function Append-Lines($Target, [string[]]$Source) {
    foreach ($line in $Source) {
        $Target.Add($line)
    }
}

$identityDir = Join-Path $OutDir "by_identity"
$playerDir = Join-Path $OutDir "by_player"
New-Item -ItemType Directory -Force -Path $identityDir | Out-Null
New-Item -ItemType Directory -Force -Path $playerDir | Out-Null

$lines = New-Object System.Collections.Generic.List[string]
$identityLines = @{}
$playerLines = @{}
$fallbackSequence = 0
foreach ($record in $records) {
    $fallbackSequence += 1
    $role = [string]$record.actorRole
    if ([string]::IsNullOrWhiteSpace($role)) {
        $role = [string]$record.actorRoleKey
    }
    if ([string]::IsNullOrWhiteSpace($role)) {
        $role = "未知身份"
    }
    $sequence = [int]$record.sequence
    if ($sequence -le 0) {
        $sequence = $fallbackSequence
    }
    $actorTitle = [string]$record.actorTitle
    $recordLines = New-Object System.Collections.Generic.List[string]
    $payload = $record.modelRequestPayload
    $payloadSchema = ""
    $outputAdapter = ""
    $reasonAdapter = ""
    $reasoningMode = ""
    if ($payload -ne $null) {
        $payloadSchema = [string]$payload.payload_schema
        $outputAdapter = [string]$payload.output_adapter
        $reasonAdapter = [string]$payload.reason_adapter
        $reasoningMode = [string]$payload.reasoning_mode
    }
    $recordLines.Add(("===== #{0} 身份={1} 玩家={2} kind={3} action={4} payload_schema={5} output_adapter={6} reason_adapter={7} reasoning_mode={8} =====" -f $sequence, $role, $actorTitle, $record.kind, $record.actionKey, $payloadSchema, $outputAdapter, $reasonAdapter, $reasoningMode))
    foreach ($message in $record.messages) {
        $messageRole = [string]$message.role
        $label = switch ($messageRole) {
            "system" { "SYSTEM"; break }
            "user" { "USER"; break }
            default { $messageRole.ToUpperInvariant() }
        }
        $recordLines.Add("")
        $recordLines.Add("[$label]")
        $recordLines.Add([string]$message.content)
    }
    $recordLines.Add("")
    Append-Lines $lines $recordLines

    $identityKey = Safe-FileName $role
    if (-not $identityLines.ContainsKey($identityKey)) {
        $identityLines[$identityKey] = New-Object System.Collections.Generic.List[string]
    }
    Append-Lines $identityLines[$identityKey] $recordLines

    $playerKey = Safe-FileName ("{0}_{1}" -f $actorTitle, $role)
    if (-not $playerLines.ContainsKey($playerKey)) {
        $playerLines[$playerKey] = New-Object System.Collections.Generic.List[string]
    }
    Append-Lines $playerLines[$playerKey] $recordLines
}

Set-Content -Path $textOut -Value $lines -Encoding UTF8
Write-Host "exported $textOut"

foreach ($key in $identityLines.Keys) {
    $path = Join-Path $identityDir ("$key.txt")
    Set-Content -Path $path -Value $identityLines[$key] -Encoding UTF8
    Write-Host "exported $path"
}

foreach ($key in $playerLines.Keys) {
    $path = Join-Path $playerDir ("$key.txt")
    Set-Content -Path $path -Value $playerLines[$key] -Encoding UTF8
    Write-Host "exported $path"
}
