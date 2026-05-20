param(
    [string]$Device = "",
    [ValidateSet("auto", "arm64-v8a", "x86_64", "universal")]
    [string]$Abi = "auto",
    [string]$Godot = "D:\ProgramData\Godot_v4.6.2\Godot_v4.6.2-stable_win64_console.exe",
    [string]$Adb = "D:\android\platform-tools\adb.exe",
    [string[]]$Connect = @(),
    [switch]$BuildPlugin,
    [switch]$NoExport,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root

function Test-NetworkDevice {
    param([string]$Serial)
    return $Serial -match '^[^\\/\s:]+:\d+$'
}

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
    return $text.Trim()
}

function Get-AdbDeviceRows {
    $lines = & $Adb devices -l
    if ($LASTEXITCODE -ne 0) {
        throw "adb devices -l failed"
    }

    $rows = @()
    foreach ($line in $lines) {
        $text = $line.ToString().Trim()
        if ($text -match '^(\S+)\s+(\S+)\b') {
            $serial = $Matches[1]
            if ($serial -eq "List") {
                continue
            }
            $rows += [PSCustomObject]@{
                Serial = $serial
                State = $Matches[2]
                Raw = $text
            }
        }
    }
    return $rows
}

function Connect-OfflineNetworkDevices {
    param([object[]]$Rows)

    foreach ($row in $Rows) {
        if ($row.State -ne "device" -and (Test-NetworkDevice $row.Serial)) {
            Write-Host "Trying adb connect for offline network device: $($row.Serial)"
            & $Adb connect $row.Serial | Out-Host
        }
    }
}

function Get-OnlineDevices {
    $rows = Get-AdbDeviceRows
    Connect-OfflineNetworkDevices -Rows $rows
    $rows = Get-AdbDeviceRows

    $devices = @()
    foreach ($row in $rows) {
        if ($row.State -eq "device") {
            $devices += $row.Serial
        }
    }
    return $devices
}

function Resolve-TargetDevices {
    foreach ($entry in $Connect) {
        foreach ($target in ($entry -split "," | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })) {
            & $Adb connect $target | Out-Host
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Device)) {
        if (Test-NetworkDevice $Device) {
            & $Adb connect $Device | Out-Host
        }
        return @($Device)
    }
    $devices = Get-OnlineDevices
    if ($devices.Count -eq 0) {
        throw "No online adb device. Run adb devices -l after connecting a device."
    }
    return $devices
}

function Resolve-DeviceAbi {
    param([string]$Serial)

    $primaryAbi = (Invoke-AdbText -Arguments @("-s", $Serial, "shell", "getprop", "ro.product.cpu.abi")).Trim()
    $abiList = (Invoke-AdbText -Arguments @("-s", $Serial, "shell", "getprop", "ro.product.cpu.abilist") -AllowFailure).Trim()

    if ($primaryAbi -eq "x86_64" -or ($abiList -split "," -contains "x86_64")) {
        return "x86_64"
    }
    if ($primaryAbi -eq "arm64-v8a" -or ($abiList -split "," -contains "arm64-v8a")) {
        return "arm64-v8a"
    }
    throw "Unsupported device ABI for $Serial. primary=$primaryAbi abilist=$abiList"
}

$targets = Resolve-TargetDevices

if ($BuildPlugin) {
    & (Join-Path $PSScriptRoot "build_android_plugin.ps1") -Configuration Debug
}

$abiToDevices = @{}
foreach ($target in $targets) {
    $targetAbi = if ($Abi -eq "auto") { Resolve-DeviceAbi -Serial $target } else { $Abi }
    if (-not $abiToDevices.ContainsKey($targetAbi)) {
        $abiToDevices[$targetAbi] = @()
    }
    $abiToDevices[$targetAbi] += $target
}

$installFailures = @()
foreach ($targetAbi in $abiToDevices.Keys) {
    $apk = Join-Path $root "builds\android\play-with-me-debug-$targetAbi.apk"
    if (-not $NoExport) {
        & (Join-Path $PSScriptRoot "export_android_debug_fast.ps1") -Abi $targetAbi -Godot $Godot -Apk $apk
    } elseif (-not (Test-Path $apk)) {
        throw "APK not found for -NoExport: $apk"
    }

    foreach ($target in $abiToDevices[$targetAbi]) {
        try {
            if ($NoLaunch) {
                & (Join-Path $PSScriptRoot "install_android_apk.ps1") -Apk $apk -Device $target -Adb $Adb -NoLaunch
            } else {
                & (Join-Path $PSScriptRoot "install_android_apk.ps1") -Apk $apk -Device $target -Adb $Adb
            }
        } catch {
            $message = "$target ($targetAbi): $($_.Exception.Message)"
            $installFailures += $message
            Write-Warning "Install failed: $message"
        }
    }
}

if ($installFailures.Count -gt 0) {
    throw "One or more device installs failed.`n$($installFailures -join "`n")"
}
