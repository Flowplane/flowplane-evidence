[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
  & (Join-Path $PSScriptRoot 'Test-GrpcObservedClient.ps1')
  & mvn --no-transfer-progress test
  if ($LASTEXITCODE -ne 0) { throw "gRPC observation client tests failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
