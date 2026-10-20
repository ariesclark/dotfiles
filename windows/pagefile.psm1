Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'volumes.psm1')

function Get-PagefileDeclaration {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Volumes,
		[Parameter(Mandatory)] [long] $MemoryBytes
	)

	$declared = @($Volumes.PSObject.Properties | Where-Object { $_.Value.PSObject.Properties['pagefile'] })
	if ($declared.Count -gt 1) {
		throw "A pagefile can be on one volume only, not $(($declared.Name | ForEach-Object { "$($_.ToUpperInvariant()):" }) -join ', ')."
	}
	if (-not $declared.Count) {
		return
	}
	$size = $declared[0].Value.pagefile
	$sizeGB = if ($size -ieq 'memory') { [int][math]::Ceiling($MemoryBytes / 1GB) } else { ConvertFrom-Size $size }
	if ($null -eq $sizeGB) {
		throw "Can't read the pagefile size '$size'; use memory, or a number of GB like 16GB."
	}
	[pscustomobject]@{ letter = $declared[0].Name.ToUpperInvariant(); sizeGB = $sizeGB }
}

function Get-PagefileChange {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Desired,
		[Parameter(Mandatory)] [bool] $Automatic,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Settings
	)

	$name = "$($Desired.letter):\pagefile.sys"
	$sizeMB = [int]$Desired.sizeGB * 1024
	if ($Automatic) {
		[pscustomobject]@{ Action = 'DisableAutomatic'; Name = $null; SizeMB = $null }
	}
	foreach ($setting in $Settings | Where-Object Name -ne $name) {
		[pscustomobject]@{ Action = 'Remove'; Name = $setting.Name; SizeMB = $null }
	}
	$current = $Settings | Where-Object Name -eq $name
	if (-not $current -or $current.InitialSize -ne $sizeMB -or $current.MaximumSize -ne $sizeMB) {
		[pscustomobject]@{ Action = 'Set'; Name = $name; SizeMB = $sizeMB }
	}
}

function Sync-Pagefile {
	[CmdletBinding()]
	param([Parameter(Mandatory)] [object] $Pagefile)

	$automatic = (Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile
	$settings = @(Get-CimInstance Win32_PageFileSetting)
	$changes = @(Get-PagefileChange -Desired $Pagefile -Automatic $automatic -Settings $settings)
	if (-not $changes.Count) {
		return
	}
	$commands = foreach ($change in $changes) {
		switch ($change.Action) {
			'DisableAutomatic' { "Get-CimInstance Win32_ComputerSystem | Set-CimInstance -Property @{ AutomaticManagedPagefile = `$false }" }
			'Remove' { "Get-CimInstance Win32_PageFileSetting | Where-Object Name -eq '$($change.Name)' | Remove-CimInstance" }
			'Set' {
				"`$setting = Get-CimInstance Win32_PageFileSetting | Where-Object Name -eq '$($change.Name)'; " +
				"if (-not `$setting) { `$setting = New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = '$($change.Name)' } }; " +
				"`$setting | Set-CimInstance -Property @{ InitialSize = [uint32]$($change.SizeMB); MaximumSize = [uint32]$($change.SizeMB) }"
			}
		}
	}
	Write-Host "Pagefile: $($Pagefile.letter): fixed at $($Pagefile.sizeGB) GB, nowhere else (admin prompt; takes effect after a restart)."
	$process = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList '-NoProfile', '-Command', "`$ErrorActionPreference = 'Stop'; $($commands -join '; ')"
	if ($process.ExitCode -ne 0) {
		throw 'Could not set the pagefile.'
	}
}

Export-ModuleMember -Function Get-PagefileDeclaration, Get-PagefileChange, Sync-Pagefile
