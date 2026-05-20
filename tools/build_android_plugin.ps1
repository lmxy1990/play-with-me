param(
    [ValidateSet("Debug", "Release", "All")]
    [string]$Configuration = "All",
    [switch]$NoSync
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pluginRoot = Join-Path $root "android_plugins\play_with_me_android"

$env:Path = "D:\android\gradle\gradle-8.10.2\bin;C:\Program Files\Java\jdk-21.0.10\bin;$env:Path"

switch ($Configuration) {
    "Debug" { $tasks = @(":play-with-me-android:assembleDebug") }
    "Release" { $tasks = @(":play-with-me-android:assembleRelease") }
    "All" { $tasks = @(":play-with-me-android:assembleDebug", ":play-with-me-android:assembleRelease") }
}

Push-Location $pluginRoot
try {
    Write-Host "Building Android plugin: $Configuration"
    & gradle @tasks
    if ($LASTEXITCODE -ne 0) {
        throw "Android plugin build failed: $Configuration"
    }
} finally {
    Pop-Location
}

if (-not $NoSync) {
    & (Join-Path $PSScriptRoot "sync_android_plugin_aar.ps1") -Configuration $Configuration
}
