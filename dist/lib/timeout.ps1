<#
.SYNOPSIS
  Resolves a "seconds" environment override to a positive integer, falling
  back to a default on anything unusable.

.DESCRIPTION
  Pulled out of dist/simplysign-login.ps1 so this logic can be unit-tested
  independently of the GUI automation, which needs a real SimplySign install
  and an interactive desktop to run at all.

  [int]::TryParse's `ref` parameter is reset to 0 on failure rather than left
  unchanged, so a naive `if (TryParse(...)) { use it }` accepts 0 as if it
  were a deliberately-parsed value. Worse, an explicit "0" (or a negative
  number) parses successfully but is exactly as broken as the unparsable
  case: a deadline loop keyed off it runs zero iterations. Both must fall
  back to the default.

  Covered by dist/lib/timeout.Tests.ps1.
#>

function Resolve-TimeoutSeconds {
    param(
        [string]$Value,
        [Parameter(Mandatory = $true)] [int]$Default
    )
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [PSCustomObject]@{ Seconds = $Default; UsedDefault = $false }
    }
    $parsed = 0
    if ([int]::TryParse($Value, [ref]$parsed) -and $parsed -gt 0) {
        return [PSCustomObject]@{ Seconds = $parsed; UsedDefault = $false }
    }
    return [PSCustomObject]@{ Seconds = $Default; UsedDefault = $true }
}
