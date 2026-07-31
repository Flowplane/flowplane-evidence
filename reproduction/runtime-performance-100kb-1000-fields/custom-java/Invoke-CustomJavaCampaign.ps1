[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
  [Parameter(Mandatory)][ValidateSet('Plan','Run','Recover','CleanupPlan','Cleanup')][string]$Action,
  [Parameter(Mandatory)][string]$CampaignId,
  [switch]$Execute,
  [string]$ConfirmCampaignId,
  [int]$ProducerRate = 0,
  [ValidateRange(60,86400)][int]$WarmupPublisherTimeoutSeconds = 1800,
  [ValidateRange(60,86400)][int]$MeasuredPublisherTimeoutSeconds = 7200,
  [ValidateRange(60,86400)][int]$MeasuredDrainTimeoutSeconds = 7200,
  [string]$ValidEvidencePathOverride,
  [string]$PolicyEvidencePathOverride,
  [string]$PlanOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$benchmarkRoot = [IO.Path]::GetFullPath((Join-Path $moduleRoot '..'))
$resultsRoot = Join-Path $benchmarkRoot 'results'
$globalLock = Join-Path $resultsRoot 'active-campaign.lock.json'
$mapping = Join-Path $benchmarkRoot 'mapping\mapping.dsl'
$corpus = Join-Path $benchmarkRoot 'workload\generated\valid-payloads-100kb.jsonl'
$oracle = Join-Path $moduleRoot 'oracle\grpc-hard-valid-flowplane.jsonl'
$validEvidencePath = if ($ValidEvidencePathOverride) { [IO.Path]::GetFullPath($ValidEvidencePathOverride) } else { Join-Path $moduleRoot 'policy\generated\valid-parity-evidence.json' }
$policyEvidencePath = if ($PolicyEvidencePathOverride) { [IO.Path]::GetFullPath($PolicyEvidencePathOverride) } else { Join-Path $moduleRoot 'policy\generated\policy-parity-evidence.json' }
$artifactAuditPath = Join-Path $moduleRoot 'policy\generated\custom-java-artifact-audit.json'
$jar = Join-Path $moduleRoot 'target\custom-java-json-runtime.jar'
$publisher = Join-Path $benchmarkRoot 'workload\publisher\publisher.py'
$brokerJfrCollector = Join-Path $benchmarkRoot 'scripts\allocation-components\Invoke-KafkaBrokerJfr.ps1'
$dockerfile = Join-Path $moduleRoot 'Dockerfile'
$expectedMapping = '007b1546713568882b12a884cdcc85031746e32855770ef0306ae3bebfd7fc31'
$expectedCorpus = 'ba3fc084ce067c2ef6b52b7326760889b492e6ad8dc553a0a2aecf4bf0c7a607'

if ($CampaignId -notmatch '^[a-z0-9][a-z0-9-]{2,62}$') {
  throw 'CampaignId must be 3-63 lowercase letters, digits, or hyphens'
}
if ($ProducerRate -lt 0 -or $ProducerRate -gt 1000000) { throw 'ProducerRate must be 0..1000000' }

$prefix = "fpbench-custom-java-$CampaignId"
$names = [ordered]@{
  prefix = $prefix
  runtimeContainer = "$prefix-runtime"
  image = "flowplane-benchmark/custom-java-json-runtime:$CampaignId"
  rawTopic = "$prefix-raw"
  outputTopic = "$prefix-output"
  dlqTopic = "$prefix-dlq"
  consumerGroup = "$prefix-consumer"
}
$campaignDir = Join-Path $resultsRoot $CampaignId
$evidenceDir = Join-Path $campaignDir 'custom-java-runtime'
$runtimeJfr = Join-Path $evidenceDir 'custom-java-runtime.jfr'
$producerJfr = Join-Path $evidenceDir 'source-producer.jfr'
$brokerJfr = Join-Path $evidenceDir 'kafka-broker.jfr'
$brokerJfrStartEvidence = Join-Path $evidenceDir 'kafka-broker-jfr-start.json'
$brokerJfrEvidence = Join-Path $evidenceDir 'kafka-broker-jfr-evidence.json'
$warmupManifest = Join-Path $evidenceDir 'warmup-publisher.json'
$publisherManifest = Join-Path $evidenceDir 'measured-publisher.json'
$manifestPath = Join-Path $campaignDir 'custom-java-campaign-manifest.json'
$provenancePath = Join-Path $campaignDir 'custom-java-provenance.json'

function Read-RequiredJson([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required evidence is missing: $Path" }
  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}
function Sha([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file is missing: $Path" }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Write-Json([string]$Path, $Value) {
  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30) + "`n", [Text.UTF8Encoding]::new($false))
}
function Acquire-CampaignLock($Value) {
  $parent = Split-Path -Parent $globalLock
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 10) + "`n")
  try {
    $stream = [IO.File]::Open($globalLock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
  } catch [IO.IOException] {
    $owner = Read-ActiveLock
    $description = if ($null -eq $owner) { 'an unreadable concurrent owner' } else { "campaign '$($owner.campaignId)' ($($owner.runtime), $($owner.state))" }
    throw "Cannot acquire the global benchmark lock; it belongs to $description"
  }
}
function Stop-PublisherProcess($Process) {
  if ($null -ne $Process) {
    $Process.Refresh()
    if (-not $Process.HasExited) {
      Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
      try { $Process.WaitForExit() } catch {}
      $Process.Refresh()
    }
  }
}
function Invoke-Docker([string[]]$Arguments, [switch]$AllowFailure) {
  $priorErrorActionPreference = $ErrorActionPreference
  try {
    $script:ErrorActionPreference = 'Continue'
    $output = @(& docker @Arguments 2>&1)
    $code = $LASTEXITCODE
  } finally {
    $script:ErrorActionPreference = $priorErrorActionPreference
  }
  if ($code -ne 0 -and -not $AllowFailure) { throw "docker $($Arguments -join ' ') failed ($code): $($output -join [Environment]::NewLine)" }
  return [ordered]@{ exitCode=$code; output=@($output | ForEach-Object { [string]$_ }) }
}
function Sum-TopicOffsets([object[]]$Lines) {
  [long]$sum = 0
  foreach ($line in @($Lines)) {
    if ([string]$line -match ':(\d+)$') { $sum += [long]$Matches[1] }
  }
  return $sum
}
function Get-TopicOffset([string]$Topic) {
  $raw = (Invoke-Docker @('exec','flowplane-kafka','kafka-get-offsets','--bootstrap-server','kafka:9092','--topic',$Topic)).output
  return [ordered]@{total=(Sum-TopicOffsets $raw);partitions=@($raw)}
}
function Get-OffsetSnapshot {
  return [ordered]@{
    capturedAtUtc=[DateTime]::UtcNow.ToString('o')
    input=Get-TopicOffset $names.rawTopic
    output=Get-TopicOffset $names.outputTopic
    dlq=Get-TopicOffset $names.dlqTopic
  }
}
function Get-ConsumerLagSnapshot {
  $description = Invoke-Docker @('exec','flowplane-kafka','kafka-consumer-groups','--bootstrap-server','kafka:9092','--describe','--group',$names.consumerGroup) -AllowFailure
  [long]$sum = 0
  [long]$committed = 0
  [long]$logEnd = 0
  $observed = 0
  foreach ($line in @($description.output)) {
    $columns = @(([string]$line).Trim() -split '\s+')
    if ($columns.Count -ge 6 -and $columns[0] -eq $names.consumerGroup -and $columns[5] -match '^\d+$') {
      $sum += [long]$columns[5]
      $committed += [long]$columns[3]
      $logEnd += [long]$columns[4]
      $observed++
    }
  }
  return [ordered]@{capturedAtUtc=[DateTime]::UtcNow.ToString('o');available=($description.exitCode -eq 0 -and $observed -gt 0);total=$sum;committedOffsetTotal=$committed;logEndOffsetTotal=$logEnd;partitionsObserved=$observed;raw=$description.output}
}
function Wait-WarmupDrain([int]$TimeoutSeconds = 1800) {
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    $snapshot = Get-OffsetSnapshot
    if (($snapshot.output.total + $snapshot.dlq.total) -ge 10000) { return $snapshot }
    if ([DateTime]::UtcNow -ge $deadline) { throw 'Warmup did not drain 10000 records before timeout' }
    Start-Sleep -Seconds 2
  } while ($true)
}
function Assert-ParityGates {
  if ((Sha $mapping) -ne $expectedMapping) { throw 'Exact hard mapping SHA-256 does not match the custom runtime' }
  if ((Sha $corpus) -ne $expectedCorpus) { throw 'Exact 100-variant corpus SHA-256 changed' }
  $valid = Read-RequiredJson $validEvidencePath
  if ($valid.schemaVersion -ne 1 -or $valid.kind -ne 'custom-java-valid-parity-evidence' -or
      $valid.parityState -ne 'PROVEN' -or $valid.mappingSha256 -ne $expectedMapping -or
      $valid.corpusSha256 -ne $expectedCorpus -or $valid.payloadVariantCount -ne 100 -or
      $valid.payloadBytesEach -ne 102400 -or $valid.outputFieldCount -ne 1000 -or
      $valid.byteExactRecordCount -ne 100 -or @($valid.differences).Count -ne 0 -or
      $valid.manualDownstreamInsertionUsed -ne $false -or $valid.jarSha256 -ne (Sha $jar) -or
      $valid.oracleSha256 -ne (Sha $oracle)) {
    throw 'Valid byte-exact parity evidence is not PROVEN for the current mapping/corpus/oracle/JAR'
  }
  $policy = Read-RequiredJson $policyEvidencePath
  if ($policy.schemaVersion -ne 1 -or $policy.kind -ne 'custom-java-policy-parity-evidence' -or
      $policy.parityState -ne 'PROVEN' -or $policy.mappingSha256 -ne $expectedMapping -or
      $policy.expectedRecordCount -ne 6 -or $policy.actualRecordCount -ne 6 -or
      [string]::IsNullOrWhiteSpace([string]$policy.expectedSha256) -or
      $policy.expectedSha256 -ne $policy.actualSha256 -or
      $policy.competitorArtifact.sha256 -ne (Sha $jar) -or
      @($policy.differences).Count -ne 0 -or $policy.manualDownstreamInsertionUsed -ne $false -or
      $policy.orderedFieldErrorsCompared -ne $true -or
      $policy.httpErrorEnvelopeSemanticsCompared -ne $true -or
      $policy.transformErrorCompared -ne $true -or $policy.dlqEnvelopeCompared -ne $true -or
      $policy.kafkaKeyBytesCompared -ne $true -or $policy.kafkaHeaderOrderAndBytesCompared -ne $true) {
    throw 'Policy/error/key/header parity evidence is not PROVEN'
  }
  $audit = Read-RequiredJson $artifactAuditPath
  if ($audit.schemaVersion -ne 3 -or $audit.kind -ne 'custom-java-artifact-audit' -or
      $audit.artifact.sha256 -ne (Sha $jar) -or $audit.artifact.flowPlaneCoreEntryCount -ne 0 -or
      $audit.artifact.flowPlaneRuntimeEntryCount -ne 0 -or $audit.artifact.unexpectedOracleOrCorpusEntries -ne 0 -or
      $audit.dependencies.flowPlaneRuntimeDependencyCount -ne 0 -or $audit.dependencies.jdepsFlowPlaneReferenceCount -ne 0 -or
      $audit.tests.total -ne 4 -or $audit.tests.failures -ne 0 -or $audit.tests.errors -ne 0 -or
      $audit.parity.evidenceSha256 -ne (Sha $policyEvidencePath) -or $audit.parity.recordCount -ne 6 -or
      $audit.parity.byteEqual -ne $true -or $audit.livePolicyPath.kafkaDlqCallsSharedSerializer -ne $true -or
      $audit.livePolicyPath.allOrderedErrorsSerialized -ne $true -or
      $audit.livePolicyPath.transformationErrorInputParseProjection -ne $true -or
      $audit.livePolicyPath.producerKeyAndOrderedHeadersPreserved -ne $true -or
      $audit.liveTrafficUsed -ne $false -or $audit.manualDownstreamInsertionUsed -ne $false) {
    throw 'Final custom Java artifact audit is not valid for the current JAR and 6-canary parity evidence'
  }
  return [ordered]@{
    valid=[ordered]@{path=$validEvidencePath;sha256=Sha $validEvidencePath}
    policy=[ordered]@{path=$policyEvidencePath;sha256=Sha $policyEvidencePath}
    artifactAudit=[ordered]@{path=$artifactAuditPath;sha256=Sha $artifactAuditPath}
  }
}
function Read-ActiveLock {
  if (Test-Path -LiteralPath $globalLock -PathType Leaf) { return Read-RequiredJson $globalLock }
  return $null
}
function Cleanup-Actions {
  return @(
    [ordered]@{kind='container';target=$names.runtimeContainer;guard="flowplane.benchmark.campaign-id=$CampaignId";action='inspect exact name and matching labels; if running docker stop --time 30; then docker rm without force'},
    [ordered]@{kind='topic';target=$names.rawTopic;action='delete exact topic'},
    [ordered]@{kind='topic';target=$names.outputTopic;action='delete exact topic'},
    [ordered]@{kind='topic';target=$names.dlqTopic;action='delete exact topic'},
    [ordered]@{kind='consumer-group';target=$names.consumerGroup;action='delete exact group'},
    [ordered]@{kind='global-lock';target=$globalLock;guard="campaignId=$CampaignId";action='remove only matching lock'},
    [ordered]@{kind='reports';target=$campaignDir;action='preserve all reports and JFR evidence'}
  )
}
function Get-RecoveryValidation {
  $lock = Read-ActiveLock
  if ($null -eq $lock -or $lock.campaignId -ne $CampaignId -or $lock.runtime -ne 'CUSTOM_JAVA_JSON') {
    throw 'Recovery requires the global lock to belong to this CUSTOM_JAVA_JSON campaign'
  }
  if (-not (Test-Path -LiteralPath $campaignDir -PathType Container)) { throw 'Recovery campaign directory is missing' }
  $warmup = Read-RequiredJson $warmupManifest
  $measured = Read-RequiredJson $publisherManifest
  if ($warmup.status -ne 'COMPLETE' -or $warmup.mode -ne 'warmup' -or $warmup.sentRecordCount -ne 10000 -or
      $warmup.firstSequence -ne 0 -or $warmup.lastSequence -ne 9999 -or $warmup.payloadBytesEach -ne 102400 -or
      $warmup.kafkaKey -ne 'decimal measured sequence' -or $warmup.producerExitCode -ne 0 -or
      $warmup.producerFlushConfirmedByExit -ne $true -or $warmup.topic -ne $names.rawTopic) {
    throw 'Persisted warmup publisher evidence is not an exact completed 10000-record warmup'
  }
  if ($measured.status -ne 'COMPLETE' -or $measured.mode -ne 'measured' -or $measured.sentRecordCount -ne 500000 -or
      $measured.firstSequence -ne 0 -or $measured.lastSequence -ne 499999 -or $measured.payloadBytesEach -ne 102400 -or
      $measured.kafkaKey -ne 'decimal measured sequence' -or $measured.producerExitCode -ne 0 -or
      $measured.producerFlushConfirmedByExit -ne $true -or $measured.topic -ne $names.rawTopic) {
    throw 'Persisted measured publisher evidence is not an exact completed 500000-record publication'
  }
  $hostPublishers = @(Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and $_.CommandLine.Contains('publisher.py') -and $_.CommandLine.Contains($CampaignId)
  })
  $kafkaProcesses = Invoke-Docker @('top','flowplane-kafka','-eo','args') -AllowFailure
  $activeKafkaProducer = @($kafkaProcesses.output | Where-Object {
    ([string]$_).Contains('kafka-console-producer') -and ([string]$_).Contains($names.rawTopic)
  })
  if ($hostPublishers.Count -ne 0 -or $activeKafkaProducer.Count -ne 0) { throw 'Recovery refuses while a campaign publisher is active' }

  $inspect = Invoke-Docker @('inspect',$names.runtimeContainer)
  $container = (($inspect.output -join "`n") | ConvertFrom-Json)[0]
  if ($container.Config.Labels.'flowplane.benchmark' -ne 'true' -or
      $container.Config.Labels.'flowplane.benchmark.campaign-id' -ne $CampaignId -or
      $container.Config.Labels.'flowplane.benchmark.runtime' -ne 'CUSTOM_JAVA_JSON' -or
      $container.State.Running -ne $false -or $container.State.ExitCode -ne 0) {
    throw 'Recovery runtime ownership, stopped state, or exit code is invalid'
  }
  $offsets = Get-OffsetSnapshot
  if ($offsets.input.total -ne 510000 -or $offsets.output.total -ne 510000 -or $offsets.dlq.total -ne 0) {
    throw 'Recovery requires exact scoped topic totals raw=510000 output=510000 dlq=0'
  }
  $lag = Get-ConsumerLagSnapshot
  if (-not $lag.available -or $lag.partitionsObserved -ne 12 -or $lag.total -ne 0 -or
      $lag.committedOffsetTotal -ne 510000 -or $lag.logEndOffsetTotal -ne 510000) {
    throw 'Recovery requires 12 committed partitions totaling 510000 at zero lag'
  }
  $brokerStart = Read-RequiredJson $brokerJfrStartEvidence
  $brokerDump = Read-RequiredJson $brokerJfrEvidence
  if ($brokerStart.kind -ne 'flowplane-benchmark-kafka-broker-jfr' -or $brokerStart.action -ne 'Start' -or
      $brokerStart.campaignId -ne $CampaignId -or [string]::IsNullOrWhiteSpace([string]$brokerStart.startedAtUtc) -or
      $brokerDump.kind -ne 'flowplane-benchmark-kafka-broker-jfr' -or $brokerDump.action -ne 'DumpStop' -or
      $brokerDump.campaignId -ne $CampaignId -or $brokerDump.recordingStopped -ne $true) {
    throw 'Recovery broker JFR start/dump evidence is incomplete or mismatched'
  }
  foreach ($file in @($runtimeJfr,$producerJfr,$brokerJfr)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -le 0) {
      throw "Recovery JFR is missing or empty: $file"
    }
  }
  if ((Sha $producerJfr) -ne $measured.producerJfr.sha256 -or (Sha $brokerJfr) -ne $brokerDump.sha256 -or
      (Get-Item -LiteralPath $brokerJfr).Length -ne $brokerDump.recordingBytes) {
    throw 'Recovery JFR hash or size does not match persisted producer/broker evidence'
  }
  $windowStart = [DateTime]::Parse([string]$brokerStart.startedAtUtc).ToUniversalTime()
  $publishEnd = (Get-Item -LiteralPath $producerJfr).LastWriteTimeUtc
  $drainEnd = [DateTime]::Parse([string]$container.State.FinishedAt).ToUniversalTime()
  if ($windowStart -ge $publishEnd -or $publishEnd -gt $drainEnd) { throw 'Recovered measured-window timestamps are not monotonic' }
  $deltas = [ordered]@{input=500000;output=500000;dlq=0}
  return [ordered]@{
    schemaVersion=1;kind='custom-java-campaign-recovery-validation';campaignId=$CampaignId;recoverable=$true
    noRepublish=$true;activePublisherCount=0;parity=$parity
    warmup=[ordered]@{manifest=$warmupManifest;sha256=Sha $warmupManifest;records=10000;status='COMPLETE'}
    measured=[ordered]@{manifest=$publisherManifest;sha256=Sha $publisherManifest;records=500000;status='COMPLETE';producerExitCode=0;flushConfirmed=$true}
    runtime=[ordered]@{container=$names.runtimeContainer;imageId=$container.Image;exitCode=0;startedAtUtc=$container.State.StartedAt;finishedAtUtc=$container.State.FinishedAt;ownershipValidated=$true}
    finalOffsets=$offsets;consumerLag=$lag
    baselineOffsets=[ordered]@{input=10000;output=10000;dlq=0;derivation='exact scoped final totals minus the complete 500000-record measured manifest; cross-checked by the complete 10000-record warmup manifest'}
    measuredDeltas=$deltas
    measuredWindow=[ordered]@{
      startUtc=$windowStart.ToString('o');publishEndUtc=$publishEnd.ToString('o');drainEndUtc=$drainEnd.ToString('o')
      sharedBoundarySemantics='start is persisted broker JFR startedAtUtc; publishEnd is measured producer JFR host LastWriteTimeUtc after producer JVM dump/copy; drainEnd is Docker runtime FinishedAt after consuming the configured 510000 total records'
      inferenceLimit='publisher manifest has elapsed duration but no embedded wall-clock timestamps; producer JFR persisted time is used instead of inventing a timestamp'
    }
    jfr=[ordered]@{
      runtime=[ordered]@{path=$runtimeJfr;bytes=(Get-Item $runtimeJfr).Length;sha256=Sha $runtimeJfr;filterWindow='measuredWindow.startUtc..drainEndUtc'}
      producer=[ordered]@{path=$producerJfr;bytes=(Get-Item $producerJfr).Length;sha256=Sha $producerJfr}
      broker=[ordered]@{path=$brokerJfr;bytes=(Get-Item $brokerJfr).Length;sha256=Sha $brokerJfr;evidence=$brokerJfrEvidence}
    }
    dockerStats=[ordered]@{state='unavailable';reason='controller_process_terminated_before_in_memory_samples_were_persisted';samples=@();invented=$false}
    runtimeOnlyOutputInsertion=$true;manualDownstreamInsertionUsed=$false;liveStateMutationsPerformed=$false
  }
}

$active = Read-ActiveLock
$parityInputsPresent = (Test-Path -LiteralPath $validEvidencePath -PathType Leaf) -and
  (Test-Path -LiteralPath $policyEvidencePath -PathType Leaf) -and
  (Test-Path -LiteralPath $artifactAuditPath -PathType Leaf) -and
  (Test-Path -LiteralPath $jar -PathType Leaf) -and
  (Test-Path -LiteralPath $corpus -PathType Leaf)
$parity = if ($Action -in @('Run','Recover')) {
  Assert-ParityGates
} elseif ($Action -eq 'Plan' -and $parityInputsPresent) {
  Assert-ParityGates
} else {
  [ordered]@{
    state='NOT_PREPARED'
    runAllowed=$false
    reason='build the isolated JAR and generate valid, policy, and artifact-audit evidence before Run'
    required=@($jar,$validEvidencePath,$policyEvidencePath,$artifactAuditPath)
  }
}
$plan = [ordered]@{
  schemaVersion=1
  kind='custom-java-live-campaign-plan'
  campaignId=$CampaignId
  runtimeType='CUSTOM_JAVA_JSON'
  benchmarkOnly=$true
  dryRun=$true
  executable=($null -eq $active -and $parityInputsPresent)
  blockedByActiveCampaign=$active
  mappingSha256=$expectedMapping
  corpus=[ordered]@{sha256=$expectedCorpus;variants=100;payloadBytesEach=102400;warmupRecords=10000;measuredRecords=500000;runtimeExpectedTotal=510000;measuredRoundRobinCycles=5000}
  parity=$parity
  names=$names
  docker=[ordered]@{
    existingNetwork='flowplane-quality-stack_default'
    kafkaContainer='flowplane-kafka'
    kafkaBootstrap='kafka:9092'
    ephemeralCampaignOwnedContainer=$true
    composeUsed=$false
    labels=[ordered]@{'flowplane.benchmark'='true';'flowplane.benchmark.campaign-id'=$CampaignId;'flowplane.benchmark.runtime'='CUSTOM_JAVA_JSON'}
    jfr=[ordered]@{
      runtime=[ordered]@{enabled=$true;settings='profile';coversWarmupAndMeasured=$true;filterToMeasuredWindowLater=$true;hostOutput=$runtimeJfr}
      sourceProducer=[ordered]@{enabled=$true;measuredPublisherOnly=$true;warmupExcluded=$true;hostOutput=$producerJfr}
      kafkaBroker=[ordered]@{enabled=$true;existingCollector=$brokerJfrCollector;measuredWindowOnly=$true;warmupExcluded=$true;hostOutput=$brokerJfr;evidenceOutput=$brokerJfrEvidence}
    }
  }
  methodology=[ordered]@{
    corpusAndKeys=[ordered]@{corpusSha256=$expectedCorpus;roundRobinFormula='payloadVariantIndex = publisherSequence % 100';kafkaKey='ASCII decimal publisher sequence';warmupKeyRange='0..9999';measuredKeyRange='0..499999'}
    warmup=[ordered]@{records=10000;corpusVariants=100;payloadBytesEach=102400;publisherMode='warmup';producerJfr=$false;drainBeforeBaseline=$true}
    measured=[ordered]@{records=500000;publisherMode='measured';producerJfr=$true;baselineOffsetsRequired=$true;deltaInputRequired=500000;deltaOutputPlusDlqRequired=500000;zeroLagRequired=$true}
    runtimeExpectedTotal=510000
    measuredWindow=[ordered]@{startUtc='captured immediately after broker JFR start and before measured publisher';publishEndUtc='captured after measured publisher exits';drainEndUtc='captured after runtime exit, exact measured deltas, and zero lag'}
    outputProvenance='only the custom Java runtime writes output/DLQ; both publishers write raw topic only'
  }
  timeouts=[ordered]@{warmupPublisherSeconds=$WarmupPublisherTimeoutSeconds;measuredPublisherSeconds=$MeasuredPublisherTimeoutSeconds;measuredDrainSeconds=$MeasuredDrainTimeoutSeconds}
  dataPath='publisher -> raw Kafka topic -> custom Java runtime -> output or DLQ Kafka topic'
  manualDownstreamInsertionUsed=$false
  measurements=@('runtime JFR filtered to measured window','Kafka broker JFR measured window only','measured source-producer JFR','transform-only cumulative nanoseconds','5-second Docker CPU/memory stats during measured publish and drain','baseline/final input/output/DLQ offsets and exact measured deltas','zero consumer-group lag at drain','warmup and measured publisher duration/rate','container exit code','runtime-only output provenance','image/JAR/mapping/corpus provenance')
  exactCleanup=@(Cleanup-Actions)
  mutationsPerformed=$false
}

if ($Action -eq 'Plan') {
  if ($PlanOutputPath) {
    $resolvedPlanOutput = [IO.Path]::GetFullPath($PlanOutputPath)
    if (-not $resolvedPlanOutput.StartsWith($moduleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Dry-run plan output must remain under the isolated custom-java module: $moduleRoot"
    }
    Write-Json $resolvedPlanOutput $plan
  }
  $plan | ConvertTo-Json -Depth 30
  return
}
if ($Action -eq 'CleanupPlan') {
  [ordered]@{schemaVersion=1;kind='custom-java-cleanup-plan';campaignId=$CampaignId;dryRun=$true;actions=@(Cleanup-Actions);mutationsPerformed=$false} | ConvertTo-Json -Depth 20
  return
}

if ($Action -eq 'Recover') {
  $recovery = Get-RecoveryValidation
  if (-not $Execute) {
    [ordered]@{schemaVersion=1;kind='custom-java-campaign-recovery-plan';campaignId=$CampaignId;dryRun=$true;validation=$recovery;wouldWrite=@($provenancePath,$manifestPath,(Join-Path $evidenceDir 'runtime-output-provenance.json'),(Join-Path $evidenceDir 'custom-java-runtime.log'));republish=$false;liveStateMutationsPerformed=$false} | ConvertTo-Json -Depth 30
    return
  }
  if ($ConfirmCampaignId -cne $CampaignId) { throw '-ConfirmCampaignId must exactly match CampaignId' }
  foreach ($target in @($provenancePath,$manifestPath,(Join-Path $evidenceDir 'runtime-output-provenance.json'),(Join-Path $evidenceDir 'custom-java-runtime.log'))) {
    if (Test-Path -LiteralPath $target) { throw "Recovery refuses to overwrite an existing report: $target" }
  }
  if (-not $PSCmdlet.ShouldProcess($CampaignId, 'Write recovery provenance and DRAINED manifest without publishing or changing live state')) { return }
  $runtimeLogPath = Join-Path $evidenceDir 'custom-java-runtime.log'
  $runtimeLogResult = Invoke-Docker @('logs',$names.runtimeContainer)
  [IO.File]::WriteAllLines($runtimeLogPath,@($runtimeLogResult.output),[Text.UTF8Encoding]::new($false))
  $runtimeOutputProvenancePath = Join-Path $evidenceDir 'runtime-output-provenance.json'
  Write-Json $runtimeOutputProvenancePath ([ordered]@{
    schemaVersion=1;kind='custom-java-runtime-output-provenance';campaignId=$CampaignId;runtimeType='CUSTOM_JAVA_JSON'
    publisherDestinations=@($names.rawTopic);runtimeContainer=$names.runtimeContainer;runtimeImageId=$recovery.runtime.imageId
    runtimeDestinations=@($names.outputTopic,$names.dlqTopic);baselineOffsets=$recovery.baselineOffsets;finalOffsets=$recovery.finalOffsets
    measuredDeltas=$recovery.measuredDeltas;measuredOutputPlusDlq=500000;runtimeOnlyOutputInsertion=$true
    manualDownstreamInsertionUsed=$false;recoveredWithoutRepublish=$true
  })
  $recovery.runtimeLog=[ordered]@{path=$runtimeLogPath;sha256=Sha $runtimeLogPath}
  $recovery.runtimeOutputProvenance=[ordered]@{path=$runtimeOutputProvenancePath;sha256=Sha $runtimeOutputProvenancePath}
  $recovery.recoveredAtUtc=[DateTime]::UtcNow.ToString('o')
  $recovery.recoverySemantics='evidence-only reconstruction after controller exit-code observation race; no records republished and no container/topic/group/lock mutation performed'
  Write-Json $provenancePath $recovery
  Write-Json $manifestPath ([ordered]@{
    schemaVersion=1;kind='custom-java-campaign-manifest';campaignId=$CampaignId;runtimeType='CUSTOM_JAVA_JSON';state='DRAINED'
    warmupRecords=10000;measuredRecords=500000;runtimeExpectedTotal=510000;measuredWindow=$recovery.measuredWindow
    measuredDeltas=$recovery.measuredDeltas;consumerLag=$recovery.consumerLag;provenance=$provenancePath
    recoveredWithoutRepublish=$true;dockerStats=$recovery.dockerStats;cleanupRequired=$true
  })
  [ordered]@{campaignId=$CampaignId;state='DRAINED';provenance=$provenancePath;manifest=$manifestPath;republished=$false;liveStateMutationsPerformed=$false} | ConvertTo-Json -Depth 8
  return
}

if (-not $Execute) { throw "$Action requires -Execute" }
if ($ConfirmCampaignId -cne $CampaignId) { throw '-ConfirmCampaignId must exactly match CampaignId' }

if ($Action -eq 'Cleanup') {
  if (-not $PSCmdlet.ShouldProcess($CampaignId, 'Remove exact campaign-owned container/topics/group/lock while preserving reports')) { return }
  $inspect = Invoke-Docker @('inspect',$names.runtimeContainer) -AllowFailure
  if ($inspect.exitCode -eq 0) {
    $container = (($inspect.output -join "`n") | ConvertFrom-Json)[0]
    if ($container.Config.Labels.'flowplane.benchmark.campaign-id' -ne $CampaignId -or
        $container.Config.Labels.'flowplane.benchmark' -ne 'true') {
      throw 'Refusing cleanup: exact-name container does not carry matching benchmark ownership labels'
    }
    if ($container.State.Running -eq $true) {
      Invoke-Docker @('stop','--time','30',$names.runtimeContainer) | Out-Null
    }
    Invoke-Docker @('rm',$names.runtimeContainer) | Out-Null
  }
  foreach ($topic in @($names.rawTopic,$names.outputTopic,$names.dlqTopic)) {
    Invoke-Docker @('exec','flowplane-kafka','kafka-topics','--bootstrap-server','kafka:9092','--delete','--if-exists','--topic',$topic) | Out-Null
  }
  Invoke-Docker @('exec','flowplane-kafka','kafka-consumer-groups','--bootstrap-server','kafka:9092','--delete','--group',$names.consumerGroup) -AllowFailure | Out-Null
  $lock = Read-ActiveLock
  if ($null -ne $lock) {
    if ($lock.campaignId -ne $CampaignId) { throw "Refusing cleanup: active lock belongs to $($lock.campaignId)" }
    [IO.File]::Delete($globalLock)
  }
  Write-Json (Join-Path $campaignDir 'custom-java-cleaned.json') ([ordered]@{
    schemaVersion=1;kind='custom-java-campaign-cleanup';campaignId=$CampaignId;cleanedAtUtc=[DateTime]::UtcNow.ToString('o')
    exactCleanup=@(Cleanup-Actions);reportsPreserved=$true
  })
  return
}

if ($null -ne $active) { throw "Cannot overlap active campaign '$($active.campaignId)' ($($active.runtime), $($active.state))" }
if (Test-Path -LiteralPath $campaignDir) { throw "Campaign result directory already exists: $campaignDir" }
$owned = @((Invoke-Docker @('ps','-a','--filter',"label=flowplane.benchmark.campaign-id=$CampaignId",'--format','{{.Names}}')).output)
if (@($owned | Where-Object { $_ }).Count -ne 0) { throw 'Campaign-owned container already exists' }
if (-not $PSCmdlet.ShouldProcess($CampaignId, 'Create exact topics and run the isolated 500000-record custom Java campaign')) { return }

New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
Acquire-CampaignLock ([ordered]@{campaignId=$CampaignId;runtime='CUSTOM_JAVA_JSON';state='MEASURED_500K_RUNNING';manifest=$manifestPath;createdAtUtc=[DateTime]::UtcNow.ToString('o')})
$started = [DateTime]::UtcNow
try {
  if ((Sha $jar) -ne (Read-RequiredJson $validEvidencePath).jarSha256) { throw 'Current JAR differs from proven valid-parity JAR' }
  Invoke-Docker @('build','--label','flowplane.benchmark=true','--label',"flowplane.benchmark.campaign-id=$CampaignId",'-t',$names.image,'-f',$dockerfile,$moduleRoot) | Out-Null
  $imageId = ((Invoke-Docker @('image','inspect',$names.image,'--format','{{.Id}}')).output -join '').Trim()
  foreach ($topic in @($names.rawTopic,$names.outputTopic,$names.dlqTopic)) {
    Invoke-Docker @('exec','flowplane-kafka','kafka-topics','--bootstrap-server','kafka:9092','--create','--if-not-exists','--topic',$topic,'--partitions','12','--replication-factor','1','--config','retention.ms=86400000') | Out-Null
  }
  Invoke-Docker @('run','-d','--name',$names.runtimeContainer,'--network','flowplane-quality-stack_default',
    '--label','flowplane.benchmark=true','--label',"flowplane.benchmark.campaign-id=$CampaignId",'--label','flowplane.benchmark.runtime=CUSTOM_JAVA_JSON',
    '--mount',"type=bind,source=$evidenceDir,target=/evidence",'--mount',"type=bind,source=$mapping,target=/benchmark/mapping.dsl,readonly",
    '--entrypoint','java',$names.image,
    '-XX:StartFlightRecording=name=custom_java_measured,settings=profile,disk=true,dumponexit=true,maxsize=2g,filename=/evidence/custom-java-runtime.jfr',
    '-jar','/opt/flowplane-benchmark/runtime.jar','kafka','--mapping','/benchmark/mapping.dsl','--bootstrap','kafka:9092',
    '--input-topic',$names.rawTopic,'--output-topic',$names.outputTopic,'--dlq-topic',$names.dlqTopic,
    '--group-id',$names.consumerGroup,'--expected-records','510000') | Out-Null
  $warmupStdout = Join-Path $evidenceDir 'warmup-publisher.stdout.log'
  $warmupStderr = Join-Path $evidenceDir 'warmup-publisher.stderr.log'
  $warmupArgs = @($publisher,'--mode','warmup','--campaign-id',$CampaignId,'--topic',$names.rawTopic,
    '--count','10000','--rate',[string]$ProducerRate,'--fixture-path',$corpus,'--manifest',$warmupManifest,
    '--publish-timeout-seconds',[string]$WarmupPublisherTimeoutSeconds,
    '--execute','--confirm-campaign',$CampaignId)
  $warmupProcess = Start-Process -FilePath 'python' -ArgumentList $warmupArgs -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $warmupStdout -RedirectStandardError $warmupStderr
  $warmupDeadline = [DateTime]::UtcNow.AddSeconds($WarmupPublisherTimeoutSeconds)
  while (-not $warmupProcess.HasExited) {
    if ([DateTime]::UtcNow -ge $warmupDeadline) {
      Stop-PublisherProcess $warmupProcess
      Write-Json (Join-Path $evidenceDir 'warmup-publisher-timeout.json') ([ordered]@{
        schemaVersion=1;kind='custom-java-warmup-publisher-timeout';campaignId=$CampaignId
        atUtc=[DateTime]::UtcNow.ToString('o');timeoutSeconds=$WarmupPublisherTimeoutSeconds
        processId=$warmupProcess.Id;stdout=$warmupStdout;stderr=$warmupStderr
      })
      Invoke-Docker @('stop','--time','30',$names.runtimeContainer) -AllowFailure | Out-Null
      throw "Warmup publisher exceeded $WarmupPublisherTimeoutSeconds seconds"
    }
    Start-Sleep -Seconds 1
    $warmupProcess.Refresh()
  }
  $warmupProcess.WaitForExit(); $warmupProcess.Refresh()
  $warmupPublisherEvidence = Read-RequiredJson $warmupManifest
  if ($warmupPublisherEvidence.status -ne 'COMPLETE' -or $warmupPublisherEvidence.sentRecordCount -ne 10000 -or
      $warmupPublisherEvidence.producerExitCode -ne 0 -or $warmupPublisherEvidence.producerFlushConfirmedByExit -ne $true) {
    throw "Warmup publisher manifest did not prove completion (process exit $($warmupProcess.ExitCode))"
  }
  $warmupDrained = Wait-WarmupDrain
  if ($warmupDrained.input.total -ne 10000 -or ($warmupDrained.output.total + $warmupDrained.dlq.total) -ne 10000) {
    throw 'Warmup baseline must be exactly 10000 input and 10000 output+DLQ records'
  }
  $baselineOffsets = $warmupDrained

  $brokerStarted = $false
  $measuredWindow = [ordered]@{startUtc=$null;publishEndUtc=$null;drainEndUtc=$null}
  $statsSamples = [Collections.Generic.List[object]]::new()
  $finalOffsets = $null
  $lag = $null
  try {
    & $brokerJfrCollector -Action Start -CampaignId $CampaignId -EvidenceOutput $brokerJfrStartEvidence `
      -Execute -ConfirmCampaign $CampaignId -Confirm:$false | Out-Null
    $brokerStarted = $true
    $measuredWindow.startUtc = [DateTime]::UtcNow.ToString('o')
  $publisherStdout = Join-Path $evidenceDir 'measured-publisher.stdout.log'
  $publisherStderr = Join-Path $evidenceDir 'measured-publisher.stderr.log'
  $publisherArgs = @($publisher,'--mode','measured','--campaign-id',$CampaignId,'--topic',$names.rawTopic,
    '--count','500000','--rate',[string]$ProducerRate,'--fixture-path',$corpus,'--manifest',$publisherManifest,
    '--publish-timeout-seconds',[string]$MeasuredPublisherTimeoutSeconds,
    '--producer-jfr-output',$producerJfr,'--execute','--confirm-campaign',$CampaignId)
  $publisherProcess = Start-Process -FilePath 'python' -ArgumentList $publisherArgs -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $publisherStdout -RedirectStandardError $publisherStderr
  $publisherDeadline = [DateTime]::UtcNow.AddSeconds($MeasuredPublisherTimeoutSeconds)
  while (-not $publisherProcess.HasExited) {
    if ([DateTime]::UtcNow -ge $publisherDeadline) {
      Stop-PublisherProcess $publisherProcess
      Write-Json (Join-Path $evidenceDir 'measured-publisher-timeout.json') ([ordered]@{
        schemaVersion=1;kind='custom-java-measured-publisher-timeout';campaignId=$CampaignId
        atUtc=[DateTime]::UtcNow.ToString('o');timeoutSeconds=$MeasuredPublisherTimeoutSeconds
        processId=$publisherProcess.Id;sampleCount=$statsSamples.Count;stdout=$publisherStdout;stderr=$publisherStderr
      })
      Invoke-Docker @('stop','--time','30',$names.runtimeContainer) -AllowFailure | Out-Null
      throw "Measured publisher exceeded $MeasuredPublisherTimeoutSeconds seconds"
    }
    $sample = Invoke-Docker @('stats',$names.runtimeContainer,'--no-stream','--format','{{json .}}') -AllowFailure
    $statsSamples.Add([ordered]@{atUtc=[DateTime]::UtcNow.ToString('o');phase='measured-publish';exitCode=$sample.exitCode;sample=($sample.output -join '')})
    Start-Sleep -Seconds 5
    $publisherProcess.Refresh()
  }
  $publisherProcess.WaitForExit(); $publisherProcess.Refresh()
  $measuredPublisherEvidence = Read-RequiredJson $publisherManifest
  if ($measuredPublisherEvidence.status -ne 'COMPLETE' -or $measuredPublisherEvidence.sentRecordCount -ne 500000 -or
      $measuredPublisherEvidence.lastSequence -ne 499999 -or $measuredPublisherEvidence.producerExitCode -ne 0 -or
      $measuredPublisherEvidence.producerFlushConfirmedByExit -ne $true) {
    throw "Measured publisher manifest did not prove completion (process exit $($publisherProcess.ExitCode))"
  }
  $measuredWindow.publishEndUtc = [DateTime]::UtcNow.ToString('o')
  $drainDeadline = [DateTime]::UtcNow.AddSeconds($MeasuredDrainTimeoutSeconds)
  do {
    if ([DateTime]::UtcNow -ge $drainDeadline) {
      $timeoutEvidence = [ordered]@{
        schemaVersion=1;kind='custom-java-measured-drain-timeout';campaignId=$CampaignId
        atUtc=[DateTime]::UtcNow.ToString('o');timeoutSeconds=$MeasuredDrainTimeoutSeconds
        sampleCount=$statsSamples.Count;runtimeContainer=$names.runtimeContainer
      }
      Write-Json (Join-Path $evidenceDir 'measured-drain-timeout.json') $timeoutEvidence
      Invoke-Docker @('stop','--time','30',$names.runtimeContainer) -AllowFailure | Out-Null
      throw "Measured runtime drain exceeded $MeasuredDrainTimeoutSeconds seconds"
    }
    $running = Invoke-Docker @('inspect',$names.runtimeContainer,'--format','{{.State.Running}}') -AllowFailure
    if ($running.exitCode -ne 0 -or (($running.output -join '').Trim()) -ne 'true') { break }
    $sample = Invoke-Docker @('stats',$names.runtimeContainer,'--no-stream','--format','{{json .}}') -AllowFailure
    $statsSamples.Add([ordered]@{atUtc=[DateTime]::UtcNow.ToString('o');phase='measured-drain';exitCode=$sample.exitCode;sample=($sample.output -join '')})
    Start-Sleep -Seconds 5
  } while ($true)
  $wait = Invoke-Docker @('wait',$names.runtimeContainer)
  $exitCode = [int](($wait.output -join '').Trim())
  if ($exitCode -ne 0) { throw "Custom Java runtime exited with code $exitCode" }
  $runtimeLog = Join-Path $evidenceDir 'custom-java-runtime.log'
  $runtimeLogResult = Invoke-Docker @('logs',$names.runtimeContainer)
  [IO.File]::WriteAllLines($runtimeLog, @($runtimeLogResult.output), [Text.UTF8Encoding]::new($false))
  $finalOffsets = Get-OffsetSnapshot
  $lag = Get-ConsumerLagSnapshot
  $measuredDeltas = [ordered]@{
    input=([long]$finalOffsets.input.total - [long]$baselineOffsets.input.total)
    output=([long]$finalOffsets.output.total - [long]$baselineOffsets.output.total)
    dlq=([long]$finalOffsets.dlq.total - [long]$baselineOffsets.dlq.total)
  }
  if ($measuredDeltas.input -ne 500000 -or ($measuredDeltas.output + $measuredDeltas.dlq) -ne 500000) {
    throw 'Measured Kafka deltas must be exactly 500000 input and 500000 output+DLQ'
  }
  if (-not $lag.available -or $lag.total -ne 0) { throw 'Measured drain requires an available zero consumer-group lag snapshot' }
  $measuredWindow.drainEndUtc = [DateTime]::UtcNow.ToString('o')
  } finally {
    if ($brokerStarted) {
      & $brokerJfrCollector -Action DumpStop -CampaignId $CampaignId -RecordingOutput $brokerJfr `
        -EvidenceOutput $brokerJfrEvidence -Execute -ConfirmCampaign $CampaignId -Confirm:$false | Out-Null
    }
  }

  $runtimeOutputProvenancePath = Join-Path $evidenceDir 'runtime-output-provenance.json'
  $runtimeOutputProvenance = [ordered]@{
    schemaVersion=1;kind='custom-java-runtime-output-provenance';campaignId=$CampaignId;runtimeType='CUSTOM_JAVA_JSON'
    publisherDestinations=@($names.rawTopic);runtimeContainer=$names.runtimeContainer;runtimeImageId=$imageId
    runtimeDestinations=@($names.outputTopic,$names.dlqTopic);baselineOffsets=$baselineOffsets;finalOffsets=$finalOffsets
    measuredDeltas=$measuredDeltas;measuredOutputPlusDlq=($measuredDeltas.output+$measuredDeltas.dlq)
    manualDownstreamInsertionUsed=$false;runtimeOnlyOutputInsertion=$true
  }
  Write-Json $runtimeOutputProvenancePath $runtimeOutputProvenance
  $completed = [DateTime]::UtcNow
  $provenance = [ordered]@{
    schemaVersion=1;kind='custom-java-live-campaign-provenance';campaignId=$CampaignId;runtimeType='CUSTOM_JAVA_JSON'
    startedAtUtc=$started.ToString('o');completedAtUtc=$completed.ToString('o');durationSeconds=($completed-$started).TotalSeconds
    mappingSha256=Sha $mapping;corpusSha256=Sha $corpus;jarSha256=Sha $jar;dockerfileSha256=Sha $dockerfile;imageId=$imageId
    parity=$parity;warmupRecords=10000;measuredRecords=500000;runtimeExpectedTotal=510000;payloadVariants=100;payloadBytesEach=102400;producerRate=$ProducerRate
    measuredWindow=$measuredWindow;baselineOffsets=$baselineOffsets;finalOffsets=$finalOffsets;measuredDeltas=$measuredDeltas
    warmupPublisherManifest=[ordered]@{path=$warmupManifest;sha256=Sha $warmupManifest}
    publisherManifest=[ordered]@{path=$publisherManifest;sha256=Sha $publisherManifest}
    runtimeJfr=[ordered]@{path=$runtimeJfr;exists=(Test-Path -LiteralPath $runtimeJfr);sha256=if(Test-Path -LiteralPath $runtimeJfr){Sha $runtimeJfr}else{$null}}
    sourceProducerJfr=[ordered]@{path=$producerJfr;exists=(Test-Path -LiteralPath $producerJfr);sha256=if(Test-Path -LiteralPath $producerJfr){Sha $producerJfr}else{$null}}
    kafkaBrokerJfr=[ordered]@{path=$brokerJfr;sha256=Sha $brokerJfr;evidencePath=$brokerJfrEvidence;evidenceSha256=Sha $brokerJfrEvidence;measuredWindowOnly=$true}
    dockerStats=[ordered]@{sampleIntervalSeconds=5;samples=$statsSamples}
    consumerLag=$lag;runtimeExitCode=$exitCode
    runtimeLog=[ordered]@{path=$runtimeLog;sha256=Sha $runtimeLog}
    runtimeOutputProvenance=[ordered]@{path=$runtimeOutputProvenancePath;sha256=Sha $runtimeOutputProvenancePath}
    manualDownstreamInsertionUsed=$false;composeUsed=$false;cleanupPlan=@(Cleanup-Actions)
  }
  Write-Json $provenancePath $provenance
  Write-Json $manifestPath ([ordered]@{schemaVersion=1;kind='custom-java-campaign-manifest';campaignId=$CampaignId;state='DRAINED';names=$names;provenance=$provenancePath;cleanupRequired=$true})
  $provenance | ConvertTo-Json -Depth 30
} catch {
  Write-Json (Join-Path $campaignDir 'custom-java-run-error.json') ([ordered]@{schemaVersion=1;kind='custom-java-campaign-error';campaignId=$CampaignId;atUtc=[DateTime]::UtcNow.ToString('o');message=$_.Exception.Message;cleanupRequired=$true})
  throw
}
