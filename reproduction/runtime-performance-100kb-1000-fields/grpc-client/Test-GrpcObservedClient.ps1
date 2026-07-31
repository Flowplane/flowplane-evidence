[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$benchmarkRoot = Split-Path -Parent $PSScriptRoot
$workloadScript = Join-Path $benchmarkRoot 'workload\workload.py'
$fixture = Join-Path $benchmarkRoot 'workload\generated\valid-payloads-100kb.jsonl'
$launcher = Join-Path $PSScriptRoot 'Invoke-GrpcObservedClient.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("flowplane-grpc-launcher-test-" + [Guid]::NewGuid().ToString('N'))
$campaignId = 'grpc-launcher-dry-run-test'

try {
  & python $workloadScript generate | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Workload generation failed with exit code $LASTEXITCODE" }
  if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) { throw "Generated default fixture is missing: $fixture" }

  $first = & $launcher `
    -CampaignId $campaignId `
    -RuntimeId 'runtime-test' `
    -MappingId 'mapping-test' `
    -ArtifactId 'artifact-test' `
    -ArtifactHash 'sha256:test' `
    -Target '127.0.0.1:19090' `
    -AssignmentUrl 'http://127.0.0.1:18090/v1/runtime/assignments' `
    -ResultsRoot $testRoot
  $plan = ($first -join [Environment]::NewLine) | ConvertFrom-Json
  $expectedFixture = [IO.Path]::GetFullPath($fixture)
  if ($plan.payloadJsonl -ne $expectedFixture) { throw 'Dry-run plan did not use the generated default workload fixture' }
  if ($plan.executeRequested -ne $false) { throw 'Dry-run plan unexpectedly requested execution' }

  $planPath = Join-Path $testRoot "$campaignId\observed-grpc-run\grpc-client-plan.json"
  $originalHash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash
  $refused = $false
  try {
    & $launcher `
      -CampaignId $campaignId `
      -RuntimeId 'changed-runtime' `
      -MappingId 'mapping-test' `
      -ArtifactId 'artifact-test' `
      -ArtifactHash 'sha256:test' `
      -Target '127.0.0.1:19090' `
      -AssignmentUrl 'http://127.0.0.1:18090/v1/runtime/assignments' `
      -ResultsRoot $testRoot | Out-Null
  } catch {
    $refused = $_.Exception.Message -match 'Refusing to overwrite existing gRPC campaign plan'
  }
  if (-not $refused) { throw 'Second launcher invocation did not refuse to overwrite the existing plan' }
  if ((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash -ne $originalHash) {
    throw 'Second launcher invocation changed the immutable campaign plan'
  }

  [pscustomobject]@{
    status = 'PASS'
    defaultFixture = $expectedFixture
    dryRunPlan = $planPath
    secondRunRefused = $true
    originalPlanPreserved = $true
  }
} finally {
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
