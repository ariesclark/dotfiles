BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'scoop.psm1') -Force
}

Describe 'Get-ScoopFailure' {
	BeforeAll {
		function New-Installed([string] $Name, [string] $Info = '') {
			[pscustomobject]@{ Name = $Name; Info = $Info }
		}
	}

	It 'reports a desired app that scoop marks as failed' {
		$installed = @(New-Installed 'git'; New-Installed 'unity-hub-np' 'Install failed')

		Get-ScoopFailure -Desired @('main/git', 'nonportable/unity-hub-np') -Installed $installed | Should -BeExactly @('nonportable/unity-hub-np')
	}

	It 'reports a desired app that is not installed at all' {
		Get-ScoopFailure -Desired @('main/git', 'extras/vlc') -Installed @(New-Installed 'git') | Should -BeExactly @('extras/vlc')
	}

	It 'reports nothing when every desired app is installed' {
		$installed = @(New-Installed 'git'; New-Installed 'vlc'; New-Installed '7zip')

		Get-ScoopFailure -Desired @('main/git', 'extras/vlc') -Installed $installed | Should -BeNullOrEmpty
	}
}
