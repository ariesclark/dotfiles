Set-StrictMode -Version Latest

function Install-Scoop {
	[CmdletBinding()]
	param([Parameter(Mandatory)] [string] $Root)

	$env:SCOOP = $Root
	[Environment]::SetEnvironmentVariable('SCOOP', $Root, 'User')
	if (-not (Test-Path -LiteralPath (Join-Path $Root 'shims\scoop.ps1'))) {
		$installer = Join-Path $env:TEMP 'install-scoop.ps1'
		Invoke-RestMethod -Uri 'https://get.scoop.sh' -OutFile $installer
		& $installer -ScoopDir $Root
		Remove-Item -LiteralPath $installer
	}

	# After a Windows reset Scoop is still on E:, but the user PATH entry the installer made is gone.
	$shims = Join-Path $Root 'shims'
	$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
	if (($userPath -split ';') -notcontains $shims) {
		[Environment]::SetEnvironmentVariable('PATH', (@($shims) + @($userPath -split ';' | Where-Object { $_ }) -join ';'), 'User')
	}
	if (($env:PATH -split ';') -notcontains $shims) {
		$env:PATH = "$shims;$env:PATH"
	}
}

function Get-ScoopApp {
	[CmdletBinding()]
	param()

	scoop list 6>$null | Where-Object { "$($_.Info)" -notmatch 'failed' } | ForEach-Object { $_.Name }
}

function Get-ScoopFailure {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Desired,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Installed
	)

	foreach ($app in $Desired) {
		$name = ($app -split '/')[1]
		$entry = $Installed | Where-Object { $_.Name -eq $name } | Select-Object -First 1
		if (-not $entry -or "$($entry.Info)" -match 'failed') {
			$app
		}
	}
}

function Invoke-ScoopChange {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Install,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Uninstall
	)

	foreach ($app in $Uninstall) {
		scoop uninstall ($app -split '/')[1] | Out-Host
	}

	$listed = @(scoop list 6>$null)
	$installed = @($listed | Where-Object { "$($_.Info)" -notmatch 'failed' } | ForEach-Object { $_.Name })
	$broken = @($listed | Where-Object { "$($_.Info)" -match 'failed' } | ForEach-Object { $_.Name })
	$buckets = @(scoop bucket list 6>$null | ForEach-Object { $_.Name })
	foreach ($app in $Install) {
		$bucket, $name = $app -split '/'
		if ($name -in $installed) {
			continue
		}
		if ($bucket -notin $buckets) {
			scoop bucket add $bucket | Out-Host
			$buckets += $bucket
		}
		if ($name -in $broken) {
			scoop uninstall $name | Out-Host
		}
		scoop install $app | Out-Host
	}

	Get-ScoopFailure -Desired $Install -Installed @(scoop list 6>$null) | ForEach-Object { "scoop:$_" }
}

Export-ModuleMember -Function Install-Scoop, Get-ScoopApp, Get-ScoopFailure, Invoke-ScoopChange
