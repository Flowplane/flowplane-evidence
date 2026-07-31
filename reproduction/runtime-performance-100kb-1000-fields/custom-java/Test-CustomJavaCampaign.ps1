[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$moduleRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$benchmarkRoot = [IO.Path]::GetFullPath((Join-Path $moduleRoot '..'))
$corpus = Join-Path $benchmarkRoot 'workload\generated\valid-payloads-100kb.jsonl'
if (-not (Test-Path -LiteralPath $corpus -PathType Leaf)) {
  & python (Join-Path $benchmarkRoot 'workload\workload.py') generate --output-dir (Join-Path $benchmarkRoot 'workload\generated') | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Workload generation failed with exit code $LASTEXITCODE" }
}
$controller = Join-Path $moduleRoot 'Invoke-CustomJavaCampaign.ps1'
$target = Join-Path $moduleRoot 'target\campaign-contract-tests'
New-Item -ItemType Directory -Path $target -Force | Out-Null
$campaignId = 'custom-java-contract-001'
$lock = Join-Path ([IO.Path]::GetFullPath((Join-Path $moduleRoot '..\..'))) 'results\active-campaign.lock.json'
$lockHashBefore = if (Test-Path -LiteralPath $lock) { (Get-FileHash -LiteralPath $lock -Algorithm SHA256).Hash } else { $null }

$planPath = Join-Path $target 'dry-run-plan.json'
if (Test-Path -LiteralPath $planPath) { [IO.File]::Delete($planPath) }
$planText = & $controller -Action Plan -CampaignId $campaignId -PlanOutputPath $planPath
$plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
if ($plan.kind -ne 'custom-java-live-campaign-plan' -or $plan.dryRun -ne $true -or
    $plan.mutationsPerformed -ne $false -or $plan.corpus.warmupRecords -ne 10000 -or
    $plan.corpus.measuredRecords -ne 500000 -or $plan.corpus.runtimeExpectedTotal -ne 510000 -or
    $plan.corpus.variants -ne 100 -or $plan.corpus.payloadBytesEach -ne 102400 -or
    $plan.mappingSha256 -ne '007b1546713568882b12a884cdcc85031746e32855770ef0306ae3bebfd7fc31' -or
    $plan.manualDownstreamInsertionUsed -ne $false -or $plan.docker.composeUsed -ne $false) {
  throw 'Dry-run plan contract is incomplete'
}
if ($plan.timeouts.warmupPublisherSeconds -ne 1800 -or
    $plan.timeouts.measuredPublisherSeconds -ne 7200 -or
    $plan.timeouts.measuredDrainSeconds -ne 7200) {
  throw 'Publisher and drain deadlines are absent from the campaign plan'
}
if ($plan.methodology.warmup.records -ne 10000 -or $plan.methodology.warmup.drainBeforeBaseline -ne $true -or
    $plan.methodology.corpusAndKeys.kafkaKey -ne 'ASCII decimal publisher sequence' -or
    $plan.methodology.corpusAndKeys.warmupKeyRange -ne '0..9999' -or
    $plan.methodology.corpusAndKeys.measuredKeyRange -ne '0..499999' -or
    $plan.methodology.measured.deltaInputRequired -ne 500000 -or
    $plan.methodology.measured.deltaOutputPlusDlqRequired -ne 500000 -or
    $plan.methodology.measured.zeroLagRequired -ne $true -or
    [string]::IsNullOrWhiteSpace([string]$plan.methodology.measuredWindow.startUtc) -or
    [string]::IsNullOrWhiteSpace([string]$plan.methodology.measuredWindow.publishEndUtc) -or
    [string]::IsNullOrWhiteSpace([string]$plan.methodology.measuredWindow.drainEndUtc) -or
    $plan.docker.jfr.sourceProducer.measuredPublisherOnly -ne $true -or
    $plan.docker.jfr.kafkaBroker.measuredWindowOnly -ne $true -or
    $plan.docker.jfr.runtime.filterToMeasuredWindowLater -ne $true -or
    $plan.methodology.outputProvenance -notmatch 'runtime writes output/DLQ') {
  throw 'Warmup, measured-window, JFR, delta, lag, or runtime-output methodology is absent'
}
$controllerSource = Get-Content -LiteralPath $controller -Raw
foreach ($requiredFragment in @(
  "--expected-records','510000", "--mode','warmup", 'Wait-WarmupDrain',
  '-Action Start -CampaignId', '-Action DumpStop -CampaignId',
  '$measuredWindow.startUtc', '$measuredWindow.publishEndUtc', '$measuredWindow.drainEndUtc',
  '$measuredDeltas.input -ne 500000', '$measuredDeltas.output + $measuredDeltas.dlq',
  '$lag.total -ne 0', 'custom-java-runtime-output-provenance',
  '$publisherProcess.WaitForExit(); $publisherProcess.Refresh()',
  '$measuredPublisherEvidence = Read-RequiredJson $publisherManifest',
  "status -ne 'COMPLETE'", 'producerFlushConfirmedByExit',
  '[IO.FileMode]::CreateNew', 'measured-publisher-timeout.json', 'warmup-publisher-timeout.json'
)) {
  if (-not $controllerSource.Contains($requiredFragment)) { throw "Live methodology implementation fragment is missing: $requiredFragment" }
}
if ($null -ne $plan.blockedByActiveCampaign -and $plan.executable -ne $false) {
  throw 'Dry-run plan did not expose the active-campaign overlap block'
}
if ($null -eq $plan.blockedByActiveCampaign -and $plan.parity.state -eq 'NOT_PREPARED' -and $plan.executable -ne $false) {
  throw 'Dry-run plan must not be executable before parity prerequisites are prepared'
}

$cleanupText = & $controller -Action CleanupPlan -CampaignId $campaignId
$cleanup = ($cleanupText -join "`n") | ConvertFrom-Json
if ($cleanup.actions.Count -ne 7 -or $cleanup.actions[-1].kind -ne 'reports' -or
    $cleanup.actions[-1].action -ne 'preserve all reports and JFR evidence') {
  throw 'Cleanup plan is not exact or does not preserve reports'
}
if ($cleanup.actions[0].action -notmatch 'docker stop --time 30' -or
    $cleanup.actions[0].action -match 'rm --force') {
  throw 'Cleanup plan does not prefer graceful stop and non-force removal'
}

$generatedValid = Join-Path $moduleRoot 'policy\generated\valid-parity-evidence.json'
$generatedPolicy = Join-Path $moduleRoot 'policy\generated\policy-parity-evidence.json'
$failedClosed = $null
$stalePolicyRefused = $null
if ((Test-Path -LiteralPath $generatedValid) -and (Test-Path -LiteralPath $generatedPolicy)) {
  $badEvidence = Join-Path $target 'not-proven-valid-parity.json'
  $valid = Get-Content -LiteralPath $generatedValid -Raw | ConvertFrom-Json
  $valid.parityState = 'NOT_PROVEN'
  [IO.File]::WriteAllText($badEvidence, ($valid | ConvertTo-Json -Depth 10) + "`n", [Text.UTF8Encoding]::new($false))
  $failedClosed = $false
  try { & $controller -Action Plan -CampaignId $campaignId -ValidEvidencePathOverride $badEvidence | Out-Null } catch { $failedClosed = $_.Exception.Message -match 'not PROVEN' }
  if (-not $failedClosed) { throw 'Controller did not fail closed on NOT_PROVEN valid parity' }

  $badPolicy = Join-Path $target 'stale-five-canary-policy.json'
  $policy = Get-Content -LiteralPath $generatedPolicy -Raw | ConvertFrom-Json
  $policy.expectedRecordCount = 5
  $policy.actualRecordCount = 5
  [IO.File]::WriteAllText($badPolicy, ($policy | ConvertTo-Json -Depth 10) + "`n", [Text.UTF8Encoding]::new($false))
  $stalePolicyRefused = $false
  try { & $controller -Action Plan -CampaignId $campaignId -PolicyEvidencePathOverride $badPolicy | Out-Null } catch { $stalePolicyRefused = $_.Exception.Message -match 'not PROVEN' }
  if (-not $stalePolicyRefused) { throw 'Controller accepted stale 5-canary policy evidence' }
}

if (Test-Path -LiteralPath $lock) {
  $overlapRefused = $false
  try {
    & $controller -Action Run -CampaignId $campaignId -Execute -ConfirmCampaignId $campaignId -Confirm:$false | Out-Null
  } catch {
    $overlapRefused = $_.Exception.Message -match 'Cannot overlap active campaign'
  }
  if (-not $overlapRefused) { throw 'Controller did not refuse live overlap with the active campaign lock' }
}

$recoveryValidated = $null
$activeLockValue = if (Test-Path -LiteralPath $lock) { Get-Content -LiteralPath $lock -Raw | ConvertFrom-Json } else { $null }
if ($null -ne $activeLockValue -and $activeLockValue.campaignId -eq 'custom-java-20260731-0937') {
  $recoveryDir = Join-Path ([IO.Path]::GetFullPath((Join-Path $moduleRoot '..\..'))) 'results\custom-java-20260731-0937'
  $recoveryTargets = @(
    (Join-Path $recoveryDir 'custom-java-provenance.json'),
    (Join-Path $recoveryDir 'custom-java-campaign-manifest.json'),
    (Join-Path $recoveryDir 'custom-java-runtime\runtime-output-provenance.json'),
    (Join-Path $recoveryDir 'custom-java-runtime\custom-java-runtime.log')
  )
  $before = @($recoveryTargets | Where-Object { Test-Path -LiteralPath $_ })
  if ($before.Count -ne 0 -and $before.Count -ne $recoveryTargets.Count) {
    throw 'Recovery contract test found a partial recovery report set'
  }
  $beforeHashes = @{}
  foreach ($path in $before) { $beforeHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
  $recoveryText = & $controller -Action Recover -CampaignId 'custom-java-20260731-0937'
  $recoveryPlan = ($recoveryText -join "`n") | ConvertFrom-Json
  $v = $recoveryPlan.validation
  if ($recoveryPlan.dryRun -ne $true -or $recoveryPlan.republish -ne $false -or
      $v.recoverable -ne $true -or $v.warmup.records -ne 10000 -or $v.measured.records -ne 500000 -or
      $v.finalOffsets.input.total -ne 510000 -or $v.finalOffsets.output.total -ne 510000 -or $v.finalOffsets.dlq.total -ne 0 -or
      $v.consumerLag.total -ne 0 -or $v.consumerLag.committedOffsetTotal -ne 510000 -or
      $v.measuredDeltas.input -ne 500000 -or $v.measuredDeltas.output -ne 500000 -or $v.measuredDeltas.dlq -ne 0 -or
      [string]::IsNullOrWhiteSpace([string]$v.measuredWindow.startUtc) -or
      [string]::IsNullOrWhiteSpace([string]$v.measuredWindow.publishEndUtc) -or
      [string]::IsNullOrWhiteSpace([string]$v.measuredWindow.drainEndUtc) -or
      $v.dockerStats.state -ne 'unavailable' -or $v.dockerStats.invented -ne $false -or
      $v.runtime.exitCode -ne 0 -or $v.activePublisherCount -ne 0) {
    throw 'Recovery dry-run validation is incomplete'
  }
  $after = @($recoveryTargets | Where-Object { Test-Path -LiteralPath $_ })
  if ($after.Count -ne $before.Count) { throw 'Recovery dry-run wrote reports or mutated recovery state' }
  foreach ($path in $before) {
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $beforeHashes[$path]) {
      throw "Recovery dry-run changed existing report: $path"
    }
  }
  if ($before.Count -eq $recoveryTargets.Count) {
    $recoveredManifest = Get-Content -LiteralPath (Join-Path $recoveryDir 'custom-java-campaign-manifest.json') -Raw | ConvertFrom-Json
    if ($recoveredManifest.state -ne 'DRAINED') { throw 'Recovered campaign manifest is not DRAINED' }
  }
  $recoveryValidated = $true
}

$lockHashAfter = if (Test-Path -LiteralPath $lock) { (Get-FileHash -LiteralPath $lock -Algorithm SHA256).Hash } else { $null }
if ($lockHashBefore -ne $lockHashAfter) { throw 'Offline contract tests changed the active campaign lock' }

[ordered]@{
  schemaVersion=1
  kind='custom-java-campaign-contract-tests'
  dryRunPlanValidated=$true
  warmup10000BeforeMeasuredValidated=$true
  explicitMeasuredWindowValidated=$true
  measuredOnlyBrokerAndProducerJfrValidated=$true
  runtimeJfrFilterBoundaryValidated=$true
  exactMeasuredDeltasAndZeroLagValidated=$true
  runtimeOnlyOutputProvenanceValidated=$true
  parityFailClosedValidated=$failedClosed
  finalSixCanaryPolicyRequired=$stalePolicyRefused
  planExecutableWithoutActiveLock=if(Test-Path -LiteralPath $lock){$null}else{$plan.executable}
  activeCampaignOverlapRefused=if(Test-Path -LiteralPath $lock){$true}else{$null}
  completedRunRecoveryValidated=$recoveryValidated
  recoveryNoRepublishValidated=$recoveryValidated
  publisherExitRaceFixValidated=$true
  cleanupExactAndReportsPreserved=$true
  gracefulCleanupPreferred=$true
  activeLockUnchanged=$true
  containersStarted=0
  topicsCreated=0
  liveTrafficUsed=$false
} | ConvertTo-Json -Depth 5
