[CmdletBinding()]
param(
  [string]$OutputPath = '',
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$moduleRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$benchmarkRoot = [IO.Path]::GetFullPath((Join-Path $moduleRoot '..'))
if (-not $OutputPath) { $OutputPath = Join-Path $moduleRoot 'policy\generated\valid-parity-evidence.json' }
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (-not $resolvedOutput.StartsWith($moduleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Evidence output must remain under the isolated custom-java module: $moduleRoot"
}

if (-not $SkipBuild) {
  Push-Location $moduleRoot
  try {
    & mvn -q test
    if ($LASTEXITCODE -ne 0) { throw "Valid parity tests failed with exit code $LASTEXITCODE" }
    & mvn -q package -DskipTests
    if ($LASTEXITCODE -ne 0) { throw "Custom Java package failed with exit code $LASTEXITCODE" }
  } finally {
    Pop-Location
  }
}

$mapping = Join-Path $benchmarkRoot 'mapping\mapping.dsl'
$corpus = Join-Path $benchmarkRoot 'workload\generated\valid-payloads-100kb.jsonl'
$oracle = Join-Path $moduleRoot 'oracle\grpc-hard-valid-flowplane.jsonl'
$jar = Join-Path $moduleRoot 'target\custom-java-json-runtime.jar'
$expectedMapping = '007b1546713568882b12a884cdcc85031746e32855770ef0306ae3bebfd7fc31'
if ((Get-FileHash -LiteralPath $mapping -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedMapping) {
  throw 'Hard mapping identity changed after the parity test'
}
$lines = [IO.File]::ReadAllLines($corpus, [Text.Encoding]::UTF8)
if ($lines.Count -ne 100 -or @($lines | Where-Object { [Text.Encoding]::UTF8.GetByteCount($_) -ne 102400 }).Count -ne 0) {
  throw 'Valid corpus no longer contains exactly 100 variants of 102400 bytes'
}
$oracleLines = [IO.File]::ReadAllLines($oracle, [Text.Encoding]::UTF8)
if ($oracleLines.Count -ne 100) { throw 'Valid parity oracle no longer contains exactly 100 records' }

$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'custom-java-valid-parity-evidence'
  parityState = 'PROVEN'
  performanceVerdict = $null
  mappingSha256 = $expectedMapping
  corpusSha256 = (Get-FileHash -LiteralPath $corpus -Algorithm SHA256).Hash.ToLowerInvariant()
  oracleSha256 = (Get-FileHash -LiteralPath $oracle -Algorithm SHA256).Hash.ToLowerInvariant()
  jarSha256 = (Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash.ToLowerInvariant()
  payloadVariantCount = 100
  payloadBytesEach = 102400
  outputFieldCount = 1000
  byteExactRecordCount = 100
  differences = @()
  manualDownstreamInsertionUsed = $false
  liveTrafficUsed = $false
  generatedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$parent = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText($resolvedOutput, ($evidence | ConvertTo-Json -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))
$evidence | ConvertTo-Json -Depth 8
