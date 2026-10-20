Set-StrictMode -Version Latest

foreach ($module in 'scoop', 'winget', 'steam') {
	Import-Module (Join-Path $PSScriptRoot "$module.psm1") -Force
}

# A list-valued key of a YAML object, or nothing when the key is absent.
function Get-ListProperty {
	param([object] $Object, [string] $Key)

	$property = $Object.PSObject.Properties[$Key]
	if ($property) {
		@($property.Value)
	}
}

function Resolve-Group {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Groups,
		[Parameter(Mandatory)] [string[]] $Selected
	)

	$ordered = [System.Collections.Generic.List[string]]::new()
	$visiting = [System.Collections.Generic.List[string]]::new()

	function Visit([string] $Name) {
		if ($ordered.Contains($Name)) {
			return
		}
		if ($visiting.Contains($Name)) {
			$start = $visiting.IndexOf($Name)
			$path = @($visiting.GetRange($start, $visiting.Count - $start)) + $Name
			throw "Group cycle: $($path -join ' -> ')"
		}
		$group = $Groups.PSObject.Properties[$Name]
		if (-not $group) {
			throw "Unknown group '$Name'."
		}
		$visiting.Add($Name)
		foreach ($required in (Get-ListProperty -Object $group.Value -Key 'needs')) {
			Visit $required
		}
		$visiting.Remove($Name) | Out-Null
		$ordered.Add($Name)
	}

	foreach ($name in $Selected) {
		Visit $name
	}
	$ordered.ToArray()
}

function Get-PackageSet {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Groups,
		[Parameter(Mandatory)] [string[]] $Names
	)

	$set = [ordered]@{ scoop = @(); winget = @(); msstore = @(); steam = @() }
	foreach ($app in @($Names | ForEach-Object { Get-ListProperty -Object $Groups.PSObject.Properties[$_].Value -Key 'apps' })) {
		$source, $id = $app -split ':', 2
		if (-not $id -or -not $set.Contains($source)) {
			throw "App '$app' must be named scoop:bucket/app, winget:id, msstore:id or steam:appid."
		}
		$set[$source] += $id
	}
	foreach ($source in @($set.Keys)) {
		$set[$source] = @($set[$source] | Sort-Object -Unique)
	}
	[pscustomobject]$set
}

# The install options apps.yaml declares for one source's apps, keyed by package id:
# Location (winget --location), InstallerType (winget --installer-type), and FixedLocation (an installer that
# can't choose a folder, so it's given none).
function Get-InstallOption {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Apps,
		[Parameter(Mandatory)] [string] $Source
	)

	$options = @{}
	foreach ($app in $Apps.PSObject.Properties) {
		$appSource, $id = $app.Name -split ':', 2
		if ($appSource -ne $Source) {
			continue
		}
		$value = { param($key) $property = $app.Value.PSObject.Properties[$key]; if ($property) { $property.Value } }
		$option = [pscustomobject]@{ Location = (& $value 'location'); InstallerType = (& $value 'installerType'); FixedLocation = [bool](& $value 'fixedLocation') }
		if ($option.Location -or $option.InstallerType -or $option.FixedLocation) {
			$options[$id] = $option
		}
	}
	$options
}

# Where a winget app installs: what apps.yaml declares, else its own folder under the root (layout.winget).
# MSIX installs and Store apps get none: Windows keeps them in C:\Program Files\WindowsApps. Neither do apps whose
# installer has a fixed folder (fixedLocation); a --location it can't take would only make winget fail.
function Resolve-InstallLocation {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [string] $Id,
		[Parameter(Mandatory)] [string] $Source,
		[AllowNull()] [object] $Option,
		[Parameter(Mandatory)] [string] $Root
	)

	$fixed = $Option -and $Option.PSObject.Properties['FixedLocation'] -and $Option.FixedLocation
	if ($Source -ne 'winget' -or ($Option -and $Option.InstallerType -eq 'msix') -or $fixed) {
		return
	}
	if ($Option -and $Option.Location) {
		return $Option.Location
	}
	Join-Path $Root $Id
}

function Get-PackageChange {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Desired,
		[AllowNull()] [object] $Previous
	)

	$install = [ordered]@{}
	$uninstall = [ordered]@{}
	foreach ($kind in 'scoop', 'winget', 'msstore', 'steam') {
		$wanted = @($Desired.$kind | Where-Object { $_ })
		$applied = if ($Previous -and $Previous.PSObject.Properties[$kind]) { @($Previous.$kind | Where-Object { $_ }) } else { @() }
		$install[$kind] = $wanted
		$uninstall[$kind] = @($applied | Where-Object { $_ -notin $wanted })
	}
	[pscustomobject]@{ install = [pscustomobject]$install; uninstall = [pscustomobject]$uninstall }
}

function Sync-Package {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Groups,
		[Parameter(Mandatory)] [object] $Apps,
		[Parameter(Mandatory)] [string[]] $Selected,
		[Parameter(Mandatory)] [object] $Layout
	)

	$names = Resolve-Group -Groups $Groups -Selected $Selected
	$desired = Get-PackageSet -Groups $Groups -Names $names
	$previous = if (Test-Path -LiteralPath $Layout.state) { Get-Content -LiteralPath $Layout.state -Raw | ConvertFrom-Json } else { $null }
	$change = Get-PackageChange -Desired $desired -Previous $previous

	Install-Scoop -Root $Layout.scoop
	$declared = Get-InstallOption -Apps $Apps -Source winget
	$wingetOptions = @{}
	foreach ($id in $change.install.winget) {
		$wingetOptions[$id] = [pscustomobject]@{
			Location = Resolve-InstallLocation -Id $id -Source winget -Option $declared[$id] -Root $Layout.winget
			InstallerType = if ($declared[$id]) { $declared[$id].InstallerType } else { $null }
		}
	}
	$failures = @(
		Invoke-ScoopChange -Install $change.install.scoop -Uninstall $change.uninstall.scoop
		Invoke-WingetChange -Source winget -Install $change.install.winget -Uninstall $change.uninstall.winget -Options $wingetOptions
		Invoke-WingetChange -Source msstore -Install $change.install.msstore -Uninstall $change.uninstall.msstore
	)
	if ($failures.Count -gt 0) {
		throw "These packages did not install: $($failures -join ', '). Nothing was recorded; fix them and apply again."
	}
	Invoke-SteamChange -Steam (Join-Path $Layout.scoop 'apps\steam\current') -Install $change.install.steam -Uninstall $change.uninstall.steam

	New-Item -ItemType Directory -Force -Path (Split-Path $Layout.state) | Out-Null
	$desired | ConvertTo-Json | Set-Content -LiteralPath $Layout.state -Encoding utf8
}

Export-ModuleMember -Function Resolve-Group, Get-PackageSet, Get-InstallOption, Resolve-InstallLocation, Get-PackageChange, Sync-Package
