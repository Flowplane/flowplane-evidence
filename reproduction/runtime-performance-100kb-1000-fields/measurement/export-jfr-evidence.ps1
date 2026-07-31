[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$CampaignId,
  [Parameter(Mandatory)][ValidateSet('HTTP','GRPC','COMPETITOR','KAFKA_BROKER','SOURCE_PRODUCER')][string]$RuntimeType,
  [Parameter(Mandatory)][string]$ArtifactHash,
  [Parameter(Mandatory)][string]$Recording,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [string]$WindowStart,
  [string]$WindowEnd,
  [ValidateRange(0,10000000)][long]$MeasuredOperations = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$recordingPath = (Resolve-Path -LiteralPath $Recording).Path
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$summaryPath = Join-Path $outputRoot 'jfr-summary.txt'
$allocationPath = Join-Path $outputRoot 'jfr-allocation-summary.json'
$manifestPath = Join-Path $outputRoot 'jfr-evidence-manifest.json'

$summary = (& jfr summary $recordingPath 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "jfr summary failed with exit code $LASTEXITCODE" }
[IO.File]::WriteAllText($summaryPath, $summary, [Text.UTF8Encoding]::new($false))

& (Join-Path $PSScriptRoot 'build.ps1') | Out-Host
$jar = Join-Path $PSScriptRoot 'build\flowplane-benchmark-measurement.jar'
$arguments = @(
  '--campaign-id',$CampaignId,'--runtime-type',$RuntimeType,'--artifact-hash',$ArtifactHash,
  '--recording',$recordingPath,'--output',$allocationPath
)
if ($WindowStart -or $WindowEnd) {
  if (-not $WindowStart -or -not $WindowEnd) { throw 'WindowStart and WindowEnd must be supplied together' }
  $arguments += @('--window-start',$WindowStart,'--window-end',$WindowEnd)
}
if ($MeasuredOperations -gt 0) { $arguments += @('--measured-operations',[string]$MeasuredOperations) }

& java -cp $jar com.flowplane.benchmark.measurement.JfrAllocationSummaryCli @arguments
if ($LASTEXITCODE -ne 0) { throw "JFR allocation summary failed with exit code $LASTEXITCODE" }
$allocation = Get-Content -LiteralPath $allocationPath -Raw | ConvertFrom-Json

$manifest = [ordered]@{
  schemaVersion = 1
  kind = 'flowplane-benchmark-jfr-evidence'
  campaignId = $CampaignId
  runtimeType = $RuntimeType
  artifactHash = $ArtifactHash
  recording = $recordingPath
  summary = $summaryPath
  allocationSummary = $allocationPath
  windowStart = if ($WindowStart) { $WindowStart } else { $null }
  windowEnd = if ($WindowEnd) { $WindowEnd } else { $null }
  measuredOperations = if ($MeasuredOperations -gt 0) { $MeasuredOperations } else { $null }
  allocation = $allocation
  bytesPerOperationSemantics = if ($MeasuredOperations -gt 0) { 'JFR ObjectAllocationSample weighted-byte estimate divided by exact measured operations' } else { $null }
  observationalOnly = $true
  capturedAt = [DateTimeOffset]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText(
  $manifestPath,
  ($manifest | ConvertTo-Json -Depth 12) + "`n",
  [Text.UTF8Encoding]::new($false)
)
[pscustomobject]@{Manifest=$manifestPath;Summary=$summaryPath;AllocationSummary=$allocationPath}
