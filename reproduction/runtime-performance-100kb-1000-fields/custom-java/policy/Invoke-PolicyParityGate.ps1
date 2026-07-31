[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Prepare','Verify')][string]$Action,
  [Parameter(Mandatory)][string]$WorkDirectory,
  [string[]]$ArtifactClasspath,
  [string]$CompetitorJar,
  [string]$ActualResponses
)

$ErrorActionPreference = 'Stop'
$benchmarkRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixtures = Join-Path $benchmarkRoot 'workload\generated'
$mapping = Join-Path $benchmarkRoot 'mapping\mapping.dsl'
$payloads = Join-Path $fixtures 'invalid-policy-payloads.jsonl'
$manifest = Join-Path $fixtures 'policy-canary-manifest.json'
$work = [IO.Path]::GetFullPath($WorkDirectory)
$oracle = Join-Path $work 'governed-core-policy-oracle.jsonl'
$requests = Join-Path $work 'policy-requests.jsonl'
$expected = Join-Path $work 'policy-expected.jsonl'
$actual = if ($ActualResponses) { [IO.Path]::GetFullPath($ActualResponses) } else { Join-Path $work 'policy-actual.jsonl' }
$evidence = Join-Path $work 'policy-parity-evidence.json'

if ($Action -eq 'Prepare') {
  if (-not $ArtifactClasspath -or $ArtifactClasspath.Count -eq 0) {
    throw 'Prepare requires the explicit FlowPlane Core artifact classpath.'
  }
  New-Item -ItemType Directory -Path $work -Force | Out-Null
  foreach ($path in @($oracle,$requests,$expected)) {
    if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite parity evidence: $path" }
  }
  $classes = Join-Path $work 'oracle-classes'
  New-Item -ItemType Directory -Path $classes -Force | Out-Null
  & javac --release 17 -encoding UTF-8 -d $classes (Join-Path $PSScriptRoot 'src\PolicyOracleCli.java')
  if ($LASTEXITCODE -ne 0) { throw "Policy oracle javac failed with exit code $LASTEXITCODE" }
  $resolvedArtifacts = @($ArtifactClasspath | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
  $classpath = (@($classes) + $resolvedArtifacts) -join [IO.Path]::PathSeparator
  $oracleInputs = Join-Path $work 'policy-oracle-inputs.jsonl'
  $invalidBytes = [IO.File]::ReadAllBytes($payloads)
  $malformed = [Text.Encoding]::UTF8.GetBytes((Get-Content -LiteralPath $payloads -TotalCount 1))
  $malformed[0] = [byte][char]'!'
  $inputStream = [IO.File]::Create($oracleInputs)
  try {
    $inputStream.Write($invalidBytes, 0, $invalidBytes.Length)
    $inputStream.Write($malformed, 0, $malformed.Length)
    $inputStream.WriteByte(10)
  } finally {
    $inputStream.Dispose()
  }
  & java -cp $classpath PolicyOracleCli --mapping $mapping --payload-jsonl $oracleInputs --output $oracle
  if ($LASTEXITCODE -ne 0) { throw "Policy oracle failed with exit code $LASTEXITCODE" }
  & python (Join-Path $PSScriptRoot 'policy_gate.py') prepare `
    --mapping $mapping --payloads $payloads --manifest $manifest --oracle $oracle `
    --requests $requests --expected $expected
  if ($LASTEXITCODE -ne 0) { throw "Policy corpus preparation failed with exit code $LASTEXITCODE" }
  $artifactEvidence = @($resolvedArtifacts | ForEach-Object {
    [ordered]@{
      path = $_
      sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
    }
  })
  $preparation = [ordered]@{
    schemaVersion = 1
    kind = 'custom-java-policy-oracle-provenance'
    mappingSha256 = (Get-FileHash -LiteralPath $mapping -Algorithm SHA256).Hash.ToLowerInvariant()
    payloadCorpusSha256 = (Get-FileHash -LiteralPath $payloads -Algorithm SHA256).Hash.ToLowerInvariant()
    oracleInputSha256 = (Get-FileHash -LiteralPath $oracleInputs -Algorithm SHA256).Hash.ToLowerInvariant()
    oracleSha256 = (Get-FileHash -LiteralPath $oracle -Algorithm SHA256).Hash.ToLowerInvariant()
    requestsSha256 = (Get-FileHash -LiteralPath $requests -Algorithm SHA256).Hash.ToLowerInvariant()
    expectedSha256 = (Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash.ToLowerInvariant()
    oracleSourceSha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'src\PolicyOracleCli.java') -Algorithm SHA256).Hash.ToLowerInvariant()
    artifactClasspath = $artifactEvidence
    liveTrafficUsed = $false
    manualDownstreamInsertionUsed = $false
  }
  [IO.File]::WriteAllText(
    (Join-Path $work 'policy-oracle-provenance.json'),
    ($preparation | ConvertTo-Json -Depth 8) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
  )
  return
}

if ($CompetitorJar) {
  if (Test-Path -LiteralPath $actual) { throw "Refusing to overwrite competitor responses: $actual" }
  & java -jar (Resolve-Path -LiteralPath $CompetitorJar).Path parity `
    --requests $requests --responses $actual --mapping $mapping
  if ($LASTEXITCODE -ne 0) { throw "Custom Java parity command failed with exit code $LASTEXITCODE" }
}
if (-not (Test-Path -LiteralPath $actual -PathType Leaf)) {
  throw "Actual response JSONL is missing: $actual"
}
$verifyArguments = @(
  (Join-Path $PSScriptRoot 'policy_gate.py'), 'verify',
  '--expected', $expected, '--actual', $actual, '--evidence', $evidence
)
if ($CompetitorJar) {
  $verifyArguments += @('--competitor-artifact', (Resolve-Path -LiteralPath $CompetitorJar).Path)
}
& python @verifyArguments
if ($LASTEXITCODE -ne 0) { throw "Custom Java policy parity is not proven. See $evidence" }
