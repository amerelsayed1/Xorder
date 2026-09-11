<#
.SYNOPSIS
  Sets up, or upgrades, the PostgreSQL that XOrder POS keeps its database in.

.DESCRIPTION
  Run by the installer, elevated, on the machine that keeps the database.
  Every step looks before it acts, so running it again is how an upgrade
  applies new migrations — and how a half-finished install is finished.

  The database logic is not here. Accounts, ownership, grants and migrations
  are `pos_migrate.exe`, the same code the database suite tests on every run;
  this script only does what is Windows: initdb, the service, the firewall,
  the file permissions.

  Logs to  %ProgramData%\XOrder POS\logs\provision.log. Passwords are never
  written to the log: they reach pos_migrate through the environment.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $AppDir,
  # Let tills on the local network reach this database.
  [switch] $Lan,
  # Stop and remove the service. The data stays.
  [switch] $Uninstall
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root      = Join-Path $env:ProgramData 'XOrder POS'
$DataDir   = Join-Path $Root 'pgdata'
$LogDir    = Join-Path $Root 'logs'
$CredFile  = Join-Path $Root 'install-credentials.json'
$Service   = 'XOrderPOS-PostgreSQL'
$Database  = 'xorder_pos'
$PgBin     = Join-Path $AppDir 'pgsql\bin'
$Migrate   = Join-Path $AppDir 'tools\pos_migrate.exe'

# Well-known security identifiers, never names: on an Arabic Windows the
# Administrators group is not called "Administrators", and icacls with the
# English name fails there and nowhere a developer would notice.
$Administrators = '*S-1-5-32-544'
$System         = '*S-1-5-18'
$NetworkService = '*S-1-5-20'

New-Item -ItemType Directory -Force -Path $Root, $LogDir | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'provision.log') -Append | Out-Null

function Invoke-Checked([string] $Exe, [string[]] $Arguments) {
  & $Exe @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$(Split-Path $Exe -Leaf) exited with $LASTEXITCODE" }
}

# 24 letters and digits from the system's cryptographic generator. Letters and
# digits only, so the value survives every file and command it passes through.
function New-Secret {
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  $out = ''
  while ($out.Length -lt 24) {
    $bytes = New-Object byte[] 48
    $rng.GetBytes($bytes)
    $out += ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '')
  }
  return $out.Substring(0, 24)
}

# Administrators and SYSTEM only — plus, for the data directory, the account
# the service runs as. Nothing inherited from ProgramData, which lets every
# user read.
function Set-Owners([string] $Path, [string[]] $Extra = @()) {
  $grants = @("${Administrators}:(OI)(CI)F", "${System}:(OI)(CI)F") + $Extra
  if (-not (Test-Path $Path -PathType Container)) {
    $grants = $grants | ForEach-Object { $_ -replace '\(OI\)\(CI\)', '' }
  }
  & icacls $Path /inheritance:r /grant:r @grants | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "icacls could not restrict $Path" }
}

function Get-FreePort {
  foreach ($candidate in 5432..5442) {
    if (-not (Get-NetTCPConnection -LocalPort $candidate -State Listen -ErrorAction SilentlyContinue)) {
      return $candidate
    }
  }
  throw 'Ports 5432 to 5442 are all taken; free one and run setup again.'
}

# Rewrites the block between our markers, so turning LAN access off on a later
# run takes it away again rather than leaving the first run's answer in place.
function Set-Block([string] $File, [string] $Body) {
  $begin = '# >>> XOrder POS (managed by setup; edits here are replaced)'
  $end   = '# <<< XOrder POS'
  $text  = if (Test-Path $File) { Get-Content $File -Raw } else { '' }
  $text  = [regex]::Replace($text, "(?s)\r?\n?$([regex]::Escape($begin)).*?$([regex]::Escape($end))\r?\n?", "`r`n")
  $text  = $text.TrimEnd() + "`r`n$begin`r`n$Body`r`n$end`r`n"
  Set-Content -Path $File -Value $text -Encoding ASCII -NoNewline
}

function Wait-Ready([int] $Port) {
  foreach ($attempt in 1..60) {
    & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $Port -q
    if ($LASTEXITCODE -eq 0) { return }
    Start-Sleep -Seconds 1
  }
  throw "PostgreSQL did not start listening on port $Port within a minute."
}

try {
  if ($Uninstall) {
    if (Get-Service $Service -ErrorAction SilentlyContinue) {
      Stop-Service $Service -ErrorAction SilentlyContinue
      & (Join-Path $PgBin 'pg_ctl.exe') unregister -N $Service
    }
    # A restaurant's trading history is not the uninstaller's to delete.
    Write-Host "Service removed. The database stays in $DataDir."
    exit 0
  }

  $fresh = -not (Test-Path (Join-Path $DataDir 'PG_VERSION'))

  if ($fresh) {
    $creds = [ordered]@{
      port      = Get-FreePort
      database  = $Database
      superuser = [ordered]@{ name = 'postgres';   password = New-Secret }
      admin     = [ordered]@{ name = 'pos_admin';  password = New-Secret }
      till      = [ordered]@{ name = 'pos_till';   password = New-Secret }
      backup    = [ordered]@{ name = 'pos_backup'; password = New-Secret }
    }
    # Written and locked down BEFORE initdb: if anything below fails, the
    # passwords are already where the technician will look for them.
    $creds | ConvertTo-Json -Depth 3 | Set-Content -Path $CredFile -Encoding UTF8
    Set-Owners $CredFile

    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    $pwFile = Join-Path $env:TEMP ("xorder-" + [guid]::NewGuid().ToString() + '.tmp')
    try {
      Set-Content -Path $pwFile -Value $creds.superuser.password -NoNewline -Encoding ASCII
      # scram-sha-256 from the first second: never `trust`, not even on
      # localhost, on a machine anybody in the restaurant can sit at.
      Invoke-Checked (Join-Path $PgBin 'initdb.exe') @(
        '-D', $DataDir, '-U', 'postgres', '-A', 'scram-sha-256',
        "--pwfile=$pwFile", '-E', 'UTF8', '--locale=C'
      )
    } finally {
      Remove-Item $pwFile -Force -ErrorAction SilentlyContinue
    }
  } else {
    if (-not (Test-Path $CredFile)) {
      throw "The database is here but $CredFile is not. Restore it from the technician's copy and run setup again."
    }
    $creds = Get-Content $CredFile -Raw | ConvertFrom-Json
  }
  $port = [int] $creds.port

  # The service account must own its data; nobody else may read it.
  Set-Owners $DataDir @("${NetworkService}:(OI)(CI)F")

  $listen = if ($Lan) { '*' } else { 'localhost' }
  Set-Block (Join-Path $DataDir 'postgresql.conf') "port = $port`r`nlisten_addresses = '$listen'"
  $hba = if ($Lan) {
    # Private ranges only, and always with a password. A public address is
    # never let in by setup, whatever the network looks like.
    "host all all 10.0.0.0/8 scram-sha-256`r`n" +
    "host all all 172.16.0.0/12 scram-sha-256`r`n" +
    'host all all 192.168.0.0/16 scram-sha-256'
  } else { '# local only' }
  Set-Block (Join-Path $DataDir 'pg_hba.conf') $hba

  $rule = 'XOrder POS database'
  Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  if ($Lan) {
    New-NetFirewallRule -DisplayName $rule -Direction Inbound -Protocol TCP `
      -LocalPort $port -Profile Private, Domain -Action Allow | Out-Null
  }

  if (-not (Get-Service $Service -ErrorAction SilentlyContinue)) {
    Invoke-Checked (Join-Path $PgBin 'pg_ctl.exe') @(
      'register', '-N', $Service, '-D', $DataDir, '-S', 'auto',
      '-U', 'NT AUTHORITY\NetworkService'
    )
  }
  # Restarted, not just started: the port or the LAN answer may have changed.
  Restart-Service $Service -Force
  Wait-Ready $port

  $common = @('--host', '127.0.0.1', '--port', "$port", '--database', $Database, '--no-verify-tls')
  try {
    # As the superuser: the accounts, then the database owned by pos_admin,
    # then stop — each one left alone if it is already there.
    $env:POS_PG_PASSWORD     = $creds.superuser.password
    $env:POS_ADMIN_PASSWORD  = $creds.admin.password
    $env:POS_TILL_PASSWORD   = $creds.till.password
    $env:POS_BACKUP_PASSWORD = $creds.backup.password
    Invoke-Checked $Migrate ($common + @(
      '--user', 'postgres', '--create-roles', '--create-database',
      '--owner', 'pos_admin', '--no-migrate'
    ))

    # As the owner: every pending migration, then the till's grants. The
    # tables are pos_admin's, which is what lets a restore replace them.
    $env:POS_PG_PASSWORD = $creds.admin.password
    Invoke-Checked $Migrate ($common + @('--user', 'pos_admin', '--grant-to', 'pos_till'))
  } finally {
    'POS_PG_PASSWORD', 'POS_ADMIN_PASSWORD', 'POS_TILL_PASSWORD', 'POS_BACKUP_PASSWORD' |
      ForEach-Object { Remove-Item "Env:$_" -ErrorAction SilentlyContinue }
  }

  Write-Host "Database ready: $Database on 127.0.0.1:$port. Accounts are in $CredFile."
  exit 0
} catch {
  Write-Host "Setup could not finish: $($_.Exception.Message)"
  exit 1
} finally {
  Stop-Transcript | Out-Null
}
