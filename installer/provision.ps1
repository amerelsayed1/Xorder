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
  written to the log: they reach pos_migrate through the environment. Nor is
  the network certificate's private key: it is made in memory, written once
  to a file only the service can read, and never printed.

  Exit codes: 0 ready; 2 ready on this machine only, because -Lan was asked
  for and the network certificate could not be made (the LAN is NOT opened
  without one); 3 ready, and the network certificate was renewed, so every
  till must be paired again; 4 ready, encrypted, and still accepting the
  unencrypted tills an install from before encryption had - pair each, then
  run this again with -Lan -LanTls On; 1 failed.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $AppDir,
  # Let tills on the local network reach this database - encrypted.
  [switch] $Lan,
  # A technician's choice, made at an elevated prompt and never by the
  # installer: Off also accepts unencrypted LAN connections (for tills that
  # cannot be paired yet), On takes that back. Remembered between runs, so an
  # upgrade does not silently undo either answer. Empty keeps the last one;
  # never set means On.
  [ValidateSet('On', 'Off')] [string] $LanTls = '',
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

# The LAN certificate. Inside the data directory, which only Administrators,
# SYSTEM and the service account can read; relative names in postgresql.conf
# resolve against it. The public half is also published beside the
# credentials file, where the app's Management pane reads its fingerprint
# (FilePublishedServerCertificate in lib/data/postgres/pos_tls.dart).
$CertFile    = Join-Path $DataDir 'server.crt'
$KeyFile     = Join-Path $DataDir 'server.key'
$PublicCert  = Join-Path $Root 'server-certificate.pem'
# In the data directory, not beside the credentials: ProgramData lets any
# user create files, and this one decides whether the LAN may be plaintext.
$PlainMarker = Join-Path $DataDir 'xorder-lan-plaintext.txt'
# 825 days is the longest validity Apple's TLS policy accepts, and a child
# till may be an iPad. Renewed by the first setup run inside its last 60.
$CertDays    = 825
$RenewWithin = 60
$Ascii       = New-Object System.Text.ASCIIEncoding

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

function ConvertTo-Pem([string] $Label, [byte[]] $Der) {
  $b64 = [Convert]::ToBase64String($Der)
  $lines = for ($i = 0; $i -lt $b64.Length; $i += 64) {
    $b64.Substring($i, [Math]::Min(64, $b64.Length - $i))
  }
  return "-----BEGIN $Label-----`n" + ($lines -join "`n") + "`n-----END $Label-----`n"
}

function Get-Sha256Hex([byte[]] $Bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
  } finally {
    $sha.Dispose()
  }
}

# AB:CD:... - the shape the app's Management pane and the till's wizard show.
function Format-Fingerprint([string] $Hex) {
  $pairs = for ($i = 0; $i -lt $Hex.Length; $i += 2) { $Hex.Substring($i, 2).ToUpperInvariant() }
  return ($pairs -join ':')
}

# The certificate in a PEM file, or $null when there is none to read.
function Read-PemCertificate([string] $Path) {
  if (-not (Test-Path $Path)) { return $null }
  try {
    $text = [System.IO.File]::ReadAllText($Path)
    $match = [regex]::Match($text, "-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----", 'Singleline')
    if (-not $match.Success) { return $null }
    $der = [Convert]::FromBase64String(($match.Groups[1].Value -replace '\s', ''))
    return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($der)
  } catch {
    return $null
  }
}

# Every name and private address a till might type for this machine. A till
# verifies the certificate against what it dialled, so a name missing here is
# a till that cannot connect by that name.
function Get-LanNames {
  $dns = New-Object System.Collections.Generic.List[string]
  $ips = New-Object System.Collections.Generic.List[string]
  $candidates = @($env:COMPUTERNAME, [System.Net.Dns]::GetHostName(), "$($env:COMPUTERNAME).local", 'localhost')
  try { $candidates += [System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName()).HostName } catch { }
  foreach ($name in $candidates) {
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $lower = $name.Trim().ToLowerInvariant()
    if (-not $dns.Contains($lower)) { $dns.Add($lower) }
  }
  $ips.Add('127.0.0.1')
  foreach ($address in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
    $ip = $address.IPAddress
    if ($ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' -and -not $ips.Contains($ip)) {
      $ips.Add($ip)
    }
  }
  return @{ Dns = $dns; Ip = $ips }
}

# A self-signed certificate for this machine's PostgreSQL, made with what
# every Windows 10 has: .NET's CertificateRequest (Framework 4.7.2+, Windows
# Update ships it), in memory. Not openssl.exe: whether EDB's binaries zip
# carries one in pgsql\bin could not be confirmed, and one that is there
# needs an openssl.cnf the zip does not ship. Not New-SelfSignedCertificate:
# it puts the key in the machine's key store, where it would outlive the
# file and need removing again.
#
# Shaped the way PostgreSQL's own docs shape one for verify-full: its own
# anchor (CA:TRUE, keyCertSign), plus serverAuth and every LAN name, so the
# till can make exactly this certificate the only one it accepts.
function New-ServerCertificate {
  if (-not ('System.Security.Cryptography.X509Certificates.CertificateRequest' -as [type])) {
    throw 'Making the network certificate needs .NET Framework 4.7.2 or later. Install it from Windows Update and run setup again.'
  }
  $x509 = 'System.Security.Cryptography.X509Certificates'
  $names = Get-LanNames

  # Ephemeral and explicitly exportable, so the PKCS#8 export below does not
  # depend on what a given Windows build defaults to.
  $creation = [System.Security.Cryptography.CngKeyCreationParameters]::new()
  $creation.ExportPolicy = [System.Security.Cryptography.CngExportPolicies]::AllowPlaintextExport
  $creation.Parameters.Add([System.Security.Cryptography.CngProperty]::new(
      'Length', [BitConverter]::GetBytes([int] 2048), [System.Security.Cryptography.CngPropertyOptions]::None))
  $key = [System.Security.Cryptography.CngKey]::Create(
    [System.Security.Cryptography.CngAlgorithm]::Rsa, [NullString]::Value, $creation)
  $rsa = [System.Security.Cryptography.RSACng]::new($key)
  try {
    $subject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=$($env:COMPUTERNAME), O=XOrder POS")
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
      $subject, $rsa,
      [System.Security.Cryptography.HashAlgorithmName]::SHA256,
      [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

    $request.CertificateExtensions.Add(
      (New-Object "$x509.X509BasicConstraintsExtension" -ArgumentList $true, $true, 0, $true))
    $usage = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags] 'DigitalSignature, KeyEncipherment, KeyCertSign'
    $request.CertificateExtensions.Add(
      (New-Object "$x509.X509KeyUsageExtension" -ArgumentList $usage, $true))
    $serverAuth = New-Object System.Security.Cryptography.OidCollection
    [void] $serverAuth.Add((New-Object System.Security.Cryptography.Oid -ArgumentList '1.3.6.1.5.5.7.3.1'))
    $request.CertificateExtensions.Add(
      (New-Object "$x509.X509EnhancedKeyUsageExtension" -ArgumentList $serverAuth, $false))
    $request.CertificateExtensions.Add(
      (New-Object "$x509.X509SubjectKeyIdentifierExtension" -ArgumentList $request.PublicKey, $false))

    $san = New-Object "$x509.SubjectAlternativeNameBuilder"
    foreach ($name in $names.Dns) {
      try { $san.AddDnsName($name) } catch { Write-Host "Left the name $name out of the certificate: $($_.Exception.Message)" }
    }
    foreach ($ip in $names.Ip) { $san.AddIpAddress([System.Net.IPAddress]::Parse($ip)) }
    $request.CertificateExtensions.Add($san.Build($false))

    $now = [DateTimeOffset]::UtcNow
    $cert = $request.CreateSelfSigned($now.AddDays(-1), $now.AddDays($CertDays - 1))
    try {
      $keyDer = $key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
      return @{
        CertificatePem = (ConvertTo-Pem 'CERTIFICATE' $cert.RawData)
        KeyPem         = (ConvertTo-Pem 'PRIVATE KEY' $keyDer)
        Sha256         = (Get-Sha256Hex $cert.RawData)
        NotAfter       = $cert.NotAfter
        # @() first: a generic List has no + of its own in PowerShell.
        Names          = ((@($names.Dns) + @($names.Ip)) -join ', ')
      }
    } finally {
      $cert.Dispose()
    }
  } finally {
    $rsa.Dispose()
    $key.Dispose()
  }
}

# The key file: created empty and locked down BEFORE the key goes in, so it is
# never readable under ProgramData's inherited permissions, not even for the
# moment between writing and restricting. PostgreSQL on Windows does not check
# a key file's permissions itself, so this is the only check there is.
function Write-PrivateKey([string] $Path, [string] $Pem) {
  if (-not (Test-Path $Path)) { New-Item -ItemType File -Path $Path -Force | Out-Null }
  Set-Owners $Path @("${NetworkService}:R")
  [System.IO.File]::WriteAllText($Path, $Pem, $Ascii)
}

# The certificate to keep: both halves there and not inside its last
# $RenewWithin days. Otherwise $null, and a new one is made. Never replaced
# for any other reason, because its fingerprint is what every till on the LAN
# was paired with: a new one means pairing each of them again.
function Get-KeptCertificate {
  if (-not (Test-Path $KeyFile)) { return $null }
  $cert = Read-PemCertificate $CertFile
  if ($null -eq $cert) { return $null }
  if ($cert.NotAfter -lt (Get-Date).AddDays($RenewWithin)) {
    Write-Host "The network certificate expires on $($cert.NotAfter.ToString('yyyy-MM-dd')); making a new one."
    return $null
  }
  return $cert
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

  # The LAN is opened encrypted or not at all. A certificate that cannot be
  # made leaves the database on this machine only - it never falls back to
  # opening the LAN in plaintext - and the installer says so (exit 2).
  $lanOpen = $false
  $renewed = $false
  if ($Lan) {
    try {
      $kept = Get-KeptCertificate
      if ($null -eq $kept) {
        $hadOne = Test-Path $CertFile
        $made = New-ServerCertificate
        Write-PrivateKey $KeyFile $made.KeyPem
        [System.IO.File]::WriteAllText($CertFile, $made.CertificatePem, $Ascii)
        $made.KeyPem = $null
        $renewed = $hadOne
        Write-Host "Network certificate made for $($made.Names); valid until $($made.NotAfter.ToString('yyyy-MM-dd'))."
        Write-Host "Its SHA-256 fingerprint: $(Format-Fingerprint $made.Sha256)"
        if ($renewed) { Write-Host 'It replaces the previous one: pair every till on the network with this machine again.' }
      } else {
        Write-Host "Network certificate kept; valid until $($kept.NotAfter.ToString('yyyy-MM-dd'))."
        Write-Host "Its SHA-256 fingerprint: $(Format-Fingerprint (Get-Sha256Hex $kept.RawData))"
      }
      # Re-asserted every run: a key file somebody copied about, or restored
      # from a backup, must not keep whatever permissions it arrived with.
      Set-Owners $KeyFile @("${NetworkService}:R")
      # Public by nature; written fresh so it takes ProgramData's permissions
      # rather than the data directory's.
      [System.IO.File]::WriteAllText($PublicCert, [System.IO.File]::ReadAllText($CertFile), $Ascii)
      $lanOpen = $true
    } catch {
      Write-Host "The network certificate could not be made: $($_.Exception.Message)"
      Write-Host 'The database stays on this machine only. Other tills cannot use it until setup runs again and the certificate is made.'
    }
  }
  if (-not $lanOpen) { Remove-Item $PublicCert -Force -ErrorAction SilentlyContinue }

  if ($LanTls -eq 'Off') {
    Set-Content -Path $PlainMarker -Encoding ASCII -Value "Unencrypted LAN connections accepted. Set by $env:USERDOMAIN\$env:USERNAME on $(Get-Date -Format o)."
    Write-Host 'Unencrypted LAN connections will be accepted as well as encrypted ones (-LanTls Off).'
  } elseif ($LanTls -eq 'On') {
    Remove-Item $PlainMarker -Force -ErrorAction SilentlyContinue
  }

  # An install from before encryption let its tills in with plain `host`
  # lines, and every one of them was set up to connect unencrypted. Turning
  # those lines into hostssl on the upgrade would lock all of them out at
  # once, mid-service, with no screen on the till that can fix it - a till
  # that cannot reach its database cannot open Management to pair. So the
  # upgrade carries the old answer over, says so, and leaves the tightening
  # to the technician once each till is paired: TLS on, plaintext still
  # accepted, until -LanTls On. Never on a fresh install, never when somebody
  # has already given an answer.
  $carriedOver = $false
  $hbaFile = Join-Path $DataDir 'pg_hba.conf'
  if ($lanOpen -and $LanTls -eq '' -and -not (Test-Path $PlainMarker) -and (Test-Path $hbaFile) -and
      ([System.IO.File]::ReadAllText($hbaFile) -match '(?m)^host all all 10\.0\.0\.0/8 ')) {
    Set-Content -Path $PlainMarker -Encoding ASCII -Value "Carried over on $(Get-Date -Format o): this install accepted unencrypted LAN connections before setup encrypted them. Pair every till, then run provision.ps1 with -Lan -LanTls On."
    Write-Host 'This install accepted unencrypted tills before; it still does, alongside encrypted ones. Pair every till, then run setup with -Lan -LanTls On.'
    $carriedOver = $true
  }
  $plaintextLan = Test-Path $PlainMarker

  $listen = if ($lanOpen) { '*' } else { 'localhost' }
  $conf = "port = $port`r`nlisten_addresses = '$listen'"
  if ($lanOpen) {
    $conf += "`r`nssl = on`r`nssl_cert_file = 'server.crt'`r`nssl_key_file = 'server.key'" +
             "`r`nssl_min_protocol_version = 'TLSv1.2'"
  }
  Set-Block (Join-Path $DataDir 'postgresql.conf') $conf
  $hba = if ($lanOpen) {
    # Private ranges only, and always with a password. A public address is
    # never let in by setup, whatever the network looks like. hostssl, so a
    # till that is not encrypting is refused before its password is asked
    # for - unless a technician ran -LanTls Off, which widens these to host
    # (encrypted still accepted, plaintext as well). The loopback lines
    # initdb wrote stay as they are: this machine's own till uses them.
    $kind = if ($plaintextLan) { 'host' } else { 'hostssl' }
    "$kind all all 10.0.0.0/8 scram-sha-256`r`n" +
    "$kind all all 172.16.0.0/12 scram-sha-256`r`n" +
    "$kind all all 192.168.0.0/16 scram-sha-256"
  } else { '# local only' }
  Set-Block (Join-Path $DataDir 'pg_hba.conf') $hba

  $rule = 'XOrder POS database'
  Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  if ($lanOpen) {
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
  if ($Lan -and -not $lanOpen) { exit 2 }
  if ($renewed) { exit 3 }
  if ($carriedOver) { exit 4 }
  exit 0
} catch {
  Write-Host "Setup could not finish: $($_.Exception.Message)"
  exit 1
} finally {
  Stop-Transcript | Out-Null
}
