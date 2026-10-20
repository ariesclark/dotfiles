Set-StrictMode -Version Latest

function Get-WingetInstallArgument {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [string] $Id,
		[Parameter(Mandatory)] [ValidateSet('winget', 'msstore')] [string] $Source,
		[string] $Location,
		[string] $InstallerType
	)

	$arguments = @('install', '--id', $Id, '--exact', '--source', $Source, '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
	if ($Location) {
		$arguments += '--location', $Location
	}
	if ($InstallerType) {
		$arguments += '--installer-type', $InstallerType
	}
	$arguments
}

function Test-WingetPackage {
	param([Parameter(Mandatory)] [string] $Id, [Parameter(Mandatory)] [string] $Source)

	winget list --id $Id --exact --source $Source --accept-source-agreements --disable-interactivity | Out-Null
	$LASTEXITCODE -eq 0
}

# Source is 'winget' or 'msstore': both go through winget, from different catalogs.
# Options maps a package id to its install options from apps.yaml (Location, InstallerType); without them,
# the installer picks where it goes (usually C:).
function Invoke-WingetChange {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [ValidateSet('winget', 'msstore')] [string] $Source,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Install,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Uninstall,
		[hashtable] $Options = @{}
	)

	foreach ($id in $Uninstall) {
		winget uninstall --id $id --exact --source $Source --silent --disable-interactivity | Out-Host
	}
	foreach ($id in $Install) {
		if (Test-WingetPackage -Id $id -Source $Source) {
			continue
		}
		$option = $Options[$id]
		$arguments = if ($option) { Get-WingetInstallArgument -Id $id -Source $Source -Location $option.Location -InstallerType $option.InstallerType } else { Get-WingetInstallArgument -Id $id -Source $Source }
		winget @arguments | Out-Host
		if ($LASTEXITCODE -ne 0) {
			"${Source}:$id"
		}
	}
}

Export-ModuleMember -Function Get-WingetInstallArgument, Test-WingetPackage, Invoke-WingetChange
