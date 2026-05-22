param(
    [string]$Device = "",
    [string]$Package = "com.playwithme.godot",
    [string]$OutDir = "",
    [switch]$Parse,
    [switch]$IncludeState,
    [switch]$IncludeSnapshot
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

function Read-AppFileBytes([string]$Path) {
    $output = & $adb @adbArgs exec-out run-as $Package cat $Path 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return $output
}

function Read-AppFileText([string]$Path) {
    $bytes = Read-AppFileBytes $Path
    if ($null -eq $bytes) {
        return ""
    }
    return (($bytes | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Export-AppFileText([string]$DevicePath, [string]$LocalName, [switch]$Required) {
    $text = Read-AppFileText $DevicePath
    if ([string]::IsNullOrWhiteSpace($text)) {
        if ($Required) {
            throw "Device file not found or empty: $DevicePath"
        }
        return ""
    }
    $path = Join-Path $OutDir $LocalName
    Set-Content -Path $path -Value $text -Encoding UTF8
    Write-Host "exported $path"
    return $path
}

Write-Host "using adb: $adb"
if (-not [string]::IsNullOrWhiteSpace($Device)) {
    Write-Host "device: $Device"
}

$rawText = Read-AppFileText "files/werewolf_bot_prompts.jsonl"
$rawPath = ""
$sourceMode = "legacy_identity_text"
if (-not [string]::IsNullOrWhiteSpace($rawText)) {
    $rawPath = Join-Path $OutDir "raw_werewolf_bot_prompts.jsonl"
    Set-Content -Path $rawPath -Value $rawText -Encoding UTF8
    Write-Host "exported $rawPath"
    $sourceMode = "raw_jsonl"
}

$deviceIdentityPath = Export-AppFileText "files/werewolf_bot_prompts_by_identity.txt" "device_werewolf_bot_prompts_by_identity.txt"

if ([string]::IsNullOrWhiteSpace($rawPath)) {
    $legacyText = Read-AppFileText "files/werewolf_bot_prompts_by_identity.txt"
    if ([string]::IsNullOrWhiteSpace($legacyText)) {
        throw "No werewolf prompt log found on device. Run a fresh werewolf round first."
    }
    $rawPath = Join-Path $OutDir "actual_model_prompts_by_identity.txt"
    Set-Content -Path $rawPath -Value $legacyText -Encoding UTF8
    Write-Host "exported $rawPath"
}

if ($IncludeState) {
    Export-AppFileText "files/play_with_me_state.json" "play_with_me_state.json" | Out-Null
}

if ($IncludeSnapshot) {
    Export-AppFileText "files/werewolf_room_debug_snapshot.json" "werewolf_room_debug_snapshot.json" | Out-Null
}

$metadata = [ordered]@{
    device = $Device
    package = $Package
    rawJsonl = $rawPath
    deviceIdentityLog = $deviceIdentityPath
    sourceMode = $sourceMode
    includeState = [bool]$IncludeState
    includeSnapshot = [bool]$IncludeSnapshot
    exportedAt = (Get-Date).ToString("o")
}
$metadataPath = Join-Path $OutDir "prompt_export_metadata.json"
Set-Content -Path $metadataPath -Value ($metadata | ConvertTo-Json -Depth 10) -Encoding UTF8
Write-Host "exported $metadataPath"

if ($Parse -and $sourceMode -eq "raw_jsonl") {
    & (Join-Path $PSScriptRoot "parse_werewolf_prompt_logs.ps1") -RawJsonl $rawPath -OutDir $OutDir
    if ($LASTEXITCODE -ne 0) {
        throw "parse_werewolf_prompt_logs.ps1 failed"
    }
} elseif ($Parse) {
    Write-Warning "Raw JSONL was not available, so parse_werewolf_prompt_logs.ps1 was skipped."
}

Write-Host "done $OutDir"
