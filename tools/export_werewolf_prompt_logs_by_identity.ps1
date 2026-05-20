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

$lines = New-Object System.Collections.Generic.List[string]
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
    $lines.Add(("===== #{0} 身份={1} 玩家={2} kind={3} action={4} =====" -f $sequence, $role, $record.actorTitle, $record.kind, $record.actionKey))
    foreach ($message in $record.messages) {
        $messageRole = [string]$message.role
        $label = switch ($messageRole) {
            "system" { "SYSTEM"; break }
            "user" { "USER"; break }
            default { $messageRole.ToUpperInvariant() }
        }
        $lines.Add("")
        $lines.Add("[$label]")
        $lines.Add([string]$message.content)
    }
    $lines.Add("")
}

Set-Content -Path $textOut -Value $lines -Encoding UTF8
Write-Host "exported $textOut"
