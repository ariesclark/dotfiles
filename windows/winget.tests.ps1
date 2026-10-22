BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'winget.psm1') -Force
}

Describe 'Get-WingetInstallArgument' {
	It 'installs silently from the given source' {
		Get-WingetInstallArgument -Id 'Overwolf.CurseForge' -Source winget |
			Should -BeExactly @('install', '--id', 'Overwolf.CurseForge', '--exact', '--source', 'winget', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
	}

	It 'passes the install location when one is declared' {
		$arguments = Get-WingetInstallArgument -Id 'Overwolf.CurseForge' -Source winget -Location 'E:\Apps\CurseForge'

		$index = [array]::IndexOf($arguments, '--location')
		$index | Should -BeGreaterThan -1
		$arguments[$index + 1] | Should -BeExactly 'E:\Apps\CurseForge'
	}

	It 'picks the installer type when one is declared' {
		$arguments = Get-WingetInstallArgument -Id 'AgileBits.1Password' -Source winget -InstallerType msix

		$index = [array]::IndexOf($arguments, '--installer-type')
		$index | Should -BeGreaterThan -1
		$arguments[$index + 1] | Should -BeExactly 'msix'
		$arguments | Should -Not -Contain '--location'
	}

	It 'replaces the installer''s own flags when an override is declared' {
		$override = 'install --quiet --user --installation-dir=E:\Apps\Docker'
		$arguments = Get-WingetInstallArgument -Id 'Docker.DockerDesktop' -Source winget -Override $override

		$index = [array]::IndexOf($arguments, '--override')
		$index | Should -BeGreaterThan -1
		$arguments[$index + 1] | Should -BeExactly $override
		$arguments | Should -Not -Contain '--location'
	}
}
