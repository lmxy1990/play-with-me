param(
    [string]$Device = "",
    [string]$Package = "com.playwithme.godot",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"

$scriptParams = @{
    Package = $Package
    Parse = $true
}
if (-not [string]::IsNullOrWhiteSpace($Device)) {
    $scriptParams["Device"] = $Device
}
if (-not [string]::IsNullOrWhiteSpace($OutDir)) {
    $scriptParams["OutDir"] = $OutDir
}

& (Join-Path $PSScriptRoot "export_werewolf_prompt_logs.ps1") @scriptParams
if ($LASTEXITCODE -ne 0) {
    throw "export_werewolf_prompt_logs.ps1 failed"
}
