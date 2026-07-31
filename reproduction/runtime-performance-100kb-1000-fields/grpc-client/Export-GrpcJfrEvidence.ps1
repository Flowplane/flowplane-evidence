[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$CampaignId,
  [Parameter(Mandatory)][string]$ArtifactHash,
  [Parameter(Mandatory)][string]$RunDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$run = (Resolve-Path -LiteralPath $RunDirectory).Path
$observationPath = Join-Path $run 'grpc-client-observation.json'
$jfr = Join-Path $run 'grpc-client.jfr'
$observation = Get-Content -LiteralPath $observationPath -Raw | ConvertFrom-Json
if ($observation.schemaVersion -ne 1 -or $observation.kind -ne 'flowplane-benchmark-grpc-observation' -or
    $observation.campaignId -ne $CampaignId -or $observation.runtimeType -ne 'GRPC' -or
    $observation.artifactHash -ne $ArtifactHash) {
  throw 'gRPC observation identity does not match the requested JFR evidence identity'
}
& (Join-Path (Split-Path -Parent $PSScriptRoot) 'measurement\export-jfr-evidence.ps1') `
  -CampaignId $CampaignId -RuntimeType GRPC -ArtifactHash $ArtifactHash `
  -Recording $jfr -OutputDirectory (Join-Path $run 'jfr-evidence') `
  -WindowStart $observation.startedAt -WindowEnd $observation.completedAt `
  -MeasuredOperations ([long]$observation.responseRecords)
