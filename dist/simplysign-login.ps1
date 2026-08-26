<#
.SYNOPSIS
  Opens a Certum SimplySign cloud-signing session on a Windows CI runner and
  publishes the resulting certificate thumbprint for dist/sign-windows.ps1.

.DESCRIPTION
  Certum's cloud code-signing key (the "Open Source Code Signing in the Cloud"
  product) is never exportable, so the PFX path in dist/sign-windows.ps1 cannot
  be used with it. The key lives in Certum's HSM and is reachable only through
  **SimplySign Desktop**, which mounts it as a *virtual smart card*: once a
  session is open the certificate appears in Cert:\CurrentUser\My and signtool
  signs with it exactly as it would with a physical token.

  Certum publishes no API and no command-line login for SimplySign Desktop, so
  opening that session without a human means driving the GUI. This script:

    1. installs SimplySign Desktop if it isn't already present,
    2. derives the current TOTP from the enrolment secret,
    3. launches the app and types the credentials into it via SendKeys,
    4. polls Cert:\CurrentUser\My until the cloud certificate shows up,
    5. writes its thumbprint to $GITHUB_ENV as WINDOWS_CERT_SHA1.

  Step 3 is the fragile part and there is no supported alternative — see
  docs/release-signing.md. Treat this as best-effort.

  By default failures warn and return for local experimentation. Pass -Required
  (the tagged-release workflow does) to terminate when the session cannot be
  opened, preventing an unsigned release fallback.

  Environment:

    SIMPLYSIGN_USER          SimplySign account ID / e-mail            (required)
    SIMPLYSIGN_TOTP_SECRET   base32 TOTP secret, or the whole          (required)
                             otpauth:// URI from the enrolment QR code
    SIMPLYSIGN_TIMEOUT_SEC   seconds to wait for the card to mount     (optional,
                             default 180)

  SIMPLYSIGN_TOTP_SECRET is the *second factor* for the signing account. Putting
  it in CI necessarily collapses 2FA to 1FA for anyone holding repo secrets.
  That is inherent to unattended signing, not something this script introduces,
  but it is worth knowing before you configure it.

.EXAMPLE
  ./dist/simplysign-login.ps1
#>
[CmdletBinding()]
param([switch]$Required)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Write-Warn([string]$Message) { Write-Host "::warning::$Message" }
function Stop-OrWarn([string]$Message) {
    if ($Required) { throw $Message }
    Write-Warn $Message
}

if ([string]::IsNullOrWhiteSpace($env:SIMPLYSIGN_USER) -or
    [string]::IsNullOrWhiteSpace($env:SIMPLYSIGN_TOTP_SECRET)) {
    Stop-OrWarn "SIMPLYSIGN_USER / SIMPLYSIGN_TOTP_SECRET are not both set."
    exit 0
}

$timeoutSec = 180
if (-not [string]::IsNullOrWhiteSpace($env:SIMPLYSIGN_TIMEOUT_SEC)) {
    [int]::TryParse($env:SIMPLYSIGN_TIMEOUT_SEC, [ref]$timeoutSec) | Out-Null
}

# --- TOTP ------------------------------------------------------------------
# The enrolment QR code is a standard otpauth:// URI, so accept either the URI
# (what you get by revealing the QR in a password manager) or the bare base32
# secret. Pasting the whole URI is the easier thing to do correctly.
function Get-Base32Secret([string]$Value) {
    $v = $Value.Trim()
    if ($v -match '^otpauth://') {
        # secret=... is required by the spec; other params (issuer, digits) are
        # ignored here because Certum uses the SHA1/6-digit/30s defaults.
        if ($v -match '[?&]secret=([^&]+)') { return $Matches[1] }
        throw "otpauth:// URI has no secret= parameter"
    }
    return $v
}

function ConvertFrom-Base32([string]$Value) {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
    $clean = ($Value -replace '[=\s-]', '').ToUpperInvariant()
    if ($clean.Length -eq 0) { throw "TOTP secret is empty" }

    $bits = New-Object System.Text.StringBuilder
    foreach ($ch in $clean.ToCharArray()) {
        $idx = $alphabet.IndexOf($ch)
        if ($idx -lt 0) { throw "TOTP secret is not valid base32 (bad character '$ch')" }
        [void]$bits.Append([Convert]::ToString($idx, 2).PadLeft(5, '0'))
    }

    # Base32 packs 5 bits per character, so the tail is padding unless the total
    # lands on a byte boundary; drop whatever doesn't fill a full byte.
    $s = $bits.ToString()
    $bytes = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i + 8 -le $s.Length; $i += 8) {
        $bytes.Add([Convert]::ToByte($s.Substring($i, 8), 2))
    }
    return $bytes.ToArray()
}

function Get-Totp([byte[]]$Secret, [int]$Digits = 6, [int]$Period = 30) {
    # RFC 6238 with the defaults Certum uses (HMAC-SHA1, 6 digits, 30s window).
    $counter = [BitConverter]::GetBytes([long][Math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / $Period))
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($counter) }

    $hmac = [System.Security.Cryptography.HMACSHA1]::new($Secret)
    try { $hash = $hmac.ComputeHash($counter) } finally { $hmac.Dispose() }

    $offset = $hash[$hash.Length - 1] -band 0x0F
    $binary = ((($hash[$offset] -band 0x7F) -shl 24) -bor
               (($hash[$offset + 1] -band 0xFF) -shl 16) -bor
               (($hash[$offset + 2] -band 0xFF) -shl 8) -bor
                ($hash[$offset + 3] -band 0xFF))
    return ($binary % [int][Math]::Pow(10, $Digits)).ToString().PadLeft($Digits, '0')
}

# --- SimplySign Desktop ----------------------------------------------------
function Find-SimplySign {
    $roots = @(
        "${env:ProgramFiles(x86)}\Certum",
        "$env:ProgramFiles\Certum",
        "${env:ProgramFiles(x86)}\proCertum SmartSign",
        "$env:ProgramFiles\proCertum SmartSign"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        $exe = Get-ChildItem -Path $root -Recurse -Filter 'SimplySign*.exe' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}

function Install-SimplySign {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "Installing SimplySign Desktop via winget..."
        & $winget.Source install --id Certum.SmartSignSimplySignDesktop --exact --silent `
            --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -eq 0) { return }
        Write-Warn "winget install returned $LASTEXITCODE; trying Certum's pinned MSI."
    }

    # GitHub's windows-2022 image intentionally has no Microsoft Store and no
    # winget. Certum publishes the same 64-bit installer directly; pin its hash
    # so a mutable download URL can never silently change release signing code.
    $version = '9.4.4.92'
    $uri = "https://files.certum.eu/software/SimplySignDesktop/Windows/$version/SimplySignDesktop-$version-64-bit-en.msi"
    $expectedSha256 = '8ec420fc27798b86078b7bd02fe7152097e1b3005bab51820eaca8e57df84da3'
    $msi = Join-Path $env:RUNNER_TEMP "SimplySignDesktop-$version-64-bit-en.msi"
    Write-Host "Downloading SimplySign Desktop $version from Certum..."
    Invoke-WebRequest -Uri $uri -OutFile $msi -UseBasicParsing
    $actualSha256 = (Get-FileHash -Path $msi -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $expectedSha256) {
        throw "SimplySign Desktop MSI checksum mismatch (got $actualSha256)."
    }
    $signature = Get-AuthenticodeSignature -FilePath $msi
    if ($signature.Status -ne 'Valid') {
        throw "SimplySign Desktop MSI Authenticode signature is $($signature.Status)."
    }
    $process = Start-Process msiexec.exe -ArgumentList @('/i', $msi, '/qn', '/norestart') -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "SimplySign Desktop MSI install returned $($process.ExitCode)."
    }
}

# Certificates the cloud card is about to add. Diffing against this is more
# reliable than matching on subject: the OSS certificate's subject is issued to
# an individual ("Open Source Developer, <name>") and we'd rather not hardcode
# a person's name in the repo.
function Get-CodeSigningCerts {
    Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
        Where-Object {
            $_.HasPrivateKey -and
            $_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.3'
        }
}

try {
    $before = @(Get-CodeSigningCerts | Select-Object -ExpandProperty Thumbprint)
    Write-Host "Code-signing certificates present before login: $($before.Count)"

    $exe = Find-SimplySign
    if (-not $exe) {
        Install-SimplySign
        $exe = Find-SimplySign
    }
    if (-not $exe) {
        Stop-OrWarn "SimplySign Desktop could not be found or installed."
        exit 0
    }
    Write-Host "Using SimplySign Desktop: $exe"

    $otp = Get-Totp (ConvertFrom-Base32 (Get-Base32Secret $env:SIMPLYSIGN_TOTP_SECRET))
    Write-Host "Generated a $($otp.Length)-digit TOTP."   # never log the value

    # `/autologin` is SimplySign Desktop's one-shot login-dialog mode. Starting
    # the executable without it only creates a tray icon, leaving no window for
    # CI to activate (and previously causing SendKeys to target the runner's
    # foreground window instead).
    Start-Process -FilePath $exe -ArgumentList '/autologin' | Out-Null

    # There is no supported way to script this. AppActivate + SendKeys against
    # the login dialog is what the community does; it depends on the runner
    # having an interactive desktop and on Certum not reshuffling the tab order.
    # If it breaks, strict release mode fails before any artifact is packaged.
    $shell = New-Object -ComObject WScript.Shell

    $windowDeadline = (Get-Date).AddSeconds(60)
    $proc = $null
    while ((Get-Date) -lt $windowDeadline) {
        $proc = Get-Process -Name 'SimplySign*' -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($proc) { break }
        Start-Sleep -Seconds 2
    }
    if (-not $proc) {
        Stop-OrWarn "SimplySign /autologin did not open a login window within 60s."
        exit 0
    }
    $shell.AppActivate($proc.Id) | Out-Null
    Start-Sleep -Seconds 2

    # SendKeys treats these as control characters, so anything appearing in an
    # account ID has to be escaped by wrapping it in braces.
    $user = $env:SIMPLYSIGN_USER -replace '([+^%~(){}])', '{$1}'
    $shell.SendKeys($user)
    Start-Sleep -Milliseconds 500
    $shell.SendKeys('{TAB}')
    Start-Sleep -Milliseconds 500
    $shell.SendKeys($otp)
    Start-Sleep -Milliseconds 500
    $shell.SendKeys('{ENTER}')

    Write-Host "Credentials submitted; waiting up to ${timeoutSec}s for the virtual card to mount..."

    $deadline = (Get-Date).AddSeconds($timeoutSec)
    $found = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $found = Get-CodeSigningCerts | Where-Object { $before -notcontains $_.Thumbprint } | Select-Object -First 1
        if ($found) { break }
    }

    if (-not $found) {
        Stop-OrWarn "SimplySign session did not produce a code-signing certificate within ${timeoutSec}s."
        exit 0
    }

    Write-Host "Cloud certificate mounted: $($found.Subject)"
    Write-Host "  expires: $($found.NotAfter.ToString('yyyy-MM-dd'))"

    # Hand the thumbprint to the signing steps. It is not a secret (it's derived
    # from the public certificate) and keeping it out of the repo secrets means
    # renewals don't need a secret rotation.
    if ($env:GITHUB_ENV) {
        "WINDOWS_CERT_SHA1=$($found.Thumbprint)" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
        Write-Host "Exported WINDOWS_CERT_SHA1 for subsequent steps."
    } else {
        Write-Host "GITHUB_ENV is unset (running locally); export WINDOWS_CERT_SHA1=$($found.Thumbprint) yourself."
    }
}
catch {
    if ($Required) { throw }
    Write-Warn "SimplySign login failed: $($_.Exception.Message)"
    exit 0
}
