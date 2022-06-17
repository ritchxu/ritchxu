# This rebuilds the contents of this package.
# This must be run from Developer Powershell for VS 2019 prompt.
# FUTURE: switch to official releases once they exist, instead of compilng from scratch.

#Requires -Version 5.1 # Shipped w/ Windows 10 1607 and Windows Server 2016
param(
    [Parameter(Mandatory=$false)][String]$AzureRelayBridgeRepo = 'AzureRelayBridge'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'

# Exit if last exit code is non-zero
function CheckExitCode {
    if ($LastExitCode -ne 0) {
        throw "exit code was $LASTEXITCODE"
    }
}

function Patch($Path, $Pattern, $Replace) {
    # Get absolute path b/c current dir for PowerShell isn't the same as .NET
    $Path = Resolve-Path $Path

    $old = [System.IO.File]::ReadAllText($Path)
    $new = $old -replace $pattern, $replace
    if ($old -eq $new) {
        throw "No match for '$pattern' in $Path"
    }
    # UTF-8 w/o BOM: https://docs.microsoft.com/en-us/dotnet/api/system.io.file.writealltext?view=netframework-4.5#System_IO_File_WriteAllText_System_String_System_String_
    [System.IO.File]::WriteAllText($Path, $new)
}

$version = [System.IO.Path]::GetFileName($PSScriptRoot)
$null = $version -match '(?<=-).*'
$versionSuffix = $Matches[0]
$commitId = '56b7f3b04718e253d416271f277a41280cfb948b'

git clone --no-checkout https://github.com/Azure/azure-relay-bridge $AzureRelayBridgeRepo
CheckExitCode

git -C $AzureRelayBridgeRepo checkout $commitId
CheckExitCode

# package-all.cmd must be run from the folder it's in, as of commit:
# 90d1b45 (origin/master, origin/HEAD) Fix typo in RelayBridgeService.cs (#7)
Push-Location $AzureRelayBridgeRepo

    # From https://github.com/Azure/azure-relay-bridge/pull/9
    # Add `--runtime win10-x64` to `dotnet test` to fix this error:
    # > NETSDK1031: It is not supported to build or publish a self-contained application without specifying
    # > a RuntimeIdentifier.  Please either specify a RuntimeIdentifier or set SelfContained to false.
    Patch -Path package-all.cmd -Pattern 'dotnet test %\*' -Replace 'dotnet test --runtime win10-x64 %*'

    # Modify version so we can differentiate between unofficial builds
    Patch -Path version.props -Pattern '<VersionSuffix>rtm</VersionSuffix>' -Replace "<VersionSuffix>$versionSuffix</VersionSuffix>"

    # From https://github.com/Azure/azure-relay-bridge/pull/23
    # Bump Packaging.Targets to get fix in https://github.com/qmfrederik/dotnet-packaging/commit/04d565670e764e36c73b61be1ed9aacb13031031: Bump libicu dependency for Ubuntu 20.04
    Patch -Path build\dependencies.props -Pattern '<PackagingTargetsPackageVersion>0.1.129</PackagingTargetsPackageVersion>' -Replace "<PackagingTargetsPackageVersion>0.1.189</PackagingTargetsPackageVersion>"

    # From https://github.com/Azure/azure-relay-bridge/pull/23
    # Remove unneeded dependencies already provided by Packaging.Targets:
    # https://github.com/qmfrederik/dotnet-packaging/blob/6ef34e121b683721f53506e530311c89b879a89d/Packaging.Targets/build/Packaging.Targets.targets
    Patch -Path src\azbridge\azbridge.csproj -Pattern '<DebDependency.+?/>' -Replace ''

    .\package-all.cmd
    CheckExitCode
Pop-Location

Copy-Item `
    -LiteralPath @(
        (Join-Path $AzureRelayBridgeRepo "artifacts\build\net462\azbridge_installer.$version.win10-x64.msi"),
        (Join-Path $AzureRelayBridgeRepo "artifacts\build\netcoreapp3.0\azbridge.$version.ubuntu.18.04-x64.deb")
    ) `
    -Destination $PSScriptRoot

@"
<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="12.0" DefaultTargets="Package" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <Import Project="`$([MSBuild]::GetDirectoryNameOfFileAbove(`$(MSBuildProjectDirectory), Static.Settings.targets))\Static.Settings.targets" />
  <ItemGroup>
    <Content Include="azbridge.$version.ubuntu.18.04-x64.deb"/>
    <Content Include="azbridge_installer.$version.win10-x64.msi"/>
  </ItemGroup>
  <Import Project="`$(BuildPath)\Static.targets" />
</Project>
"@ | Set-Content (Join-Path $PSScriptRoot Mseng.AzureRelayBridge.extproj) -Encoding ASCII