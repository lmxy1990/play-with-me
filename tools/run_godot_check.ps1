param(
    [Parameter(Mandatory = $true)]
    [string[]]$Check,
    [string]$Godot = "D:\ProgramData\Godot_v4.6.2\Godot_v4.6.2-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Test-FatalGodotOutput {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }

    $fatalPatterns = @(
        "SCRIPT ERROR:",
        "Assertion failed.",
        "Assertion failed:",
        "timeout at stage="
    )

    foreach ($pattern in $fatalPatterns) {
        if ($Text.Contains($pattern)) {
            return $true
        }
    }

    return $false
}

if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot executable not found: $Godot"
}

$checks = @()
foreach ($entry in $Check) {
    $checks += ($entry -split "," | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
}

foreach ($item in $checks) {
    $path = $item
    if (-not [System.IO.Path]::IsPathRooted($path)) {
        $path = Join-Path $root $path
    }
    $resolved = (Resolve-Path -LiteralPath $path).Path
    Write-Host "Running Godot check: $resolved"
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $Godot `
            -ArgumentList @("--headless", "--path", $root, "--script", $resolved) `
            -PassThru `
            -NoNewWindow `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastHeartbeatSec = -1
        $stdoutOffset = 0
        $stderrOffset = 0
        $fatalDetected = $false
        $fatalReason = ""
        $stdoutTail = ""
        $stderrTail = ""

        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 800

            if (Test-Path -LiteralPath $stdoutPath) {
                $stdoutLength = (Get-Item -LiteralPath $stdoutPath).Length
                if ($stdoutLength -gt $stdoutOffset) {
                    $stream = [System.IO.File]::Open($stdoutPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        $stream.Seek($stdoutOffset, [System.IO.SeekOrigin]::Begin) > $null
                        $reader = New-Object System.IO.StreamReader($stream)
                        $text = $reader.ReadToEnd()
                        if ($text -ne "") {
                            Write-Host $text.TrimEnd("`r", "`n")
                            $stdoutTail = ($stdoutTail + $text)
                            if ($stdoutTail.Length -gt 4000) {
                                $stdoutTail = $stdoutTail.Substring($stdoutTail.Length - 4000)
                            }
                            if (-not $fatalDetected -and (Test-FatalGodotOutput -Text $stdoutTail)) {
                                $fatalDetected = $true
                                $fatalReason = "stdout"
                            }
                        }
                        $stdoutOffset = $stream.Length
                    }
                    finally {
                        $stream.Dispose()
                    }
                }
            }

            if (Test-Path -LiteralPath $stderrPath) {
                $stderrLength = (Get-Item -LiteralPath $stderrPath).Length
                if ($stderrLength -gt $stderrOffset) {
                    $stream = [System.IO.File]::Open($stderrPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        $stream.Seek($stderrOffset, [System.IO.SeekOrigin]::Begin) > $null
                        $reader = New-Object System.IO.StreamReader($stream)
                        $text = $reader.ReadToEnd()
                        if ($text -ne "") {
                            Write-Warning $text.TrimEnd("`r", "`n")
                            $stderrTail = ($stderrTail + $text)
                            if ($stderrTail.Length -gt 4000) {
                                $stderrTail = $stderrTail.Substring($stderrTail.Length - 4000)
                            }
                            if (-not $fatalDetected -and (Test-FatalGodotOutput -Text $stderrTail)) {
                                $fatalDetected = $true
                                $fatalReason = "stderr"
                            }
                        }
                        $stderrOffset = $stream.Length
                    }
                    finally {
                        $stream.Dispose()
                    }
                }
            }

            if ($fatalDetected) {
                Write-Host ("[run_godot_check] fatal output detected from {0}, stopping process: {1}" -f $fatalReason, $resolved)
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                } catch {
                }
                $process.WaitForExit()
                break
            }

            $elapsedSec = [int][Math]::Floor($stopwatch.Elapsed.TotalSeconds)
            if ($elapsedSec -ge 5 -and ($elapsedSec % 5) -eq 0 -and $elapsedSec -ne $lastHeartbeatSec) {
                Write-Host ("[run_godot_check] still running: {0} ({1}s)" -f $resolved, $elapsedSec)
                $lastHeartbeatSec = $elapsedSec
            }
        }

        if (Test-Path -LiteralPath $stdoutPath) {
            $remainingStdout = Get-Content -LiteralPath $stdoutPath -Raw
            if ($remainingStdout.Length -gt $stdoutOffset) {
                Write-Host $remainingStdout.Substring($stdoutOffset).TrimEnd("`r", "`n")
            }
        }
        if (Test-Path -LiteralPath $stderrPath) {
            $remainingStderr = Get-Content -LiteralPath $stderrPath -Raw
            if ($remainingStderr.Length -gt $stderrOffset) {
                Write-Warning $remainingStderr.Substring($stderrOffset).TrimEnd("`r", "`n")
            }
        }

        $exitCode = 0
        if ($null -ne $process.ExitCode) {
            $exitCode = [int]$process.ExitCode
        } elseif ($process.HasExited) {
            try {
                $exitCode = [int]$process.ExitCode
            } catch {
                $exitCode = 0
            }
        }
        if ($fatalDetected -and $exitCode -eq 0) {
            $exitCode = 1
        }
        Write-Host ("[run_godot_check] finished: {0} exit={1} elapsed={2:n1}s" -f $resolved, $exitCode, $stopwatch.Elapsed.TotalSeconds)
        if ($fatalDetected) {
            throw "Godot check failed from fatal output: $resolved"
        }
        if ($exitCode -ne 0) {
            throw "Godot check failed: $resolved"
        }
    }
    finally {
        if (Test-Path -LiteralPath $stdoutPath) {
            Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }
}
