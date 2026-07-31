[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'build.ps1') | Out-Host
$buildRoot = Join-Path $PSScriptRoot 'build'
$classes = Join-Path $buildRoot 'classes'
$jfrPath = Join-Path $buildRoot 'smoke-allocation.jfr'
$evidenceRoot = Join-Path $buildRoot 'smoke-evidence'
foreach ($target in @($jfrPath, $evidenceRoot)) {
  if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}

$jfrArgument = "-XX:StartFlightRecording=settings=profile,disk=true,dumponexit=true,filename=$jfrPath"
& java $jfrArgument -cp $classes com.flowplane.benchmark.measurement.JfrAllocationWorkload
if ($LASTEXITCODE -ne 0) { throw "JFR fixture process failed with exit code $LASTEXITCODE" }

& (Join-Path $PSScriptRoot 'export-jfr-evidence.ps1') `
  -CampaignId measurement-smoke -RuntimeType GRPC -ArtifactHash 'sha256:smoke' `
  -Recording $jfrPath -OutputDirectory $evidenceRoot -MeasuredOperations 50000 | Out-Host

$allocation = Get-Content -LiteralPath (Join-Path $evidenceRoot 'jfr-allocation-summary.json') -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath (Join-Path $evidenceRoot 'jfr-evidence-manifest.json') -Raw | ConvertFrom-Json
if ($allocation.state -ne 'available' -or $allocation.sampledEventCount -le 0 -or
    $allocation.estimatedAllocatedBytes -le 0 -or $allocation.estimatedBytesPerOperation -le 0) {
  throw "JFR allocation evidence was unavailable or empty: $($allocation.reason)"
}
if ($manifest.kind -ne 'flowplane-benchmark-jfr-evidence' -or
    $manifest.measuredOperations -ne 50000 -or $manifest.observationalOnly -ne $true) {
  throw 'JFR evidence manifest failed its smoke contract'
}
if (-not (Test-Path -LiteralPath (Join-Path $evidenceRoot 'jfr-summary.txt') -PathType Leaf)) {
  throw 'jfr summary output is missing'
}

[pscustomobject]@{
  status='PASS'
  sampledEventCount=$allocation.sampledEventCount
  estimatedAllocatedBytes=$allocation.estimatedAllocatedBytes
  estimatedBytesPerOperation=$allocation.estimatedBytesPerOperation
} | ConvertTo-Json -Compress
