Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BenchmarkRoot {
  return (Split-Path -Parent $PSScriptRoot)
}

function Read-CampaignConfig {
  param([string]$Path = (Join-Path (Get-BenchmarkRoot) 'runtime-config\campaign.defaults.json'))
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Campaign config not found: $Path" }
  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Assert-BenchmarkCampaignId {
  param([Parameter(Mandatory)][string]$CampaignId)
  if ($CampaignId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or $CampaignId -in @('.', '..')) {
    throw 'CampaignId must be 1-64 characters and contain only letters, numbers, dot, underscore, or hyphen; path segments are forbidden'
  }
  return $CampaignId
}

function Test-BenchmarkPreflightReady {
  param([object[]]$MissingRequiredContainers, [object[]]$Endpoints)
  return @($MissingRequiredContainers).Count -eq 0 -and
    @($Endpoints).Count -gt 0 -and
    @($Endpoints | Where-Object { -not $_.available }).Count -eq 0
}

function Test-BenchmarkStateGateEvidence {
  param([Parameter(Mandatory)]$Evidence, [Parameter(Mandatory)]$Manifest, [Parameter(Mandatory)][string]$TargetState)
  return $Evidence.schemaVersion -eq 1 -and
    $Evidence.kind -eq 'flowplane-benchmark-state-gate' -and
    $Evidence.campaignId -eq $Manifest.campaignId -and
    $Evidence.runtime -eq $Manifest.runtime -and
    $Evidence.targetState -eq $TargetState -and
    $Evidence.validated -eq $true
}

function Get-Sha256Text {
  param([AllowEmptyString()][string]$Text)
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Invoke-GitText {
  param([string]$Repository, [string[]]$Arguments)
  $priorPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & git -c core.safecrlf=false -C $Repository @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally { $ErrorActionPreference = $priorPreference }
  if ($exitCode -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
  return (($output | ForEach-Object { [string]$_ }) -join "`n")
}

function New-RepositorySnapshot {
  param([Parameter(Mandatory)][string]$Repository)
  $resolved = (Resolve-Path -LiteralPath $Repository).Path
  $commit = (Invoke-GitText $resolved @('rev-parse', 'HEAD')).Trim()
  $status = Invoke-GitText $resolved @('status', '--porcelain=v1', '--untracked-files=all')
  $trackedDiff = Invoke-GitText $resolved @('diff', '--binary', 'HEAD', '--')
  [ordered]@{
    repository = $resolved
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    commit = $commit
    statusSha256 = Get-Sha256Text $status
    trackedDiffSha256 = Get-Sha256Text $trackedDiff
    status = @($status -split "`n" | Where-Object { $_ })
  }
}

function Test-RepositorySnapshot {
  param([Parameter(Mandatory)]$Baseline, [Parameter(Mandatory)]$Current)
  $same = $Baseline.commit -eq $Current.commit -and
    $Baseline.statusSha256 -eq $Current.statusSha256 -and
    $Baseline.trackedDiffSha256 -eq $Current.trackedDiffSha256
  [ordered]@{
    validated = $same
    commitUnchanged = $Baseline.commit -eq $Current.commit
    statusUnchanged = $Baseline.statusSha256 -eq $Current.statusSha256
    trackedDiffUnchanged = $Baseline.trackedDiffSha256 -eq $Current.trackedDiffSha256
  }
}

function Get-DockerInventory {
  param([Parameter(Mandatory)][string]$Network)
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'docker CLI is not available' }
  $version = (& docker version --format '{{json .}}' 2>&1) -join ''
  if ($LASTEXITCODE -ne 0) { throw "Docker is unavailable: $version" }
  $networkJson = (& docker network inspect $Network 2>&1) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "Required Docker network is unavailable: $Network" }
  $containers = @()
  foreach ($line in @(& docker ps --no-trunc --format '{{json .}}')) {
    if ($line) { $containers += ($line | ConvertFrom-Json) }
  }
  [ordered]@{
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    network = $Network
    docker = ($version | ConvertFrom-Json)
    containers = @($containers)
    networkInspectSha256 = Get-Sha256Text $networkJson
  }
}

function Get-ContainerPublishedPorts {
  param([Parameter(Mandatory)][string]$ContainerName)
  $json = (& docker inspect $ContainerName --format '{{json .NetworkSettings.Ports}}' 2>&1) -join ''
  if ($LASTEXITCODE -ne 0) { throw "Unable to inspect ports for ${ContainerName}: $json" }
  $ports = $json | ConvertFrom-Json
  $result = @()
  foreach ($property in $ports.PSObject.Properties) {
    foreach ($binding in @($property.Value)) {
      if ($null -ne $binding) {
        $result += [ordered]@{ containerPort=$property.Name; hostIp=$binding.HostIp; hostPort=[int]$binding.HostPort }
      }
    }
  }
  return @($result)
}

function New-CampaignNames {
  param([Parameter(Mandatory)][ValidateSet('HTTP','GRPC','HTTP_BATCH')][string]$Runtime, [Parameter(Mandatory)][string]$CampaignId)
  Assert-BenchmarkCampaignId $CampaignId | Out-Null
  $slug = $CampaignId.ToLowerInvariant() -replace '[^a-z0-9-]', '-'
  $runtimeSlug = $Runtime.ToLowerInvariant().Replace('_','-')
  $prefix = "fpbench-$runtimeSlug-$slug"
  [ordered]@{
    prefix = $prefix
    runtime = "$prefix-runtime"
    integration = "$prefix-integration"
    rawTopic = "$prefix-raw"
    outputTopic = "$prefix-output"
    dlqTopic = "$prefix-dlq"
    consumerGroup = "$prefix-consumer"
    runtimeId = "$prefix-runtime"
    mappingName = "$prefix-mapping"
  }
}

function Get-CleanupPlan {
  param([Parameter(Mandatory)]$Manifest, [Parameter(Mandatory)]$Config)
  $id = [string]$Manifest.campaignId
  Assert-BenchmarkCampaignId $id | Out-Null
  @(
    [ordered]@{ kind='container'; selector="label=$($Config.campaignLabel)=$id"; action='docker rm --force <matched benchmark container IDs>' },
    [ordered]@{ kind='topic'; targets=@($Manifest.names.rawTopic,$Manifest.names.outputTopic,$Manifest.names.dlqTopic); action='delete exact run-scoped topic names' },
    [ordered]@{ kind='consumer-group'; targets=@($Manifest.names.consumerGroup); action='delete exact run-scoped consumer group' },
    [ordered]@{ kind='runtime'; targets=@($Manifest.names.runtimeId); action='delete exact run-scoped runtime via control-plane API' }
  )
}

Export-ModuleMember -Function Get-BenchmarkRoot,Read-CampaignConfig,Assert-BenchmarkCampaignId,Test-BenchmarkPreflightReady,Test-BenchmarkStateGateEvidence,Get-Sha256Text,New-RepositorySnapshot,Test-RepositorySnapshot,Get-DockerInventory,Get-ContainerPublishedPorts,New-CampaignNames,Get-CleanupPlan
