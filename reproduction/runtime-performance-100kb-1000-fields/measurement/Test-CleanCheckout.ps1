[CmdletBinding()]
param([switch]$KeepCheckout)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scratchRoot = Join-Path ([IO.Path]::GetTempPath()) ('flowplane-measurement-smoke-' + [Guid]::NewGuid().ToString('N'))
$checkout = Join-Path $scratchRoot 'measurement'
$files = @(
  '.gitignore','README.md','build.ps1','export-jfr-evidence.ps1','test.ps1',
  'src\main\java\com\flowplane\benchmark\measurement\Json.java',
  'src\main\java\com\flowplane\benchmark\measurement\JfrAllocationSummaryCli.java',
  'src\main\java\com\flowplane\benchmark\measurement\JfrAllocationWorkload.java'
)
try {
  foreach ($relative in $files) {
    $source = Join-Path $PSScriptRoot $relative
    $destination = Join-Path $checkout $relative
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath $source -Destination $destination
  }
  & (Join-Path $checkout 'test.ps1') | Out-Host
  [pscustomobject]@{status='PASS';isolatedCheckout=$checkout;sourceFileCount=3} | ConvertTo-Json -Compress
} finally {
  if (-not $KeepCheckout -and (Test-Path -LiteralPath $scratchRoot)) {
    $resolvedScratch = [IO.Path]::GetFullPath($scratchRoot)
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolvedScratch.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path -Leaf $resolvedScratch).StartsWith('flowplane-measurement-smoke-')) {
      throw "Refusing to remove unexpected smoke directory: $resolvedScratch"
    }
    Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
  }
}
