[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceRoot = Join-Path $PSScriptRoot 'src\main\java'
$buildRoot = Join-Path $PSScriptRoot 'build'
$classes = Join-Path $buildRoot 'classes'
$jarPath = Join-Path $buildRoot 'flowplane-benchmark-measurement.jar'
$sources = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -Filter '*.java' | ForEach-Object FullName)
if ($sources.Count -eq 0) { throw 'No measurement exporter Java sources found' }

New-Item -ItemType Directory -Force -Path $classes | Out-Null
& javac --release 17 -encoding UTF-8 -d $classes @sources
if ($LASTEXITCODE -ne 0) { throw "javac failed with exit code $LASTEXITCODE" }
& jar --create --file $jarPath -C $classes .
if ($LASTEXITCODE -ne 0) { throw "jar failed with exit code $LASTEXITCODE" }

[pscustomobject]@{Jar=$jarPath;Classes=$classes;SourceCount=$sources.Count} | ConvertTo-Json -Compress
