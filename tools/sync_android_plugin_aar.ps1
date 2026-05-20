param(
    [ValidateSet("Debug", "Release", "All")]
    [string]$Configuration = "All"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

function Copy-Aar {
    param(
        [string]$Name,
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path $Source)) {
        throw "$Name AAR not found: $Source"
    }
    $destinationDir = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    $item = Get-Item $Destination
    Write-Host "$Name AAR synced: $Destination ($([Math]::Round($item.Length / 1MB, 1)) MB)"
}

$pluginOutput = Join-Path $root "android_plugins\play_with_me_android\play-with-me-android\build\outputs\aar"

if ($Configuration -eq "Debug" -or $Configuration -eq "All") {
    Copy-Aar `
        -Name "Debug" `
        -Source (Join-Path $pluginOutput "play-with-me-android-debug.aar") `
        -Destination (Join-Path $root "addons\play_with_me_android\bin\debug\play-with-me-android-debug.aar")
}

if ($Configuration -eq "Release" -or $Configuration -eq "All") {
    Copy-Aar `
        -Name "Release" `
        -Source (Join-Path $pluginOutput "play-with-me-android-release.aar") `
        -Destination (Join-Path $root "addons\play_with_me_android\bin\release\play-with-me-android-release.aar")
}
