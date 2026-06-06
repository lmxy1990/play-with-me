param(
    [ValidateNotNullOrEmpty()]
    [string]$Version = "1.3.0",
    [ValidateSet("arm64-v8a", "x86_64", "universal")]
    [string[]]$Abis = @("arm64-v8a", "x86_64", "universal"),
    [string]$Godot = "D:\ProgramData\Godot_v4.6.2\Godot_v4.6.2-stable_win64_console.exe",
    [string]$ReleaseKeystore = "",
    [string]$ReleaseKeystoreUser = "",
    [string]$ReleaseKeystorePassword = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

function Assert-ExternalSuccess {
    param([string]$Message)

    if ($LASTEXITCODE -ne 0) {
        throw $Message
    }
}

function Get-TagCommit {
    param([string]$TagName)

    $refName = "refs/tags/$TagName"
    $tagInfo = & git for-each-ref --format="%(objectname)|%(*objectname)" $refName
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect git tag $TagName."
    }

    $tagText = (($tagInfo | Select-Object -First 1 | Out-String).Trim())
    if ([string]::IsNullOrWhiteSpace($tagText)) {
        return $null
    }

    $parts = $tagText -split "\|", 2
    if ($parts.Length -ge 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
        return $parts[1].Trim()
    }
    return $parts[0].Trim()
}

function Test-GhReleaseExists {
    param([string]$TagName)

    $output = & gh release list --limit 200 --json tagName 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    $outputText = (($output | Out-String).Trim())
    if ([string]::IsNullOrWhiteSpace($outputText)) {
        return $false
    }

    $releases = $outputText | ConvertFrom-Json
    return ($null -ne ($releases | Where-Object { $_.tagName -eq $TagName } | Select-Object -First 1))
}

if ([string]::IsNullOrWhiteSpace($ReleaseKeystore)) {
    $ReleaseKeystore = if ([string]::IsNullOrWhiteSpace($env:PLAY_WITH_ME_RELEASE_KEYSTORE)) {
        "builds\android\play-with-me-release.keystore"
    } else {
        $env:PLAY_WITH_ME_RELEASE_KEYSTORE
    }
}
if ([string]::IsNullOrWhiteSpace($ReleaseKeystoreUser)) {
    $ReleaseKeystoreUser = if ([string]::IsNullOrWhiteSpace($env:PLAY_WITH_ME_RELEASE_KEYSTORE_USER)) {
        "playwithme"
    } else {
        $env:PLAY_WITH_ME_RELEASE_KEYSTORE_USER
    }
}
if ([string]::IsNullOrWhiteSpace($ReleaseKeystorePassword)) {
    $ReleaseKeystorePassword = $env:PLAY_WITH_ME_RELEASE_KEYSTORE_PASSWORD
}

$releaseKeystorePath = if ([System.IO.Path]::IsPathRooted($ReleaseKeystore)) { $ReleaseKeystore } else { Join-Path $root $ReleaseKeystore }
if (-not (Test-Path $releaseKeystorePath)) {
    throw "Release keystore not found: $releaseKeystorePath"
}
if ([string]::IsNullOrWhiteSpace($ReleaseKeystoreUser)) {
    throw "Release keystore user is required. Pass -ReleaseKeystoreUser or set PLAY_WITH_ME_RELEASE_KEYSTORE_USER."
}
if ([string]::IsNullOrWhiteSpace($ReleaseKeystorePassword)) {
    throw "Release keystore password is required. Pass -ReleaseKeystorePassword or set PLAY_WITH_ME_RELEASE_KEYSTORE_PASSWORD."
}

Write-Host "Building Android release plugin"
& (Join-Path $PSScriptRoot "build_android_plugin.ps1") -Configuration Release
Assert-ExternalSuccess "Android plugin build failed."

$assets = @()
foreach ($abi in $Abis) {
    $apkPath = Join-Path $root "builds\android\play-with-me-release-$abi.apk"
    Write-Host "Exporting release APK: $abi"
    & (Join-Path $PSScriptRoot "export_android_release.ps1") `
        -Abi $abi `
        -Godot $Godot `
        -Apk $apkPath `
        -ReleaseKeystore $ReleaseKeystore `
        -ReleaseKeystoreUser $ReleaseKeystoreUser `
        -ReleaseKeystorePassword $ReleaseKeystorePassword
    Assert-ExternalSuccess "Android release export failed for $abi."

    if (-not (Test-Path $apkPath)) {
        throw "Release APK not found: $apkPath"
    }

    $item = Get-Item $apkPath
    if ($item.Length -le 1MB) {
        throw "Release APK is unexpectedly small: $apkPath"
    }

    Write-Host "Ready: $apkPath ($([Math]::Round($item.Length / 1MB, 1)) MB)"
    $assets += [pscustomobject]@{
        Path  = $apkPath
        Label = $abi
    }
}

$tag = "v$Version"
$headCommit = (& git rev-parse HEAD).Trim()
Assert-ExternalSuccess "Unable to resolve HEAD commit."

$tagCommit = Get-TagCommit -TagName $tag
if ($null -eq $tagCommit) {
    Write-Host "Creating git tag $tag"
    & git tag -a $tag -m "Play With Me $Version"
    Assert-ExternalSuccess "Failed to create git tag $tag."
    $tagCommit = $headCommit
} elseif ($tagCommit -ne $headCommit) {
    throw "Tag $tag already exists and points to $tagCommit, expected $headCommit."
}

Write-Host "Pushing tag $tag"
& git push origin $tag
Assert-ExternalSuccess "Failed to push tag $tag to origin."

$assetArgs = @()
foreach ($asset in $assets) {
    $assetArgs += "$($asset.Path)#$($asset.Label)"
}

if (Test-GhReleaseExists -TagName $tag) {
    Write-Host "Updating existing GitHub release $tag"
    & gh release upload $tag @assetArgs --clobber
    Assert-ExternalSuccess "Failed to upload release assets for $tag."
} else {
    Write-Host "Creating GitHub release $tag"
    & gh release create $tag @assetArgs --title "Play With Me $Version" --generate-notes --verify-tag --latest
    Assert-ExternalSuccess "Failed to create GitHub release $tag."
}
