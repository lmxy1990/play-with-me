param(
    [string]$Device = "",
    [string]$Package = "com.playwithme.godot",
    [string]$RawJsonl = "",
    [int]$Sequence = 123,
    [string]$ApiKey = "",
    [string]$OutDir = "",
    [int]$TimeoutSec = 150,
    [switch]$PrintBody,
    [switch]$NoDeviceState
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutDir = Join-Path $repoRoot "exports\werewolf_request_replay_$stamp"
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
    if ([string]::IsNullOrWhiteSpace($Device)) {
        return ""
    }
    $output = & $adb @adbArgs exec-out run-as $Package cat $Path 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ""
    }
    return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Resolve-RawJsonlPath {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        if (-not (Test-Path $Path)) {
            throw "RawJsonl not found: $Path"
        }
        return (Resolve-Path $Path).Path
    }
    $latest = Get-ChildItem -Path (Join-Path $repoRoot "exports") -Filter "raw_werewolf_bot_prompts.jsonl" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latest -ne $null) {
        return $latest.FullName
    }
    return ""
}

function Parse-JsonlRecords([string]$Text) {
    $records = @()
    foreach ($line in ($Text -split "`r?`n")) {
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
        $jsonArrayText = "[" + ($Text -replace "}\s*{", "},{") + "]"
        $records = @($jsonArrayText | ConvertFrom-Json)
    }
    return $records
}

function Mask-Key([string]$Key) {
    $clean = $Key.Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return "empty"
    }
    if ($clean.Length -le 8) {
        return "set len=$($clean.Length)"
    }
    return "set len=$($clean.Length) masked=$($clean.Substring(0, 4))...$($clean.Substring($clean.Length - 4))"
}

function Get-RecordApiKeyFromDeviceState {
    param(
        [string]$Model,
        [string]$Endpoint
    )
    if ($NoDeviceState) {
        return ""
    }
    $stateText = Read-AppFileText "files/play_with_me_state.json"
    if ([string]::IsNullOrWhiteSpace($stateText)) {
        return ""
    }
    $state = $stateText | ConvertFrom-Json
    $configs = @()
    if ($state.model_configs -is [Array]) {
        $configs = @($state.model_configs)
    } elseif ($state.models -is [Array]) {
        $configs = @($state.models)
    }
    if ($configs.Count -eq 0) {
        return ""
    }
    $endpointClean = $Endpoint.TrimEnd("/")
    foreach ($config in $configs) {
        $configModel = [string]$config.model
        $configEndpoint = ([string]$config.endpoint).TrimEnd("/")
        if ($configModel -eq $Model -and $configEndpoint -eq $endpointClean) {
            return ([string]$config.api_key).Trim()
        }
    }
    foreach ($config in $configs) {
        if ([string]$config.model -eq $Model) {
            return ([string]$config.api_key).Trim()
        }
    }
    return ""
}

function Header-Map {
    param(
        [string]$Provider,
        [string]$Key
    )
    $headers = @{
        "Accept" = "application/json"
    }
    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        if ($Provider -eq "anthropic") {
            $headers["x-api-key"] = $Key
        } elseif ($Provider -eq "gemini") {
            $headers["x-goog-api-key"] = $Key
        } else {
            $headers["Authorization"] = "Bearer $Key"
        }
    }
    return $headers
}

function Redacted-Headers {
    param($Headers)
    $redacted = @{}
    foreach ($key in $Headers.Keys) {
        if ($key -in @("Authorization", "x-api-key", "x-goog-api-key")) {
            $redacted[$key] = "set"
        } else {
            $redacted[$key] = $Headers[$key]
        }
    }
    return $redacted
}

$rawPath = Resolve-RawJsonlPath $RawJsonl
$rawText = ""
if (-not [string]::IsNullOrWhiteSpace($rawPath)) {
    $rawText = Get-Content -Path $rawPath -Raw -Encoding UTF8
} else {
    $rawText = Read-AppFileText "files/werewolf_bot_prompts.jsonl"
}
if ([string]::IsNullOrWhiteSpace($rawText)) {
    throw "No raw werewolf prompt JSONL found. Pass -RawJsonl or -Device."
}

$records = Parse-JsonlRecords $rawText
$record = $records | Where-Object { [int]$_.sequence -eq $Sequence } | Select-Object -First 1
if ($record -eq $null) {
    throw "No request found for sequence=$Sequence"
}

$modelRequest = $record.modelRequestPayload
if ($modelRequest -eq $null) {
    throw "Request sequence=$Sequence has no modelRequestPayload."
}
$payload = $modelRequest.payload
if ($payload -eq $null) {
    throw "Request sequence=$Sequence has no payload."
}

$url = [string]$modelRequest.url
if ([string]::IsNullOrWhiteSpace($url)) {
    throw "Request sequence=$Sequence has no url."
}
$provider = [string]$modelRequest.provider
$model = [string]$modelRequest.model
$endpoint = [string]$modelRequest.endpoint

$effectiveApiKey = $ApiKey.Trim()
if ([string]::IsNullOrWhiteSpace($effectiveApiKey)) {
    $effectiveApiKey = Get-RecordApiKeyFromDeviceState -Model $model -Endpoint $endpoint
}
if ([string]::IsNullOrWhiteSpace($effectiveApiKey)) {
    throw "No API key found. Pass -ApiKey or use -Device so the script can read files/play_with_me_state.json."
}

$payloadJson = $payload | ConvertTo-Json -Depth 100
$requestPayloadPath = Join-Path $OutDir "request_payload.json"
$requestMessagesPath = Join-Path $OutDir "request_messages.json"
$requestRecordPath = Join-Path $OutDir "source_record.redacted.json"
$responsePath = Join-Path $OutDir "response_body.txt"
$metadataPath = Join-Path $OutDir "metadata.json"

Set-Content -Path $requestPayloadPath -Value $payloadJson -Encoding UTF8
Set-Content -Path $requestMessagesPath -Value ($record.messages | ConvertTo-Json -Depth 100) -Encoding UTF8
Set-Content -Path $requestRecordPath -Value ($record | ConvertTo-Json -Depth 100) -Encoding UTF8

$headers = Header-Map -Provider $provider -Key $effectiveApiKey
$started = Get-Date
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$ok = $false
$statusCode = 0
$errorText = ""
$bodyText = ""

Write-Host ("replay sequence={0} actor={1} action={2} model={3} url={4}" -f $Sequence, [string]$record.actorTitle, [string]$record.actionKey, $model, $url)
Write-Host ("api_key={0} timeout={1}s payload_chars={2}" -f (Mask-Key $effectiveApiKey), $TimeoutSec, $payloadJson.Length)

try {
    $response = Invoke-WebRequest `
        -Method Post `
        -Uri $url `
        -Headers $headers `
        -ContentType "application/json; charset=utf-8" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($payloadJson)) `
        -TimeoutSec $TimeoutSec `
        -UseBasicParsing
    $statusCode = [int]$response.StatusCode
    $bodyText = [string]$response.Content
    $ok = $true
} catch {
    $errorText = $_.Exception.Message
    if ($_.Exception.Response -ne $null) {
        try {
            $statusCode = [int]$_.Exception.Response.StatusCode
            $stream = $_.Exception.Response.GetResponseStream()
            if ($stream -ne $null) {
                $reader = New-Object System.IO.StreamReader($stream)
                $bodyText = $reader.ReadToEnd()
                $reader.Close()
            }
        } catch {
            if ([string]::IsNullOrWhiteSpace($bodyText)) {
                $bodyText = ""
            }
        }
    }
} finally {
    $stopwatch.Stop()
}

Set-Content -Path $responsePath -Value $bodyText -Encoding UTF8

$metadata = [ordered]@{
    ok = $ok
    statusCode = $statusCode
    error = $errorText
    elapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    startedAt = $started.ToString("o")
    sequence = $Sequence
    actorTitle = [string]$record.actorTitle
    actorRole = [string]$record.actorRole
    day = [int]$record.day
    phase = [string]$record.phase
    actionKey = [string]$record.actionKey
    purpose = [string]$modelRequest.purpose
    provider = $provider
    endpoint = $endpoint
    url = $url
    model = $model
    outputType = [string]$modelRequest.output_type
    outputAdapter = [string]$modelRequest.output_adapter
    reasonAdapter = [string]$modelRequest.reason_adapter
    payloadSchema = [string]$modelRequest.payload_schema
    timeoutSec = $TimeoutSec
    requestPayloadChars = $payloadJson.Length
    responseChars = $bodyText.Length
    apiKey = Mask-Key $effectiveApiKey
    headers = Redacted-Headers $headers
    files = @{
        requestPayload = $requestPayloadPath
        requestMessages = $requestMessagesPath
        sourceRecord = $requestRecordPath
        responseBody = $responsePath
    }
}
Set-Content -Path $metadataPath -Value ($metadata | ConvertTo-Json -Depth 20) -Encoding UTF8

Write-Host ("done ok={0} status={1} elapsed={2}s response_chars={3}" -f $ok, $statusCode, $metadata.elapsedSeconds, $bodyText.Length)
Write-Host "wrote $metadataPath"
Write-Host "wrote $responsePath"

if ($PrintBody -and -not [string]::IsNullOrWhiteSpace($bodyText)) {
    Write-Host "----- response body -----"
    Write-Host $bodyText
}
