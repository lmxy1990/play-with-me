param(
    [string]$MuMuRoot = "D:\Program Files\Netease\MuMu",
    [string]$AdbPath = "D:\android\platform-tools\adb.exe",
    [int]$TcpTimeoutMs = 700
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMs = 700
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Add-Candidate {
    param(
        [System.Collections.Generic.HashSet[string]]$Set,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $clean = $Value.Trim()
    if ($clean -match "^\d{1,3}(\.\d{1,3}){3}$") {
        [void]$Set.Add($clean)
    }
}

if (-not (Test-Path -LiteralPath $AdbPath)) {
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adbCommand) {
        throw "adb.exe was not found. Pass -AdbPath or add Android platform-tools to PATH."
    }
    $AdbPath = $adbCommand.Source
}

$ips = [System.Collections.Generic.HashSet[string]]::new()
$localPorts = [System.Collections.Generic.HashSet[int]]::new()
$vmsPath = Join-Path $MuMuRoot "vms"

if (Test-Path -LiteralPath $vmsPath) {
    Get-ChildItem -LiteralPath $vmsPath -Directory | ForEach-Object {
        $vmConfig = Join-Path $_.FullName "configs\vm_config.json"
        if (Test-Path -LiteralPath $vmConfig) {
            try {
                $json = Get-Content -LiteralPath $vmConfig -Raw | ConvertFrom-Json
                Add-Candidate -Set $ips -Value $json.vm.nat.port_forward.adb.guest_ip

                $portText = $json.vm.nat.port_forward.adb.host_port
                $port = 0
                if ([int]::TryParse([string]$portText, [ref]$port) -and $port -gt 0) {
                    [void]$localPorts.Add($port)
                }
            } catch {
                Write-Warning "Skipped unreadable config: $vmConfig"
            }
        }

        $vboxLog = Join-Path $_.FullName "logs\vboxmanager.log"
        if (Test-Path -LiteralPath $vboxLog) {
            $match = Select-String -LiteralPath $vboxLog -Pattern "wifi_ip value:" | Select-Object -Last 1
            if ($match) {
                Add-Candidate -Set $ips -Value ($match.Line -replace ".*wifi_ip value:\s*", "")
            }
        }
    }
}

Write-Host "Using adb: $AdbPath"

foreach ($ip in ($ips | Sort-Object)) {
    $target = "${ip}:5555"
    if (Test-TcpPort -HostName $ip -Port 5555 -TimeoutMs $TcpTimeoutMs) {
        & $AdbPath connect $target
    } else {
        Write-Host "skip $target (port closed)"
    }
}

foreach ($port in ($localPorts | Sort-Object)) {
    $target = "127.0.0.1:$port"
    if (Test-TcpPort -HostName "127.0.0.1" -Port $port -TimeoutMs $TcpTimeoutMs) {
        & $AdbPath connect $target
    }
}

& $AdbPath devices -l
