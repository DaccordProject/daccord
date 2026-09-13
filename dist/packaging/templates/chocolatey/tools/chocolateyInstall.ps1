# Review only until a release supports the package-manager installer switch.
$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Daccord requires 64-bit Windows.'
}
$packageArgs = @{
    packageName = 'daccord'
    fileType = 'exe'
    softwareName = 'Daccord*'
    url64bit = '@@WINDOWS_INSTALLER_URL@@'
    checksum64 = '@@WINDOWS_INSTALLER_SHA256@@'
    checksumType64 = 'sha256'
    silentArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS /PACKAGE_MANAGER=chocolatey'
    validExitCodes = @(0)
}
Install-ChocolateyPackage @packageArgs
