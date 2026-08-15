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

  **Never fails the release.** Every failure path warns and exits 0 without
  setting WINDOWS_CERT_SHA1; sign-windows.ps1 then finds no credential and
  ships unsigned binaries, which is the same outcome as having no certificate
  at all.

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
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# Nothing here may sink a tagged release, so the whole body runs inside a
# try/catch that downgrades any error to a warning + exit 0.
function Write-Warn([string]$Message) { Write-Host "::warning::$Message" }

if ([string]::IsNullOrWhiteSpace($env:SIMPLYSIGN_USER) -or
    [string]::IsNullOrWhiteSpace($env:SIMPLYSIGN_TOTP_SECRET)) {
    Write-Warn "SIMPLYSIGN_USER / SIMPLYSIGN_TOTP_SECRET are not both set - skipping SimplySign login."
    exit 0
}

$timeoutSec = 180
if (-not [string]::IsNullOrWhiteSpace($env:SIMPLYSIGN_TIMEOUT_SEC)) {
    [int]::TryParse($env:SIMPLYSIGN_TIMEOUT_SEC, [ref]$timeoutSec) | Out-Null
}

# --- TOTP ------------------------------------------------------------------
# The enrolment QR code is a standard otpauth:// URI, so accept either the URI
# (what you get by revealing the QR in a password manager) or the bare base32
# secret. Pasting the whole URI is the easier thing to do correctly - and it is
# also the only form that carries the algorithm, because Certum do NOT use the
# RFC 6238 default: their code-signing enrolment URIs specify algorithm=SHA256.
# Signing with the wrong PRF produces six plausible-looking digits that Certum
# always rejects, so the parameters are read from the URI rather than assumed.
function Get-TotpParams([string]$Value) {
    $v = $Value.Trim()
    $params = @{ Secret = $v; Algorithm = 'SHA1'; Digits = 6; Period = 30 }

    if ($v -match '^otpauth://') {
        if ($v -notmatch '[?&]secret=([^&]+)') { throw "otpauth:// URI has no secret= parameter" }
        $params.Secret = $Matches[1]
        if ($v -match '[?&]algorithm=([^&]+)') { $params.Algorithm = $Matches[1].ToUpperInvariant() }
        if ($v -match '[?&]digits=(\d+)')      { $params.Digits    = [int]$Matches[1] }
        if ($v -match '[?&]period=(\d+)')      { $params.Period    = [int]$Matches[1] }
    }
    return $params
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

function Get-Totp([byte[]]$Secret, [string]$Algorithm = 'SHA1', [int]$Digits = 6, [int]$Period = 30) {
    # RFC 6238. The PRF comes from the enrolment URI - Certum's code-signing
    # accounts use SHA256, not the SHA1 default.
    $counter = [BitConverter]::GetBytes([long][Math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / $Period))
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($counter) }

    $hmac = switch ($Algorithm) {
        'SHA1'   { [System.Security.Cryptography.HMACSHA1]::new($Secret) }
        'SHA256' { [System.Security.Cryptography.HMACSHA256]::new($Secret) }
        'SHA512' { [System.Security.Cryptography.HMACSHA512]::new($Secret) }
        default  { throw "Unsupported TOTP algorithm '$Algorithm'" }
    }
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

# Pinned to a specific MSI rather than "latest": the URL is version-stamped, so
# there is no floating one to use, and pinning means the hash below can be
# checked. Both values are copied from Certum's own winget manifest
# (microsoft/winget-pkgs, manifests/c/Certum/SmartSignSimplySignDesktop). To
# bump, take the InstallerUrl + InstallerSha256 for the new version from there.
$script:SimplySignMsiUrl = 'https://files.certum.eu/software/SimplySignDesktop/Windows/9.4.4.92/SimplySignDesktop-9.4.4.92-64-bit-en.msi'
$script:SimplySignMsiSha256 = '8EC420FC27798B86078B7BD02FE7152097E1B3005BAB51820EACA8E57DF84DA3'

function Install-SimplySign {
    # winget looks like the obvious installer, and it is what this script used
    # to do, but it is NOT usable on the GitHub windows-latest image: winget is
    # provisioned per-user for an interactive desktop user and the runner
    # service account has no such install, so the call dies with "the term
    # 'winget' is not recognized". Use it when it happens to be there (a
    # self-hosted runner may well have it) and fall back to the MSI otherwise.
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing SimplySign Desktop via winget..."
        winget install --id Certum.SmartSignSimplySignDesktop --exact --silent `
            --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -eq 0) { return }
        Write-Warn "winget install returned $LASTEXITCODE; falling back to the MSI."
    }

    $msi = Join-Path $env:TEMP 'SimplySignDesktop.msi'
    Write-Host "Downloading $script:SimplySignMsiUrl"
    $ProgressPreference = 'SilentlyContinue'   # the progress bar is very slow over a CI pipe
    Invoke-WebRequest -Uri $script:SimplySignMsiUrl -OutFile $msi -UseBasicParsing

    # An unsigned installer for the tool that holds our signing key would be an
    # absurd link in the chain, so the download is pinned by hash.
    $actual = (Get-FileHash -Path $msi -Algorithm SHA256).Hash
    if ($actual -ne $script:SimplySignMsiSha256) {
        throw "SimplySign MSI hash mismatch: expected $script:SimplySignMsiSha256, got $actual"
    }
    Write-Host "MSI hash verified; installing silently..."

    $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/qn', '/norestart' -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        Write-Warn "msiexec returned $($p.ExitCode); continuing in case the app is already present."
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
        Write-Warn "SimplySign Desktop could not be found or installed - shipping UNSIGNED Windows binaries."
        exit 0
    }
    Write-Host "Using SimplySign Desktop: $exe"

    # Parse (and so validate) the enrolment URI before launching anything - a
    # malformed secret should fail here, not after a 20-second GUI dance.
    $totp = Get-TotpParams $env:SIMPLYSIGN_TOTP_SECRET

    Start-Process -FilePath $exe | Out-Null
    Start-Sleep -Seconds 25

    # A second launch is what actually produces the login dialog: SimplySign is
    # a tray application, so the first launch leaves every window hidden. It has
    # a single-instance path, and hitting it raises the dialog.
    Start-Process -FilePath $exe | Out-Null

    # Find that window by ENUMERATING top-level windows, not through
    # MainWindowHandle. MainWindowHandle is 0 for this app even when its login
    # dialog is on screen, and trusting it is the single reason v0.2.10-rc.2
    # reported "no interactive desktop" on a runner that demonstrably has one:
    # session 2, explorer running, 1024x768, and a visible WinForms dialog.
    Add-Type -Path (Join-Path $PSScriptRoot 'EnumWindows.cs')
    Add-Type -Path (Join-Path $PSScriptRoot 'CaptureWindow.cs') `
        -ReferencedAssemblies System.Drawing, System.Windows.Forms

    $hwnd = [IntPtr]::Zero
    $windowDeadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $windowDeadline) {
        $row = [WinEnum]::All() |
            Where-Object { $_ -match 'visible=True' -and $_ -match 'title=SimplySign Desktop' } |
            Select-Object -First 1
        if ($row) {
            $hwnd = [IntPtr][int]($row -replace '.*hwnd=(\d+).*', '$1')
            Write-Host "Login dialog found: $row"
            break
        }
        Start-Sleep -Seconds 5
    }

    if ($hwnd -eq [IntPtr]::Zero) {
        Write-Warn "No SimplySign login dialog appeared in 120s - shipping UNSIGNED Windows binaries."
        [WinEnum]::All() | ForEach-Object { Write-Host "  $_" }
        exit 0
    }

    # SwitchToThisWindow, not SetForegroundWindow: the latter is refused to a
    # background process and silently does nothing.
    [WinCapture]::Raise($hwnd)
    Start-Sleep -Seconds 2

    $shell = New-Object -ComObject WScript.Shell

    # Only now derive the code, and only from a window with enough validity left
    # to survive the ~2s of typing below. Generating it before the GUI wait -
    # which is what the obvious ordering does - can submit a code that expired
    # while the app was still painting, which looks exactly like a wrong secret.
    $elapsed = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() % $totp.Period
    if (($totp.Period - $elapsed) -lt 10) {
        $wait = $totp.Period - $elapsed
        Write-Host "TOTP window has ${wait}s left; waiting for the next one."
        Start-Sleep -Seconds ($wait + 1)
    }
    $otp = Get-Totp (ConvertFrom-Base32 $totp.Secret) $totp.Algorithm $totp.Digits $totp.Period
    # Log the parameters but never the value - a wrong algorithm is otherwise
    # indistinguishable from a wrong password in the failure log.
    Write-Host "Generated a $($otp.Length)-digit TOTP (HMAC-$($totp.Algorithm), $($totp.Period)s)."

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
        Write-Warn "SimplySign session did not produce a code-signing certificate within ${timeoutSec}s - shipping UNSIGNED Windows binaries."
        # Photograph the dialog: on Linux the equivalent capture was the only
        # thing that showed the login had actually succeeded and was merely
        # waiting on a confirmation panel.
        if ($env:RUNNER_TEMP) {
            $shot = Join-Path $env:RUNNER_TEMP 'simplysign-failure.png'
            Write-Host ([WinCapture]::Save($hwnd, $shot))
        }
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
    Write-Warn "SimplySign login failed: $($_.Exception.Message) - shipping UNSIGNED Windows binaries."
    exit 0
}
