<#
.SYNOPSIS
  Pester tests for dist/lib/totp.ps1, the TOTP math dist/simplysign-login.ps1
  depends on to authenticate against Certum SimplySign.

.DESCRIPTION
  The GUI-automation half of simplysign-login.ps1 can't be exercised in CI (no
  SimplySign install, no interactive desktop), but the TOTP/base32 code it
  depends on is pure and deterministic, so it gets real coverage here instead
  of only the one-off manual check described in the PR that introduced it.

  Run with: Invoke-Pester dist/lib/totp.Tests.ps1
#>

BeforeAll {
    . "$PSScriptRoot/totp.ps1"
}

Describe 'ConvertFrom-Base32' {
    It 'round-trips RFC 4648 test vectors' {
        # RFC 4648 §10.
        [System.Text.Encoding]::ASCII.GetBytes('f') | Should -Be (ConvertFrom-Base32 'MY======')
        [System.Text.Encoding]::ASCII.GetBytes('foobar') | Should -Be (ConvertFrom-Base32 'MZXW6YTBOI======')
    }

    It 'is case-insensitive and tolerates padding/whitespace/hyphens' {
        $expected = ConvertFrom-Base32 'MZXW6YTBOI======'
        (ConvertFrom-Base32 'mzxw6ytboi======') | Should -Be $expected
        (ConvertFrom-Base32 " mz-xw6y-tboi `n") | Should -Be $expected
    }

    It 'throws on an invalid character' {
        { ConvertFrom-Base32 '01239' } | Should -Throw
    }

    It 'throws on an empty secret' {
        { ConvertFrom-Base32 '' } | Should -Throw
    }
}

Describe 'Get-Base32Secret' {
    It 'passes a bare base32 secret through unchanged' {
        Get-Base32Secret 'JBSWY3DPEHPK3PXP' | Should -Be 'JBSWY3DPEHPK3PXP'
    }

    It 'extracts secret= from an otpauth:// URI' {
        $uri = 'otpauth://totp/Certum:me@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Certum&digits=6'
        Get-Base32Secret $uri | Should -Be 'JBSWY3DPEHPK3PXP'
    }

    It 'throws when an otpauth:// URI has no secret parameter' {
        { Get-Base32Secret 'otpauth://totp/Certum:me@example.com?issuer=Certum' } | Should -Throw
    }
}

Describe 'Get-Totp' {
    # RFC 6238 Appendix B, SHA-1 mode: 20-byte ASCII secret "12345678901234567890",
    # 8-digit codes, 30s period. These are the canonical vectors used to
    # validate any TOTP implementation.
    BeforeAll {
        $script:secret = [System.Text.Encoding]::ASCII.GetBytes('12345678901234567890')
    }

    $cases = @(
        @{ UnixSeconds = 59;          Expected = '94287082' }
        @{ UnixSeconds = 1111111109;  Expected = '07081804' }
        @{ UnixSeconds = 1111111111;  Expected = '14050471' }
        @{ UnixSeconds = 1234567890;  Expected = '89005924' }
        @{ UnixSeconds = 2000000000;  Expected = '69279037' }
    )

    It 'matches the RFC 6238 SHA-1 vector at T=<UnixSeconds>' -TestCases $cases {
        param($UnixSeconds, $Expected)
        $now = [DateTimeOffset]::FromUnixTimeSeconds($UnixSeconds)
        Get-Totp -Secret $script:secret -Digits 8 -Period 30 -Now $now | Should -Be $Expected
    }

    It 'defaults to 6 digits, 30s period' {
        $now = [DateTimeOffset]::FromUnixTimeSeconds(59)
        (Get-Totp -Secret $script:secret -Now $now).Length | Should -Be 6
        # A 6-digit code is the low-order 6 digits of the 8-digit vector.
        Get-Totp -Secret $script:secret -Now $now | Should -Be '287082'
    }
}
