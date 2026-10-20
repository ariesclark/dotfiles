Set-StrictMode -Version Latest

function Get-SteamLibrary {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [string] $Steam,
		[AllowNull()] [string] $Folders
	)

	# not Join-Path: it fails when a library's drive is unplugged
	$libraries = @([System.IO.Path]::Combine($Steam, 'steamapps'))
	if ($Folders) {
		foreach ($match in [regex]::Matches($Folders, '"path"\s+"([^"]+)"')) {
			$libraries += [System.IO.Path]::Combine(($match.Groups[1].Value -replace '\\\\', '\'), 'steamapps')
		}
	}
	$libraries | Select-Object -Unique
}

function Get-SteamInstalled {
	[CmdletBinding()]
	param([Parameter(Mandatory)] [string[]] $Libraries)

	foreach ($library in $Libraries) {
		Get-ChildItem -LiteralPath $library -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue |
			ForEach-Object { $_.BaseName -replace '^appmanifest_', '' }
	}
}

# Steam has no silent install: this opens Steam's own dialog for each change, and the download runs in Steam.
function Invoke-SteamChange {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [string] $Steam,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Install,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Uninstall
	)

	if (-not ($Install + $Uninstall)) {
		return
	}
	$steam = $Steam
	$executable = Join-Path $steam 'steam.exe'
	if (-not (Test-Path -LiteralPath $executable)) {
		throw 'steam: apps need Steam; add scoop:games/steam to a selected group.'
	}
	$folders = Join-Path $steam 'steamapps\libraryfolders.vdf'
	$text = if (Test-Path -LiteralPath $folders) { Get-Content -LiteralPath $folders -Raw } else { $null }
	$installed = @(Get-SteamInstalled -Libraries @(Get-SteamLibrary -Steam $steam -Folders $text))

	foreach ($id in $Uninstall) {
		if ($id -in $installed) {
			Write-Host "Steam: confirm uninstalling app $id in the Steam window."
			Start-Process -FilePath $executable -ArgumentList "steam://uninstall/$id"
		}
	}
	foreach ($id in $Install) {
		if ($id -notin $installed) {
			Write-Host "Steam: confirm installing app $id in the Steam window."
			Start-Process -FilePath $executable -ArgumentList "steam://install/$id"
		}
	}
}

Export-ModuleMember -Function Get-SteamLibrary, Get-SteamInstalled, Invoke-SteamChange
