[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
  [Parameter(Mandatory)][string]$CampaignId,
  [Parameter(Mandatory)][string]$RuntimeId,
  [Parameter(Mandatory)][string]$MappingId,
  [Parameter(Mandatory)][string]$ArtifactId,
  [Parameter(Mandatory)][string]$ArtifactHash,
  [Parameter(Mandatory)][string]$Target,
  [Parameter(Mandatory)][string]$AssignmentUrl,
  [string]$PayloadJsonl,
  [string]$ResultsRoot,
  [string]$RunDirectory,
  [string]$ParityEvidencePath,
  [string]$TransportEvidence = 'verified setup/control-plane runtime evidence; assignment endpoint omits transport',
  [ValidateRange(1,5000000)][int]$RecordCount = 500000,
  [ValidateRange(1,1000)][int]$BatchSize = 10,
  [ValidateRange(1,64)][int]$Streams = 4,
  [ValidateRange(1,4096)][int]$MaxInflightBatches = 128,
  [ValidateRange(0,1000000)][int]$TargetRps = 0,
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$benchmarkRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PayloadJsonl)) { $PayloadJsonl = Join-Path $benchmarkRoot 'workload\generated\valid-payloads-100kb.jsonl' }
if ([string]::IsNullOrWhiteSpace($ResultsRoot)) { $ResultsRoot = Join-Path $benchmarkRoot 'results' }
$payload = (Resolve-Path -LiteralPath $PayloadJsonl).Path
$runDir = if($RunDirectory){[IO.Path]::GetFullPath($RunDirectory)}else{[IO.Path]::GetFullPath((Join-Path $ResultsRoot "$CampaignId\observed-grpc-run"))}
$jfr = Join-Path $runDir 'grpc-client.jfr'
$jar = Join-Path $PSScriptRoot 'target\isolated-grpc-observation-client.jar'

$plan = [ordered]@{
  schema = 'flowplane.grpc-runtime-client-plan.v1'
  campaignId = $CampaignId
  runtimeId = $RuntimeId
  mappingId = $MappingId
  artifactId = $ArtifactId
  artifactHash = $ArtifactHash
  transport = 'GRPC_STREAM'
  transportEvidence = $TransportEvidence
  target = $Target
  assignmentUrl = $AssignmentUrl
  payloadJsonl = $payload
  recordCount = $RecordCount
  payloadVariants = 100
  payloadBytes = 102400
  batchSize = $BatchSize
  streams = $Streams
  maxInflightBatches = $MaxInflightBatches
  targetRps = $TargetRps
  outputHandling = 'runtime responses observed then discarded; bounded hash/size samples only; no downstream publisher'
  parityEvidencePath = if ([string]::IsNullOrWhiteSpace($ParityEvidencePath)) { $null } else { [IO.Path]::GetFullPath($ParityEvidencePath) }
  jfr = $jfr
  observationalOnly = $true
  executeRequested = [bool]$Execute
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
}

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$planPath = Join-Path $runDir 'grpc-client-plan.json'
if (Test-Path -LiteralPath $planPath) {
  throw "Refusing to overwrite existing gRPC campaign plan: $planPath"
}
$planJson = ($plan | ConvertTo-Json -Depth 8) + [Environment]::NewLine
$planStream = $null
$planWriter = $null
try {
  $planStream = [IO.File]::Open($planPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  $planWriter = [IO.StreamWriter]::new($planStream, [Text.UTF8Encoding]::new($false))
  $planWriter.Write($planJson)
} finally {
  if ($null -ne $planWriter) { $planWriter.Dispose() }
  elseif ($null -ne $planStream) { $planStream.Dispose() }
}
if (-not $Execute) {
  Write-Output ($plan | ConvertTo-Json -Depth 8)
  return
}
if ($MaxInflightBatches -lt $Streams) { throw 'MaxInflightBatches must be greater than or equal to Streams' }
if (-not $PSCmdlet.ShouldProcess("gRPC runtime $Target", "Send $RecordCount source records for campaign $CampaignId")) { return }
if (-not (Test-Path -LiteralPath $jar -PathType Leaf)) { & (Join-Path $PSScriptRoot 'build.ps1') | Out-Host }

$javaArgs = @(
  '-Xms512m','-Xmx2g','-XX:+UseG1GC','-jar',$jar,
  '--campaign-id',$CampaignId,'--expected-runtime-id',$RuntimeId,'--expected-mapping-id',$MappingId,
  '--expected-artifact-id',$ArtifactId,
  '--target',$Target,'--assignment-url',$AssignmentUrl,'--payload-jsonl',$payload,
  '--expected-artifact-hash',$ArtifactHash,'--expected-transport','GRPC_STREAM','--transport-evidence',$TransportEvidence,
  '--run-dir',$runDir,'--jfr-file',$jfr,'--record-count',[string]$RecordCount,
  '--payload-variants','100','--payload-bytes','102400','--batch-size',[string]$BatchSize,
  '--streams',[string]$Streams,'--max-inflight-batches',[string]$MaxInflightBatches,
  '--target-rps',[string]$TargetRps
)
if (-not [string]::IsNullOrWhiteSpace($ParityEvidencePath)) {
  if ($RecordCount -gt 1000) { throw 'Parity evidence capture is bounded to at most 1000 records' }
  $javaArgs += @('--parity-evidence-path', [IO.Path]::GetFullPath($ParityEvidencePath))
}
$previousErrorActionPreference = $ErrorActionPreference
try {
  # Windows PowerShell exposes native stderr as ErrorRecords. The gRPC/Netty
  # client writes normal INFO diagnostics there, so keep them visible while
  # using the native exit code—not the stream type—as the failure signal.
  $ErrorActionPreference = 'Continue'
  & java @javaArgs 2>&1 | Out-Host
  $javaExitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousErrorActionPreference
}
if ($javaExitCode -ne 0) { throw "gRPC observation client exited with code $javaExitCode" }

$observationPath = Join-Path $runDir 'grpc-client-observation.json'
$observation = Get-Content -LiteralPath $observationPath -Raw | ConvertFrom-Json
if ($observation.configuredRecords -ne $RecordCount) { throw 'Observation record count does not match the launch plan' }
$expectedBatches = [long][Math]::Ceiling($RecordCount / [double]$BatchSize)
if ($observation.responseDrainCompleted -ne $true -or $observation.outstandingBatches -ne 0) {
  throw 'Observation did not prove a complete response drain'
}
if ($observation.recordsSent -ne $RecordCount -or $observation.responseRecords -ne $RecordCount) {
  throw 'Observation did not account for every configured record'
}
if ($observation.batchesSent -ne $expectedBatches -or $observation.responseBatches -ne $expectedBatches) {
  throw 'Observation did not account for every configured batch'
}
if (($observation.okObserved + $observation.dlqObserved + $observation.failedObserved) -ne $RecordCount) {
  throw 'Observation status totals do not equal the configured record count'
}
if ($observation.rpcObservation -ne 'none reported') { throw 'Observation contains an RPC error' }
if ($observation.jfr.path -ne $jfr) { throw 'Observation JFR path does not match the launch plan' }
[pscustomobject]@{ Plan=$planPath; Observation=$observationPath; Jfr=$jfr; ObservationalOnly=$true }
