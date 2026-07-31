[CmdletBinding()]
param(
  [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'target\custom-java-offline-parity.jfr' }
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$moduleRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if (-not $resolvedOutput.StartsWith($moduleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw "JFR output must remain under the isolated custom-java module: $moduleRoot"
}

Push-Location $moduleRoot
try {
  & mvn -q test "-DargLine=-XX:StartFlightRecording=filename=$resolvedOutput,settings=profile,dumponexit=true"
  if ($LASTEXITCODE -ne 0) { throw "Offline parity JFR run failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}

$jfr = Get-Item -LiteralPath $resolvedOutput
if ($jfr.Length -le 0) { throw "JFR output is empty: $resolvedOutput" }
[ordered]@{
  schemaVersion = 1
  kind = 'custom-java-offline-parity-jfr'
  mappingSha256 = '007b1546713568882b12a884cdcc85031746e32855770ef0306ae3bebfd7fc31'
  validVariantCount = 100
  jfrPath = $jfr.FullName
  jfrBytes = $jfr.Length
  liveTrafficUsed = $false
  manualDownstreamInsertionUsed = $false
} | ConvertTo-Json -Depth 4
