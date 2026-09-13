$ErrorActionPreference = 'Stop'
# Target the exact Inno AppId, never a fuzzy publisher/name match.
$uninstallKey = '{B8F3A2D1-7C4E-4A9B-8D5F-1E6C3B2A0F47}_is1'
$entry = Get-UninstallRegistryKey -SoftwareName 'Daccord*' |
    Where-Object { $_.PSChildName -eq $uninstallKey }
if (@($entry).Count -gt 1) { throw 'Multiple Daccord installs found; uninstall the intended scope manually.' }
if ($entry) {
    $uninstaller = Join-Path $entry.InstallLocation 'unins000.exe'
    if (-not (Test-Path -LiteralPath $uninstaller)) { throw 'Daccord uninstaller was not found.' }
    Uninstall-ChocolateyPackage -PackageName 'daccord' -FileType 'exe' `
        -File $uninstaller -SilentArgs '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-' `
        -ValidExitCodes @(0)
}
# The application's Documents/daccord/data directory is intentionally retained.
