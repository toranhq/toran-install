# Installs Toran on Windows 11 from toran.run (#2480): irm https://toran.run/install.ps1 | iex
# TORAN_INSTALLER_RELEASE=v0.100.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Registry = 'https://ghcr.io'
$Repository = 'toranhq/toran'
$Scope = 'read:packages'
$ScopeFix = 'gh auth refresh -h github.com -s read:packages'
$AccessFix = 'ask the maintainer for package access'

function Stop-Install([string]$Message) {
  throw "toran install: $Message"
}

function Invoke-Native([scriptblock]$Command) {
  $before = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & $Command 2>&1
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $before
  }
  return @{ Code = $code; Text = (($out | ForEach-Object { "$_" }) -join [Environment]::NewLine) }
}

function Invoke-Interactive([scriptblock]$Command) {
  $before = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $Command | Out-Host
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $before
  }
  return @{ Code = $code }
}

function Test-Yes([string]$Question) {
  $answer = Read-Host "$Question [y/N]"
  return $answer -match '^(y|yes)$'
}

function Test-Tool([string]$Name) {
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machine;$user"
}

Write-Host 'This installs Toran on this PC:'
Write-Host '  - toran.exe, from ghcr.io/toranhq/toran, into %LOCALAPPDATA%\Programs\toran, and that folder on your user PATH'
Write-Host '  - GitHub CLI (gh) and Git with winget, only if they are missing and you say yes'
Write-Host '  - a gh sign-in with the read:packages scope, in your browser, if you have none'
Write-Host 'It never asks for administrator rights on its own and stores no token.'
if (-not (Test-Yes 'Continue?')) { Stop-Install 'stopped: nothing was installed' }

$missing = @()
if (-not (Test-Tool 'gh')) { $missing += @{ Name = 'GitHub CLI'; Id = 'GitHub.cli' } }
if (-not (Test-Tool 'git')) { $missing += @{ Name = 'Git'; Id = 'Git.Git' } }
if ($missing.Count -gt 0) {
  $names = ($missing | ForEach-Object { $_.Name }) -join ' and '
  if (-not (Test-Tool 'winget')) {
    Stop-Install "$names needed: install them from https://cli.github.com and https://git-scm.com, then run this again"
  }
  if (-not (Test-Yes "Install $names with winget?")) {
    Stop-Install "$names needed: run winget install --id GitHub.cli -e and winget install --id Git.Git -e, then run this again"
  }
  foreach ($tool in $missing) {
    $id = $tool.Id
    $r = Invoke-Interactive { winget install --id $id -e --source winget --accept-package-agreements --accept-source-agreements }
    if ($r.Code -ne 0) { Stop-Install "could not install $($tool.Name): run winget install --id $id -e --source winget, then run this again" }
  }
  Update-SessionPath
  if (-not (Test-Tool 'gh') -or -not (Test-Tool 'git')) {
    Stop-Install 'gh and git are installed but not on this window''s PATH: open a new PowerShell window and run this again'
  }
}

$auth = Invoke-Native { gh auth status --hostname github.com --active }
if ($auth.Code -ne 0) { $auth = Invoke-Native { gh auth status --hostname github.com } }
if ($auth.Code -ne 0) {
  Write-Host "gh is not signed in to github.com. Signing in with the $Scope scope; approve it in the browser."
  $r = Invoke-Interactive { gh auth login --web -h github.com -s read:packages }
  if ($r.Code -ne 0) { Stop-Install 'gh sign-in failed: run gh auth login -h github.com -s read:packages, then run this again' }
} else {
  $scopes = [regex]::Match($auth.Text, 'Token scopes:[ \t]*([^\r\n]*)')
  if ($scopes.Success) {
    $listed = $scopes.Groups[1].Value.Trim()
    $have = ($listed -replace "[' ]", '') -split ','
    if (($have -notcontains $Scope) -and ($have -notcontains 'none') -and ($listed -ne '')) {
      Write-Host "gh needs the $Scope scope to read the Toran package. Approve it in the browser."
      $r = Invoke-Interactive { gh auth refresh -h github.com -s read:packages }
      if ($r.Code -ne 0) { Stop-Install "the scope was not added: run $ScopeFix, then run this again" }
    }
  }
}

function Stop-NoAccess([string]$Why) {
  Stop-Install "no access to ghcr.io/$Repository ($Why): $AccessFix; if you were granted it, give gh the $Scope scope: $ScopeFix"
}

$basic = Invoke-Native { gh auth token --hostname github.com }
if ($basic.Code -ne 0 -or -not $basic.Text) { Stop-Install 'gh has no github.com token: run gh auth login -h github.com -s read:packages, then run this again' }
$credential = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("toran:$($basic.Text.Trim())"))
$basic = $null
try {
  $exchange = Invoke-RestMethod "$Registry/token?scope=repository:$($Repository):pull&service=ghcr.io" -Headers @{ Authorization = "Basic $credential" }
} catch {
  Stop-Install "ghcr.io refused gh's github.com sign-in: sign in again with gh auth login, or $AccessFix"
}
$credential = $null
$headers = @{ Authorization = "Bearer $($exchange.token)" }
try {
  $manifest = Invoke-RestMethod "$Registry/v2/$Repository/manifests/stable" -Headers @{ Authorization = "Bearer $($exchange.token)"; Accept = 'application/vnd.oci.image.manifest.v1+json' }
} catch {
  Stop-NoAccess 'the stable release cannot be read'
}
$layer = $manifest.layers | Where-Object { $_.annotations.'org.opencontainers.image.title' -eq 'toran-win32-x64.exe' } | Select-Object -First 1
if (-not $layer) { Stop-Install 'the release has no toran-win32-x64.exe' }

$folder = Join-Path $env:LOCALAPPDATA 'Programs\toran'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$target = Join-Path $folder 'toran.exe'
$part = Join-Path $folder 'toran.exe.download'
try {
  Invoke-WebRequest "$Registry/v2/$Repository/blobs/$($layer.digest)" -Headers $headers -OutFile $part
} catch {
  Remove-Item -Force -ErrorAction SilentlyContinue $part
  Stop-NoAccess 'the binary cannot be downloaded'
}
$headers = $null
$exchange = $null

$got = (Get-FileHash $part -Algorithm SHA256).Hash.ToLower()
$want = $layer.digest.Substring(7)
$published = $layer.annotations.'io.github.toranhq.toran.sha256'
if ($got -ne $want -or ($published -and $got -ne $published)) {
  Remove-Item -Force $part
  Stop-Install 'the downloaded binary''s SHA-256 does not match the release; run this again'
}
Move-Item -Force $part $target
& $target install
if ($LASTEXITCODE -ne 0) { Stop-Install "toran.exe install failed (exit $LASTEXITCODE): fix what it says, then run $target install" }
