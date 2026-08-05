<#
.SYNOPSIS
  RFC 6238 TOTP generation from a base32 (or otpauth:// URI) secret.

.DESCRIPTION
  Pulled out of dist/simplysign-login.ps1 so the pure, deterministic parts of
  that script (parsing, base32 decoding, HOTP/TOTP math) can be dot-sourced
  and unit-tested without touching the GUI-automation half, which needs a
  real SimplySign install and an interactive desktop to run at all.

  Covered by dist/lib/totp.Tests.ps1 against the RFC 6238 Appendix B SHA-1
  test vectors.
#>

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

function Get-Totp {
    param(
        [Parameter(Mandatory = $true)] [byte[]]$Secret,
        [int]$Digits = 6,
        [int]$Period = 30,
        # Injectable for tests; production callers rely on the default.
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
    )
    # RFC 6238 with the defaults Certum uses (HMAC-SHA1, 6 digits, 30s window).
    $counter = [BitConverter]::GetBytes([long][Math]::Floor($Now.ToUnixTimeSeconds() / $Period))
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
