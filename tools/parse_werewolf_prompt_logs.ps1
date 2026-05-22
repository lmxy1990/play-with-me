param(
    [string]$RawJsonl = "",
    [string]$InputDir = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RawJsonlPath {
    if (-not [string]::IsNullOrWhiteSpace($RawJsonl)) {
        if (Test-Path -LiteralPath $RawJsonl -PathType Container) {
            $candidate = Join-Path $RawJsonl "raw_werewolf_bot_prompts.jsonl"
            if (-not (Test-Path -LiteralPath $candidate)) {
                throw "raw_werewolf_bot_prompts.jsonl not found under: $RawJsonl"
            }
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        if (-not (Test-Path -LiteralPath $RawJsonl)) {
            throw "RawJsonl not found: $RawJsonl"
        }
        return (Resolve-Path -LiteralPath $RawJsonl).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($InputDir)) {
        $candidate = Join-Path $InputDir "raw_werewolf_bot_prompts.jsonl"
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "raw_werewolf_bot_prompts.jsonl not found under: $InputDir"
        }
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    $latest = Get-ChildItem -Path (Join-Path $repoRoot "exports") -Filter "raw_werewolf_bot_prompts.jsonl" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latest -eq $null) {
        throw "No raw_werewolf_bot_prompts.jsonl found. Pass -RawJsonl or -InputDir."
    }
    return $latest.FullName
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

function Safe-FileName([string]$Value) {
    $name = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "unknown"
    }
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $name = $name.Replace([string]$char, "_")
    }
    $name = ($name -replace "\s+", "_")
    if ($name.Length -gt 90) {
        $name = $name.Substring(0, 90)
    }
    return $name
}

function Add-Lines($Target, $Source) {
    foreach ($line in $Source) {
        $Target.Add($line)
    }
}

function Get-RecordRole($Record) {
    $role = [string]$Record.actorRole
    if ([string]::IsNullOrWhiteSpace($role)) {
        $role = [string]$Record.actorRoleKey
    }
    if ([string]::IsNullOrWhiteSpace($role)) {
        $role = "未知身份"
    }
    return $role
}

function Get-MessageContent($Record, [string]$Role) {
    foreach ($message in $Record.messages) {
        if ([string]$message.role -eq $Role) {
            return [string]$message.content
        }
    }
    return ""
}

function Convert-UserPromptJson([string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $null
    }
    try {
        return ($Content | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Escape-Md([string]$Value) {
    return (($Value -replace "\|", "\|") -replace "`r?`n", "<br>")
}

function Add-Warning($Warnings, [string]$Code, [string]$Message, [string]$Evidence) {
    [void]$Warnings.Add([pscustomobject]@{
        code = $Code
        message = $Message
        evidence = $Evidence
    })
}

function Get-KnownRoleText($UserPrompt) {
    if ($UserPrompt -eq $null -or -not ($UserPrompt.players -is [Array])) {
        return ""
    }
    $items = @()
    foreach ($player in $UserPrompt.players) {
        $items += ("{0}:{1}" -f [int]$player.seatNumber, [string]$player.role)
    }
    return ($items -join ", ")
}

function Has-IdiotVoteRevealEvidence($UserPrompt, [int]$Seat) {
    if ($UserPrompt -eq $null -or -not ($UserPrompt.timeline -is [Array]) -or $Seat -le 0) {
        return $false
    }

    $seatText = [regex]::Escape([string]$Seat)
    foreach ($line in $UserPrompt.timeline) {
        $text = [string]$line
        if (
            ($text -match ("{0}\s*号.*被投票放逐.*白痴翻牌" -f $seatText)) -or
            ($text -match ("{0}\s*号.*白痴翻牌.*投票" -f $seatText)) -or
            ($text -match ("{0}\s*号.*白痴翻牌免于出局" -f $seatText))
        ) {
            return $true
        }
    }
    return $false
}

function Get-VisibleRoleWarnings($Record, $UserPrompt) {
    $warnings = New-Object System.Collections.Generic.List[object]
    if ($UserPrompt -eq $null -or -not ($UserPrompt.players -is [Array])) {
        return $warnings
    }

    $phase = [string]$Record.phase
    if ($phase -in @("post_game_summary", "mvp_vote", "game_over", "completed")) {
        return $warnings
    }

    $actorSeat = [int]$Record.actorSeatNumber
    $actorRole = Get-RecordRole $Record
    foreach ($player in $UserPrompt.players) {
        $seat = [int]$player.seatNumber
        $role = [string]$player.role
        if ([string]::IsNullOrWhiteSpace($role) -or $role -eq "未知") {
            continue
        }
        if ($role -eq "白痴" -and (Has-IdiotVoteRevealEvidence $UserPrompt $seat)) {
            continue
        }

        if ($actorRole -ne "狼人" -and $seat -ne $actorSeat) {
            Add-Warning $warnings "hidden_role_visible" "非狼人视角看到了其它玩家隐藏身份。" ("{0}号={1}" -f $seat, $role)
        }

        if ($actorRole -eq "狼人" -and $role -ne "狼人" -and $seat -ne $actorSeat) {
            Add-Warning $warnings "non_wolf_role_visible_to_wolf" "狼人视角看到了非狼玩家隐藏身份。" ("{0}号={1}" -f $seat, $role)
        }
    }

    return $warnings
}

function Get-NightFactWarnings($UserPrompt) {
    $warnings = New-Object System.Collections.Generic.List[object]
    if ($UserPrompt -eq $null) {
        return $warnings
    }

    $state = [string]$UserPrompt.current_state
    $noNightFacts = ($state -match "首夜前|无夜间技能结果|没有查验结果|没有可见的夜间被刀信息")
    if (-not $noNightFacts -or -not ($UserPrompt.timeline -is [Array])) {
        return $warnings
    }

    $nightFactClaimPattern = "昨晚|昨夜|昨晚查|查了\d+号|查验.*(金水|查杀)|验.*(金水|查杀)|昨晚.*(刀|救|毒|守)|首夜.*(查|验|刀|救|毒|守)"
    foreach ($line in $UserPrompt.timeline) {
        $text = [string]$line
        if ($text.StartsWith("主持人:")) {
            continue
        }
        if ($text -match $nightFactClaimPattern) {
            Add-Warning $warnings "night_fact_claim_before_night" "上下文声明首夜前或无夜间结果，但历史发言出现夜间事实声明。" $text
        }
    }

    return $warnings
}

function Get-PromptPolicyWarnings($Record, [string]$SystemPrompt, $UserPrompt) {
    $warnings = New-Object System.Collections.Generic.List[object]
    $kind = [string]$Record.kind
    $role = Get-RecordRole $Record
    $state = if ($UserPrompt -ne $null) { [string]$UserPrompt.current_state } else { "" }

    $isPublicSpeech = $phase -in @("sheriff_speech", "day_discussion", "last_words")
    if ($kind -eq "speech" -and $isPublicSpeech -and $role -eq "狼人" -and ($SystemPrompt -notmatch "公开.*(不要|不得).*暴露|不要.*暴露.*狼队友|隐藏.*身份")) {
        Add-Warning $warnings "missing_wolf_public_privacy_guard" "狼人公开发言 prompt 没有明确要求隐藏狼队友和真实身份。" "system prompt lacks wolf public speech privacy guard"
    }

    if ($kind -eq "speech" -and ($SystemPrompt -match "未知不编") -and ($SystemPrompt -notmatch "游戏内.*撒谎|策略性.*伪装|不能编造系统事实")) {
        Add-Warning $warnings "ambiguous_no_fabrication_rule" "提示词中的未知不编没有区分游戏内策略伪装和编造未发生的系统事实。" "system prompt contains 未知不编"
    }

    return $warnings
}

function Build-RecordLines($Record, [int]$FallbackSequence) {
    $role = Get-RecordRole $Record
    $sequence = [int]$Record.sequence
    if ($sequence -le 0) {
        $sequence = $FallbackSequence
    }
    $payload = $Record.modelRequestPayload
    $payloadSchema = ""
    $outputAdapter = ""
    $reasonAdapter = ""
    $reasoningMode = ""
    $provider = ""
    $model = ""
    if ($payload -ne $null) {
        $payloadSchema = [string]$payload.payload_schema
        $outputAdapter = [string]$payload.output_adapter
        $reasonAdapter = [string]$payload.reason_adapter
        $reasoningMode = [string]$payload.reasoning_mode
        $provider = [string]$payload.provider
        $model = [string]$payload.model
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(("===== #{0} seat={1} 身份={2} 玩家={3} kind={4} action={5} provider={6} model={7} payload_schema={8} output_adapter={9} reason_adapter={10} reasoning_mode={11} =====" -f $sequence, [int]$Record.actorSeatNumber, $role, [string]$Record.actorTitle, [string]$Record.kind, [string]$Record.actionKey, $provider, $model, $payloadSchema, $outputAdapter, $reasonAdapter, $reasoningMode))

    foreach ($message in $Record.messages) {
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
    return $lines
}

$rawPath = Resolve-RawJsonlPath
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Split-Path -Parent $rawPath
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$rawText = Get-Content -Path $rawPath -Raw -Encoding UTF8
if ([string]::IsNullOrWhiteSpace($rawText)) {
    throw "Raw JSONL is empty: $rawPath"
}

$records = @(Parse-JsonlRecords $rawText)
if ($records.Count -eq 0) {
    throw "No prompt records parsed from: $rawPath"
}

$bySeatDir = Join-Path $OutDir "by_seat"
$byIdentityDir = Join-Path $OutDir "by_identity"
$byPlayerDir = Join-Path $OutDir "by_player"
New-Item -ItemType Directory -Force -Path $bySeatDir | Out-Null
New-Item -ItemType Directory -Force -Path $byIdentityDir | Out-Null
New-Item -ItemType Directory -Force -Path $byPlayerDir | Out-Null

$allLines = New-Object System.Collections.Generic.List[string]
$seatLines = @{}
$identityLines = @{}
$playerLines = @{}
$summaryRows = @()
$warningRows = New-Object System.Collections.Generic.List[object]
$expectedSeatNumbers = @()
$fallbackSequence = 0

foreach ($record in ($records | Sort-Object @{ Expression = { [int]$_.sequence } }, @{ Expression = { [int]$_.actorSeatNumber } })) {
    $fallbackSequence += 1
    $role = Get-RecordRole $record
    $actorTitle = [string]$record.actorTitle
    $seatNumber = [int]$record.actorSeatNumber
    $recordLines = Build-RecordLines $record $fallbackSequence
    Add-Lines $allLines $recordLines

    $seatKey = "seat_{0:00}_{1}_{2}" -f $seatNumber, $role, (Safe-FileName $actorTitle)
    if (-not $seatLines.ContainsKey($seatKey)) {
        $seatLines[$seatKey] = New-Object System.Collections.Generic.List[string]
    }
    Add-Lines $seatLines[$seatKey] $recordLines

    $identityKey = Safe-FileName $role
    if (-not $identityLines.ContainsKey($identityKey)) {
        $identityLines[$identityKey] = New-Object System.Collections.Generic.List[string]
    }
    Add-Lines $identityLines[$identityKey] $recordLines

    $playerKey = Safe-FileName ("{0}_{1}" -f $actorTitle, $role)
    if (-not $playerLines.ContainsKey($playerKey)) {
        $playerLines[$playerKey] = New-Object System.Collections.Generic.List[string]
    }
    Add-Lines $playerLines[$playerKey] $recordLines

    $systemPrompt = Get-MessageContent $record "system"
    $userPrompt = Convert-UserPromptJson (Get-MessageContent $record "user")
    if ($userPrompt -ne $null -and $userPrompt.players -is [Array]) {
        foreach ($player in $userPrompt.players) {
            $n = [int]$player.seatNumber
            if ($n -gt 0 -and -not $expectedSeatNumbers.Contains($n)) {
                $expectedSeatNumbers += $n
            }
        }
    }

    $recordWarnings = New-Object System.Collections.Generic.List[object]
    Add-Lines $recordWarnings (Get-VisibleRoleWarnings $record $userPrompt)
    Add-Lines $recordWarnings (Get-NightFactWarnings $userPrompt)
    Add-Lines $recordWarnings (Get-PromptPolicyWarnings $record $systemPrompt $userPrompt)

    foreach ($warning in $recordWarnings) {
        $warningRows.Add([pscustomobject]@{
            sequence = [int]$record.sequence
            seat = $seatNumber
            actorTitle = $actorTitle
            actorRole = $role
            code = [string]$warning.code
            message = [string]$warning.message
            evidence = [string]$warning.evidence
        })
    }

    $payload = $record.modelRequestPayload
    $payloadSchema = if ($payload -ne $null) { [string]$payload.payload_schema } else { "" }
    $outputAdapter = if ($payload -ne $null) { [string]$payload.output_adapter } else { "" }
    $reasonAdapter = if ($payload -ne $null) { [string]$payload.reason_adapter } else { "" }
    $reasoningMode = if ($payload -ne $null) { [string]$payload.reasoning_mode } else { "" }
    $provider = if ($payload -ne $null) { [string]$payload.provider } else { "" }
    $model = if ($payload -ne $null) { [string]$payload.model } else { "" }
    $endpoint = if ($payload -ne $null) { [string]$payload.endpoint } else { "" }
    $timeline = if ($userPrompt -ne $null -and $userPrompt.timeline -is [Array]) { @($userPrompt.timeline) } else { @() }

    $summaryRows += [pscustomobject]@{
        sequence = [int]$record.sequence
        seat = $seatNumber
        actorTitle = $actorTitle
        actorRole = $role
        actorRoleKey = [string]$record.actorRoleKey
        kind = [string]$record.kind
        actionKey = [string]$record.actionKey
        day = [int]$record.day
        phase = [string]$record.phase
        phaseLabel = [string]$record.phaseLabel
        currentQuestion = if ($userPrompt -ne $null) { [string]$userPrompt.current_question } else { "" }
        currentState = if ($userPrompt -ne $null) { [string]$userPrompt.current_state } else { "" }
        knownRoles = Get-KnownRoleText $userPrompt
        timelineCount = $timeline.Count
        lastTimeline = (($timeline | Select-Object -Last 1) -join "")
        provider = $provider
        model = $model
        endpoint = $endpoint
        payloadSchema = $payloadSchema
        outputAdapter = $outputAdapter
        reasonAdapter = $reasonAdapter
        reasoningMode = $reasoningMode
        warningCount = $recordWarnings.Count
    }
}

$allTextPath = Join-Path $OutDir "actual_model_prompts_by_seat.txt"
Set-Content -Path $allTextPath -Value $allLines -Encoding UTF8
Write-Host "exported $allTextPath"

$allIdentityTextPath = Join-Path $OutDir "actual_model_prompts_by_identity.txt"
$allIdentityLines = New-Object System.Collections.Generic.List[string]
foreach ($key in ($identityLines.Keys | Sort-Object)) {
    $allIdentityLines.Add(("######## identity={0} ########" -f $key))
    $allIdentityLines.Add("")
    Add-Lines $allIdentityLines $identityLines[$key]
}
Set-Content -Path $allIdentityTextPath -Value $allIdentityLines -Encoding UTF8
Write-Host "exported $allIdentityTextPath"

foreach ($key in ($seatLines.Keys | Sort-Object)) {
    $path = Join-Path $bySeatDir ("$key.txt")
    Set-Content -Path $path -Value $seatLines[$key] -Encoding UTF8
    Write-Host "exported $path"
}

foreach ($key in ($identityLines.Keys | Sort-Object)) {
    $path = Join-Path $byIdentityDir ("$key.txt")
    Set-Content -Path $path -Value $identityLines[$key] -Encoding UTF8
    Write-Host "exported $path"
}

foreach ($key in ($playerLines.Keys | Sort-Object)) {
    $path = Join-Path $byPlayerDir ("$key.txt")
    Set-Content -Path $path -Value $playerLines[$key] -Encoding UTF8
    Write-Host "exported $path"
}

$summaryCsv = Join-Path $OutDir "prompt_summary.csv"
$summaryRows | Sort-Object seat, sequence | Export-Csv -Path $summaryCsv -NoTypeInformation -Encoding UTF8
Write-Host "exported $summaryCsv"

$warningsCsv = Join-Path $OutDir "prompt_warnings.csv"
$warningRows | Export-Csv -Path $warningsCsv -NoTypeInformation -Encoding UTF8
Write-Host "exported $warningsCsv"

$summaryMd = New-Object System.Collections.Generic.List[string]
$summaryMd.Add("# Werewolf Prompt Summary")
$summaryMd.Add("")
$summaryMd.Add(('- raw: `{0}`' -f $rawPath))
$summaryMd.Add(("- records: {0}" -f $records.Count))
$summaryMd.Add(("- generated_at: {0}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")))
if ($expectedSeatNumbers.Count -gt 0) {
    $requestedSeats = @($summaryRows | ForEach-Object { [int]$_.seat } | Sort-Object -Unique)
    $missingSeats = @($expectedSeatNumbers | Where-Object { -not $requestedSeats.Contains([int]$_) } | Sort-Object)
    if ($missingSeats.Count -gt 0) {
        $summaryMd.Add("- missing_model_requests: $($missingSeats -join ', ')")
    }
}
$summaryMd.Add("")
$summaryMd.Add("## Seat Index")
$summaryMd.Add("")
$summaryMd.Add("| seq | seat | role | actor | kind | phase | warnings |")
$summaryMd.Add("| --- | ---: | --- | --- | --- | --- | ---: |")
foreach ($row in ($summaryRows | Sort-Object seat, sequence)) {
    $summaryMd.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f $row.sequence, $row.seat, (Escape-Md $row.actorRole), (Escape-Md $row.actorTitle), (Escape-Md $row.kind), (Escape-Md $row.phaseLabel), $row.warningCount))
}

$summaryMd.Add("")
$summaryMd.Add("## Warnings")
$summaryMd.Add("")
if ($warningRows.Count -eq 0) {
    $summaryMd.Add("No warnings detected by the static parser.")
} else {
    $summaryMd.Add("| seq | seat | code | message | evidence |")
    $summaryMd.Add("| --- | ---: | --- | --- | --- |")
    foreach ($warning in $warningRows) {
        $summaryMd.Add(("| {0} | {1} | {2} | {3} | {4} |" -f $warning.sequence, $warning.seat, (Escape-Md $warning.code), (Escape-Md $warning.message), (Escape-Md $warning.evidence)))
    }
}

$summaryMd.Add("")
$summaryMd.Add("## Prompt Review Notes")
$summaryMd.Add("")
$summaryMd.Add('- `ambiguous_no_fabrication_rule`: `未知不编` 对狼人杀不够精确；建议区分“可以策略伪装”和“不能编造系统事实或未发生夜间结果”。')
$summaryMd.Add('- `missing_wolf_public_privacy_guard`: 狼人公开发言应明确要求不要暴露狼队友和真实身份。')

$summaryMdPath = Join-Path $OutDir "prompt_analysis.md"
Set-Content -Path $summaryMdPath -Value $summaryMd -Encoding UTF8
Write-Host "exported $summaryMdPath"

$metadata = [ordered]@{
    rawJsonl = $rawPath
    outDir = (Resolve-Path -LiteralPath $OutDir).Path
    recordCount = $records.Count
    warningCount = $warningRows.Count
    generatedAt = (Get-Date).ToString("o")
    files = @{
        allBySeat = $allTextPath
        allByIdentity = $allIdentityTextPath
        summaryCsv = $summaryCsv
        warningsCsv = $warningsCsv
        analysis = $summaryMdPath
        bySeatDir = $bySeatDir
        byIdentityDir = $byIdentityDir
        byPlayerDir = $byPlayerDir
    }
}
$metadataPath = Join-Path $OutDir "prompt_parse_metadata.json"
Set-Content -Path $metadataPath -Value ($metadata | ConvertTo-Json -Depth 20) -Encoding UTF8
Write-Host "exported $metadataPath"
