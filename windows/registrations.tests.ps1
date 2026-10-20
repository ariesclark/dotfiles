BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'registrations.psm1') -Force
}

Describe 'Get-RegistrationPlan' {
	BeforeAll {
		$apps = '{
			"scoop:extras/vscode": { "registry": ["install-context.reg"] },
			"scoop:extras/powertoys": { "removeAppx": ["Microsoft.PowerToys.*ContextMenu"], "scripts": ["install-context.ps1"] },
			"scoop:games/steam": {
				"startup": [{ "name": "Steam", "path": "steam.exe", "arguments": "-silent" }],
				"protocols": [{ "name": "steam", "path": "steam.exe", "arguments": "-- \"%1\"" }]
			},
			"scoop:main/pwsh": { "shims": [{ "name": "pwsh", "directory": "%LOCALAPPDATA%\\Microsoft\\WindowsApps" }] },
			"scoop:extras/chromium": { "shortcuts": [{ "name": "Chromium", "path": "chrome.exe", "arguments": "--no-default-browser-check", "appId": "Chromium.Default" }] },
			"scoop:versions/firefox-nightly": { "shortcuts": [{ "name": "Firefox Nightly", "path": "firefox.exe" }] },
			"winget:Discord.Discord": { "fixedLocation": true }
		}' | ConvertFrom-Json
	}

	It 'plans nothing for apps that are not installed' {
		Get-RegistrationPlan -Apps $apps -Installed @('git') -ScoopRoot 'E:\Scoop' | Should -BeNullOrEmpty
	}

	It 'resolves app files inside the app''s current folder' {
		$plan = @(Get-RegistrationPlan -Apps $apps -Installed @('vscode') -ScoopRoot 'E:\Scoop')

		$plan.Count | Should -Be 1
		$plan[0].Kind | Should -BeExactly 'registry'
		$plan[0].Path | Should -BeExactly 'E:\Scoop\apps\vscode\current\install-context.reg'
	}

	It 'removes stale appx packages before running scripts' {
		$plan = @(Get-RegistrationPlan -Apps $apps -Installed @('powertoys') -ScoopRoot 'E:\Scoop')

		$plan.Kind | Should -BeExactly @('removeAppx', 'script')
		$plan[0].Value | Should -BeExactly 'Microsoft.PowerToys.*ContextMenu'
		$plan[1].Path | Should -BeExactly 'E:\Scoop\apps\powertoys\current\install-context.ps1'
	}

	It 'resolves the packages a script registers, and keeps them out of the stale-package removal' {
		$declared = '{
			"scoop:extras/powertoys": {
				"removeAppx": ["Microsoft.PowerToys.*ContextMenu"],
				"scripts": [{ "path": "install-context.ps1", "skipWhenRegistered": ["WinUI3Apps\\ImageResizerContextMenuPackage.msix"] }]
			}
		}' | ConvertFrom-Json
		$plan = @(Get-RegistrationPlan -Apps $declared -Installed @('powertoys') -ScoopRoot 'E:\Scoop')

		$plan.Kind | Should -BeExactly @('removeAppx', 'script')
		$plan[0].Keep | Should -BeExactly @('E:\Scoop\apps\powertoys\current\WinUI3Apps\ImageResizerContextMenuPackage.msix')
		$plan[1].Path | Should -BeExactly 'E:\Scoop\apps\powertoys\current\install-context.ps1'
		$plan[1].SkipWhenRegistered | Should -BeExactly @('E:\Scoop\apps\powertoys\current\WinUI3Apps\ImageResizerContextMenuPackage.msix')
	}

	It 'leaves startup entries and URL handlers to the user.reg template' {
		Get-RegistrationPlan -Apps $apps -Installed @('steam') -ScoopRoot 'E:\Scoop' | Should -BeNullOrEmpty
	}

	It 'places scoop shims into the given directory' {
		$plan = @(Get-RegistrationPlan -Apps $apps -Installed @('pwsh') -ScoopRoot 'E:\Scoop')

		$plan[0].Kind | Should -BeExactly 'shim'
		$plan[0].Path | Should -BeExactly 'E:\Scoop\shims\pwsh'
		$plan[0].Value | Should -BeExactly (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
	}

	It 'places shortcuts in the Start menu, pointing into the app''s current folder' {
		$plan = @(Get-RegistrationPlan -Apps $apps -Installed @('chromium') -ScoopRoot 'E:\Scoop')

		$plan.Count | Should -Be 1
		$plan[0].Kind | Should -BeExactly 'shortcut'
		$plan[0].Path | Should -BeExactly (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Chromium.lnk')
		$plan[0].Target | Should -BeExactly 'E:\Scoop\apps\chromium\current\chrome.exe'
		$plan[0].Arguments | Should -BeExactly '--no-default-browser-check'
		$plan[0].AppId | Should -BeExactly 'Chromium.Default'
	}

	It 'gives a shortcut with no arguments or app id empty ones' {
		$plan = @(Get-RegistrationPlan -Apps $apps -Installed @('firefox-nightly') -ScoopRoot 'E:\Scoop')

		$plan[0].Arguments | Should -BeExactly ''
		$plan[0].AppId | Should -BeExactly ''
	}
}

Describe 'Get-AppxIdentity' {
	It 'reads the name and version from the package manifest' {
		$folder = Join-Path $TestDrive 'package'
		New-Item -ItemType Directory $folder | Out-Null
		Set-Content (Join-Path $folder 'AppxManifest.xml') '<?xml version="1.0" encoding="utf-8"?><Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"><Identity Name="Contoso.ContextMenu" Version="1.2.3.0" Publisher="CN=Contoso" /></Package>'
		$package = Join-Path $TestDrive 'Contoso.msix'
		Compress-Archive -Path (Join-Path $folder '*') -DestinationPath "$package.zip"
		Move-Item "$package.zip" $package

		$identity = InModuleScope registrations -Parameters @{ package = $package } { Get-AppxIdentity -Path $package }
		$identity.Name | Should -BeExactly 'Contoso.ContextMenu'
		$identity.Version | Should -BeExactly '1.2.3.0'
	}
}

Describe 'Invoke-RegistrationPlan' {
	BeforeAll {
		$shipped = 'E:\Scoop\apps\powertoys\current\WinUI3Apps\ImageResizerContextMenuPackage.msix'
	}

	BeforeEach {
		InModuleScope registrations {
			Mock Import-Module {}
			Mock Test-Path { $true }
			Mock Remove-AppxPackage {}
			Mock Invoke-VendorScript {}
			Mock Get-AppxIdentity { [pscustomobject]@{ Name = 'Microsoft.PowerToys.ImageResizerContextMenu'; Version = '0.101.2362.0' } }
		}
	}

	It 'keeps the packages the app ships when removing stale ones' {
		InModuleScope registrations -Parameters @{ shipped = $shipped } {
			Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.PowerToys.ImageResizerContextMenu'; Version = '0.101.2362.0'; PackageFullName = 'ImageResizer_0.101.2362.0' } }
			Invoke-RegistrationPlan -Plan @([pscustomobject]@{ Kind = 'removeAppx'; App = 'scoop:extras/powertoys'; Value = 'Microsoft.PowerToys.*ContextMenu'; Keep = @($shipped) })
			Should -Invoke Remove-AppxPackage -Times 0 -Exactly
		}
	}

	It 'still removes an older version of a shipped package' {
		InModuleScope registrations -Parameters @{ shipped = $shipped } {
			Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.PowerToys.ImageResizerContextMenu'; Version = '0.100.0.0'; PackageFullName = 'ImageResizer_0.100.0.0' } }
			Invoke-RegistrationPlan -Plan @([pscustomobject]@{ Kind = 'removeAppx'; App = 'scoop:extras/powertoys'; Value = 'Microsoft.PowerToys.*ContextMenu'; Keep = @($shipped) })
			Should -Invoke Remove-AppxPackage -Times 1 -Exactly -ParameterFilter { $Package -eq 'ImageResizer_0.100.0.0' }
		}
	}

	It 'skips a script once every package it registers is registered at the shipped version' {
		InModuleScope registrations -Parameters @{ shipped = $shipped } {
			Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.PowerToys.ImageResizerContextMenu'; Version = '0.101.2362.0'; PackageFullName = 'ImageResizer_0.101.2362.0' } }
			Invoke-RegistrationPlan -Plan @([pscustomobject]@{ Kind = 'script'; App = 'scoop:extras/powertoys'; Path = 'E:\Scoop\apps\powertoys\current\install-context.ps1'; SkipWhenRegistered = @($shipped) })
			Should -Invoke Invoke-VendorScript -Times 0 -Exactly
		}
	}

	It 'runs the script when a package it registers is at another version' {
		InModuleScope registrations -Parameters @{ shipped = $shipped } {
			Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.PowerToys.ImageResizerContextMenu'; Version = '0.100.0.0'; PackageFullName = 'ImageResizer_0.100.0.0' } }
			Invoke-RegistrationPlan -Plan @([pscustomobject]@{ Kind = 'script'; App = 'scoop:extras/powertoys'; Path = 'E:\Scoop\apps\powertoys\current\install-context.ps1'; SkipWhenRegistered = @($shipped) })
			Should -Invoke Invoke-VendorScript -Times 1 -Exactly
		}
	}

	It 'runs the script when a package it registers is missing' {
		InModuleScope registrations -Parameters @{ shipped = $shipped } {
			Mock Get-AppxPackage {}
			Invoke-RegistrationPlan -Plan @([pscustomobject]@{ Kind = 'script'; App = 'scoop:extras/powertoys'; Path = 'E:\Scoop\apps\powertoys\current\install-context.ps1'; SkipWhenRegistered = @($shipped) })
			Should -Invoke Invoke-VendorScript -Times 1 -Exactly
		}
	}

	It 'always runs a script that lists nothing to skip on' {
		InModuleScope registrations {
			Mock Get-AppxPackage {}
			Invoke-RegistrationPlan -Plan @([pscustomobject]@{ Kind = 'script'; App = 'scoop:extras/powertoys'; Path = 'E:\Scoop\apps\powertoys\current\install-context.ps1'; SkipWhenRegistered = @() })
			Should -Invoke Invoke-VendorScript -Times 1 -Exactly
		}
	}
}
