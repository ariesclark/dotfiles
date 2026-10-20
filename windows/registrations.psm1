Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'scoop.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'shortcuts.psm1')

function Get-ListProperty {
	param([object] $Object, [string] $Key)

	$property = $Object.PSObject.Properties[$Key]
	if ($property) {
		@($property.Value)
	}
}

function Get-RegistrationPlan {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Apps,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Installed,
		[Parameter(Mandatory)] [string] $ScoopRoot
	)

	foreach ($entry in $Apps.PSObject.Properties) {
		if ($entry.Name -notlike 'scoop:*') {
			continue
		}
		$name = ($entry.Name -split '/')[1]
		if ($name -notin $Installed) {
			continue
		}
		$current = Join-Path $ScoopRoot "apps\$name\current"
		$resolve = { param($path) $path = [Environment]::ExpandEnvironmentVariables($path); if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $current $path } }

		$scripts = foreach ($script in (Get-ListProperty -Object $entry.Value -Key 'scripts')) {
			if ($script -is [string]) {
				[pscustomobject]@{ Path = (& $resolve $script); SkipWhenRegistered = @() }
			}
			else {
				[pscustomobject]@{ Path = (& $resolve $script.path); SkipWhenRegistered = @(Get-ListProperty -Object $script -Key 'skipWhenRegistered' | ForEach-Object { & $resolve $_ }) }
			}
		}
		$shipped = @($scripts | ForEach-Object { $_.SkipWhenRegistered })

		foreach ($pattern in (Get-ListProperty -Object $entry.Value -Key 'removeAppx')) {
			[pscustomobject]@{ Kind = 'removeAppx'; App = $entry.Name; Name = $null; Path = $null; Value = $pattern; Keep = $shipped }
		}
		foreach ($file in (Get-ListProperty -Object $entry.Value -Key 'registry')) {
			[pscustomobject]@{ Kind = 'registry'; App = $entry.Name; Name = $null; Path = (& $resolve $file); Value = $null }
		}
		foreach ($script in $scripts) {
			[pscustomobject]@{ Kind = 'script'; App = $entry.Name; Name = $null; Path = $script.Path; Value = $null; SkipWhenRegistered = $script.SkipWhenRegistered }
		}
		foreach ($shim in (Get-ListProperty -Object $entry.Value -Key 'shims')) {
			[pscustomobject]@{ Kind = 'shim'; App = $entry.Name; Name = $shim.name; Path = (Join-Path $ScoopRoot "shims\$($shim.name)"); Value = [Environment]::ExpandEnvironmentVariables($shim.directory) }
		}
		foreach ($shortcut in (Get-ListProperty -Object $entry.Value -Key 'shortcuts')) {
			[pscustomobject]@{
				Kind = 'shortcut'
				App = $entry.Name
				Name = $shortcut.name
				Path = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$($shortcut.name).lnk"
				Value = $null
				Target = & $resolve $shortcut.path
				Arguments = "$(Get-ListProperty -Object $shortcut -Key 'arguments')"
				AppId = "$(Get-ListProperty -Object $shortcut -Key 'appId')"
			}
		}
	}
}

function Get-AppxIdentity {
	param([Parameter(Mandatory)] [string] $Path)

	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
	try {
		$reader = [System.IO.StreamReader]::new($archive.GetEntry('AppxManifest.xml').Open())
		try {
			$identity = ([xml]$reader.ReadToEnd()).Package.Identity
		}
		finally {
			$reader.Dispose()
		}
	}
	finally {
		$archive.Dispose()
	}
	[pscustomobject]@{ Name = $identity.Name; Version = $identity.Version }
}

function Test-AppxRegistered {
	param([Parameter(Mandatory)] [object] $Identity)

	[bool](Get-AppxPackage -Name $Identity.Name | Where-Object Version -eq $Identity.Version)
}

function Invoke-VendorScript {
	param([Parameter(Mandatory)] [string] $Path)

	& $Path | Out-Host
}

function Invoke-RegistrationPlan {
	[CmdletBinding()]
	param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan)

	$usesAppx = ($Plan.Kind -contains 'removeAppx') -or ($Plan | Where-Object { $_.PSObject.Properties['SkipWhenRegistered'] -and $_.SkipWhenRegistered })
	if ($usesAppx -and $PSVersionTable.PSEdition -eq 'Core') {
		Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue
	}
	foreach ($step in $Plan) {
		switch ($step.Kind) {
			'removeAppx' {
				$keep = @($step.Keep | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-AppxIdentity -Path $_ })
				Get-AppxPackage -Name $step.Value |
					Where-Object { $package = $_; -not ($keep | Where-Object { $_.Name -eq $package.Name -and $_.Version -eq $package.Version }) } |
					ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName }
			}
			'registry' {
				if (Test-Path -LiteralPath $step.Path) {
					reg import $step.Path 2>&1 | Out-Null
				}
			}
			'script' {
				$packages = @($step.SkipWhenRegistered | Where-Object { Test-Path -LiteralPath $_ })
				if ($packages -and $packages.Count -eq $step.SkipWhenRegistered.Count -and -not ($packages | Where-Object { -not (Test-AppxRegistered -Identity (Get-AppxIdentity -Path $_)) })) {
					continue
				}
				if (Test-Path -LiteralPath $step.Path) {
					try {
						Invoke-VendorScript -Path $step.Path
					}
					catch {
						Write-Warning "$($step.App): $(Split-Path $step.Path -Leaf) failed: $($_.Exception.Message.Split([Environment]::NewLine)[0])"
					}
				}
			}
			'shim' {
				New-Item -ItemType Directory -Force -Path $step.Value | Out-Null
				$executable = Join-Path $step.Value "$($step.Name).exe"
				if (-not (Test-Path -LiteralPath $executable)) {
					Copy-Item -LiteralPath "$($step.Path).exe" -Destination $executable
				}
				Copy-Item -LiteralPath "$($step.Path).shim" -Destination (Join-Path $step.Value "$($step.Name).shim") -Force
			}
			'shortcut' {
				Sync-Shortcut -Path $step.Path -Target $step.Target -Arguments $step.Arguments -AppId $step.AppId
			}
		}
	}
}

function Sync-Registration {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Apps,
		[Parameter(Mandatory)] [object] $Install
	)

	Install-Scoop -Root $Install.scoop
	$plan = @(Get-RegistrationPlan -Apps $Apps -Installed @(Get-ScoopApp) -ScoopRoot $Install.scoop)
	Invoke-RegistrationPlan -Plan $plan
}

Export-ModuleMember -Function Get-RegistrationPlan, Sync-Registration
