[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$module = $PSScriptRoot
Push-Location $module
try {
  & mvn --no-transfer-progress package
  if ($LASTEXITCODE -ne 0) { throw "gRPC observation client build failed with exit code $LASTEXITCODE" }
  $jar = Join-Path $module 'target\isolated-grpc-observation-client.jar'
  if (-not (Test-Path -LiteralPath $jar -PathType Leaf)) { throw "Expected shaded client jar was not created: $jar" }
  Get-Item -LiteralPath $jar
} finally {
  Pop-Location
}
