<#
.SYNOPSIS
  Pester tests for dist/lib/timeout.ps1, the SIMPLYSIGN_TIMEOUT_SEC parsing
  dist/simplysign-login.ps1 depends on.

.DESCRIPTION
  Regression coverage for the bug fixed in this PR (TryParse silently
  resetting the timeout to 0 on a malformed value) and for the same failure
  mode via a value that parses fine but is still unusable (0 or negative).

  Run with: Invoke-Pester dist/lib/timeout.Tests.ps1
#>

BeforeAll {
    . "$PSScriptRoot/timeout.ps1"
}

Describe 'Resolve-TimeoutSeconds' {
    It 'uses the default when the value is unset or blank' {
        (Resolve-TimeoutSeconds -Value $null -Default 180).Seconds | Should -Be 180
        (Resolve-TimeoutSeconds -Value '' -Default 180).Seconds | Should -Be 180
        (Resolve-TimeoutSeconds -Value '   ' -Default 180).Seconds | Should -Be 180
        (Resolve-TimeoutSeconds -Value '' -Default 180).UsedDefault | Should -BeFalse
    }

    It 'parses a valid positive integer' {
        $result = Resolve-TimeoutSeconds -Value '300' -Default 180
        $result.Seconds | Should -Be 300
        $result.UsedDefault | Should -BeFalse
    }

    It 'falls back to the default on a non-numeric value' {
        $result = Resolve-TimeoutSeconds -Value 'not-a-number' -Default 180
        $result.Seconds | Should -Be 180
        $result.UsedDefault | Should -BeTrue
    }

    It 'falls back to the default on zero, matching the malformed-value case rather than reintroducing it' {
        $result = Resolve-TimeoutSeconds -Value '0' -Default 180
        $result.Seconds | Should -Be 180
        $result.UsedDefault | Should -BeTrue
    }

    It 'falls back to the default on a negative value' {
        $result = Resolve-TimeoutSeconds -Value '-30' -Default 180
        $result.Seconds | Should -Be 180
        $result.UsedDefault | Should -BeTrue
    }
}
