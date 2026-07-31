[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
  [Parameter(Mandatory)][ValidateSet('Plan','Start','DumpStop')][string]$Action,
  [Parameter(Mandatory)][string]$CampaignId,
  [string]$ContainerName='flowplane-kafka',
  [string]$RecordingOutput,
  [string]$EvidenceOutput,
  [switch]$Execute,
  [string]$ConfirmCampaign
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $root 'scripts\Campaign.Common.psm1') -Force
Assert-BenchmarkCampaignId $CampaignId|Out-Null
if($ContainerName-ne'flowplane-kafka'){throw 'Broker JFR collector is restricted to the existing flowplane-kafka container'}
$recordingName='flowplane_broker_'+$CampaignId.Replace('-','_')
$containerRecording="/tmp/flowplane-benchmark-broker-$CampaignId.jfr"

function Invoke-DockerCommand([string[]]$Arguments,[switch]$AllowError){
  $lines=@(& docker @Arguments 2>&1);$code=$LASTEXITCODE
  if($code-ne0-and-not$AllowError){throw "docker $($Arguments-join' ') exited ${code}: $($lines-join[Environment]::NewLine)"}
  [pscustomobject]@{code=$code;lines=@($lines|ForEach-Object{[string]$_})}
}
function BrokerPid {
  $listed=Invoke-DockerCommand @('exec',$ContainerName,'timeout','15','jcmd','-l')
  $jvmLines=@($listed.lines|Where-Object{$_-match'^\s*\d+\s+kafka\.Kafka(?:\s|$)'})
  if($jvmLines.Count-ne1){throw "Expected exactly one kafka.Kafka JVM; observed $($jvmLines.Count)"}
  $parsed=[regex]::Match($jvmLines[0],'^\s*(\d+)')
  if(-not$parsed.Success){throw 'Kafka JVM PID could not be parsed'}
  [string]$parsed.Groups[1].Value
}
function RecordingCheck([string]$BrokerProcessId){
  (Invoke-DockerCommand @('exec',$ContainerName,'timeout','30','jcmd',$BrokerProcessId,'JFR.check')).lines-join[Environment]::NewLine
}
function Write-Evidence($Value){
  if([string]::IsNullOrWhiteSpace($EvidenceOutput)){return}
  $target=[IO.Path]::GetFullPath($EvidenceOutput)
  if(Test-Path -LiteralPath $target){throw "Refusing to overwrite broker JFR evidence: $target"}
  $parent=Split-Path -Parent $target
  if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
  [IO.File]::WriteAllText($target,($Value|ConvertTo-Json -Depth 12)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}

$pidValue=BrokerPid
$check=RecordingCheck $pidValue
$plan=[ordered]@{
  schemaVersion=1;kind='flowplane-benchmark-kafka-broker-jfr';action=$Action;campaignId=$CampaignId
  container=$ContainerName;brokerPid=$pidValue;recordingName=$recordingName;containerRecording=$containerRecording
  processScope='entire shared kafka.Kafka broker JVM during the measured window'
  allocationSemantics='JFR ObjectAllocationSample weighted estimate; includes unrelated broker/background allocation'
  brokerRestartRequired=$false;mutationsPerformed=$false;recordingCheck=$check
}
if($Action-eq'Plan'){$plan|ConvertTo-Json -Depth 12;exit 0}
if(-not$Execute-or$ConfirmCampaign-ne$CampaignId){throw "$Action requires -Execute and -ConfirmCampaign exactly matching $CampaignId"}

if($Action-eq'Start'){
  if($check-match[regex]::Escape($recordingName)){throw "Campaign broker JFR recording is already active: $recordingName"}
  $stale=Invoke-DockerCommand @('exec',$ContainerName,'test','-e',$containerRecording) -AllowError
  if($stale.code-eq0){throw "Campaign broker JFR file already exists in the container: $containerRecording"}
  if(-not$PSCmdlet.ShouldProcess($CampaignId,'Start campaign-scoped JFR on the existing Kafka broker JVM without restarting it')){exit 0}
  $started=Invoke-DockerCommand @('exec',$ContainerName,'timeout','30','jcmd',$pidValue,'JFR.start',"name=$recordingName",'settings=profile','disk=true','maxsize=2g')
  $after=RecordingCheck $pidValue
  if($after-notmatch[regex]::Escape($recordingName)){throw 'Kafka broker JFR start was not visible in JFR.check'}
  $evidence=$plan
  $evidence.action='Start';$evidence.mutationsPerformed=$true;$evidence.startedAtUtc=[DateTime]::UtcNow.ToString('o')
  $evidence.startOutput=$started.lines;$evidence.recordingCheck=$after
  Write-Evidence $evidence
  $evidence|ConvertTo-Json -Depth 12
  exit 0
}

if([string]::IsNullOrWhiteSpace($RecordingOutput)){throw 'DumpStop requires -RecordingOutput'}
if($check-notmatch[regex]::Escape($recordingName)){throw "Campaign broker JFR recording is not active: $recordingName"}
$hostRecording=[IO.Path]::GetFullPath($RecordingOutput)
if(Test-Path -LiteralPath $hostRecording){throw "Refusing to overwrite broker JFR recording: $hostRecording"}
$hostParent=Split-Path -Parent $hostRecording
if(-not(Test-Path -LiteralPath $hostParent)){New-Item -ItemType Directory -Force -Path $hostParent|Out-Null}
if(-not$PSCmdlet.ShouldProcess($CampaignId,'Dump and stop only the campaign-scoped Kafka broker JFR recording')){exit 0}
$dumped=$false
try{
  $dump=Invoke-DockerCommand @('exec',$ContainerName,'timeout','60','jcmd',$pidValue,'JFR.dump',"name=$recordingName","filename=$containerRecording")
  $dumped=$true
  Invoke-DockerCommand @('cp',("${ContainerName}:$containerRecording"),$hostRecording)|Out-Null
}finally{
  $stop=Invoke-DockerCommand @('exec',$ContainerName,'timeout','30','jcmd',$pidValue,'JFR.stop',"name=$recordingName") -AllowError
}
if($stop.code-ne0){throw "Kafka broker JFR dump completed but recording stop failed: $($stop.lines-join[Environment]::NewLine)"}
$afterStop=RecordingCheck $pidValue
if($afterStop-match[regex]::Escape($recordingName)){throw 'Kafka broker campaign recording remains active after JFR.stop'}
if(-not$dumped-or-not(Test-Path -LiteralPath $hostRecording -PathType Leaf)-or(Get-Item -LiteralPath $hostRecording).Length-le0){
  throw 'Kafka broker JFR dump is missing or empty'
}
$cleanup=Invoke-DockerCommand @('exec',$ContainerName,'rm','-f','--',$containerRecording) -AllowError
if($cleanup.code-ne0){throw 'Broker JFR was copied but exact container-file cleanup failed'}
$file=Get-Item -LiteralPath $hostRecording
$evidence=[ordered]@{
  schemaVersion=1;kind='flowplane-benchmark-kafka-broker-jfr';action='DumpStop';campaignId=$CampaignId
  container=$ContainerName;brokerPid=$pidValue;recordingName=$recordingName;recording=$hostRecording
  recordingBytes=$file.Length;sha256=(Get-FileHash -LiteralPath $hostRecording -Algorithm SHA256).Hash.ToLowerInvariant()
  processScope='entire shared kafka.Kafka broker JVM during the measured window'
  allocationSemantics='JFR ObjectAllocationSample weighted estimate; includes unrelated broker/background allocation'
  campaignAttribution='time-window correlation only; JFR allocation events cannot be filtered by Kafka topic'
  brokerRestarted=$false;recordingStopped=$true;containerRecordingRemoved=$true;mutationsPerformed=$true
  dumpedAtUtc=[DateTime]::UtcNow.ToString('o');dumpOutput=$dump.lines;stopOutput=$stop.lines;recordingCheckAfterStop=$afterStop
}
Write-Evidence $evidence
$evidence|ConvertTo-Json -Depth 12
