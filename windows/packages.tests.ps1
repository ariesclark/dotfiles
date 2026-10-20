BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'packages.psm1') -Force

	function New-Groups([string] $Json) {
		$Json | ConvertFrom-Json
	}
}

Describe 'Resolve-Group' {
	BeforeAll {
		$fixture = New-Groups '{
			"base": {},
			"dev": { "needs": ["base"] },
			"unity": { "needs": ["dev"] },
			"vrchat": { "needs": ["base"] },
			"vrchat-dev": { "needs": ["vrchat", "unity"] }
		}'
	}

	It 'expands needs transitively, dependencies before dependents' {
		Resolve-Group -Groups $fixture -Selected @('vrchat-dev') | Should -BeExactly @('base', 'vrchat', 'dev', 'unity', 'vrchat-dev')
	}

	It 'lists each group once when selections overlap' {
		Resolve-Group -Groups $fixture -Selected @('unity', 'dev', 'base') | Should -BeExactly @('base', 'dev', 'unity')
	}

	It 'refuses an unknown group by name' {
		{ Resolve-Group -Groups $fixture -Selected @('work') } | Should -Throw "*'work'*"
	}

	It 'refuses a cycle and names the groups in it' {
		$cyclic = New-Groups '{ "a": { "needs": ["b"] }, "b": { "needs": ["a"] } }'
		{ Resolve-Group -Groups $cyclic -Selected @('a') } | Should -Throw '*cycle: a -> b -> a*'
	}
}

Describe 'Get-PackageSet' {
	BeforeAll {
		$fixture = New-Groups '{
			"base": { "apps": ["scoop:main/git", "scoop:extras/vlc", "winget:AgileBits.1Password"] },
			"dev": { "needs": ["base"], "apps": ["scoop:extras/vscode", "msstore:9P8LTPGCBZXD", "steam:431960"] },
			"hardware": { "needs": ["dev"] },
			"games": { "apps": ["games/steam"] }
		}'
	}

	It 'collects the apps of the given groups per source, sorted' {
		$set = Get-PackageSet -Groups $fixture -Names @('base', 'dev', 'hardware')

		$set.scoop | Should -BeExactly @('extras/vlc', 'extras/vscode', 'main/git')
		$set.winget | Should -BeExactly @('AgileBits.1Password')
		$set.msstore | Should -BeExactly @('9P8LTPGCBZXD')
		$set.steam | Should -BeExactly @('431960')
	}

	It 'leaves out apps of groups that are not given' {
		(Get-PackageSet -Groups $fixture -Names @('dev')).scoop | Should -BeExactly @('extras/vscode')
	}

	It 'refuses an app without a source' {
		{ Get-PackageSet -Groups $fixture -Names @('games') } | Should -Throw "*'games/steam'*"
	}
}

Describe 'Resolve-InstallLocation' {
	It 'puts a winget app in its own folder under the root, named by its id' {
		Resolve-InstallLocation -Id 'Cloudflare.Warp' -Source winget -Option $null -Root 'E:\Apps' | Should -BeExactly 'E:\Apps\Cloudflare.Warp'
	}

	It 'uses the location apps.yaml declares instead' {
		$option = [pscustomobject]@{ Location = 'E:\Games\Riot\League of Legends'; InstallerType = $null }

		Resolve-InstallLocation -Id 'RiotGames.LeagueOfLegends.NA' -Source winget -Option $option -Root 'E:\Apps' | Should -BeExactly 'E:\Games\Riot\League of Legends'
	}

	It 'gives MSIX installs no folder, since Windows picks their drive' {
		$option = [pscustomobject]@{ Location = $null; InstallerType = 'msix' }

		Resolve-InstallLocation -Id 'AgileBits.1Password' -Source winget -Option $option -Root 'E:\Apps' | Should -BeNullOrEmpty
	}

	It 'gives apps whose installer cannot choose a folder none' {
		$option = [pscustomobject]@{ Location = $null; InstallerType = $null; FixedLocation = $true }

		Resolve-InstallLocation -Id 'Discord.Discord' -Source winget -Option $option -Root 'E:\Apps' | Should -BeNullOrEmpty
	}

	It 'gives Store apps no folder' {
		Resolve-InstallLocation -Id '9P8LTPGCBZXD' -Source msstore -Option $null -Root 'E:\Apps' | Should -BeNullOrEmpty
	}
}

Describe 'Get-InstallOption' {
	BeforeAll {
		$apps = '{
			"winget:Cloudflare.Warp": { "location": "E:\\Apps\\Cloudflare WARP" },
			"winget:AgileBits.1Password": { "installerType": "msix" },
			"winget:Discord.Discord": { "fixedLocation": true },
			"scoop:extras/vscode": { "registry": ["install-context.reg"] }
		}' | ConvertFrom-Json
	}

	It 'collects each app''s install options for one source, keyed by its id' {
		$options = Get-InstallOption -Apps $apps -Source winget

		@($options.Keys | Sort-Object) | Should -BeExactly @('AgileBits.1Password', 'Cloudflare.Warp', 'Discord.Discord')
		$options['Cloudflare.Warp'].Location | Should -BeExactly 'E:\Apps\Cloudflare WARP'
		$options['Cloudflare.Warp'].InstallerType | Should -BeNullOrEmpty
		$options['AgileBits.1Password'].InstallerType | Should -BeExactly 'msix'
		$options['Discord.Discord'].FixedLocation | Should -BeTrue
		$options['Cloudflare.Warp'].FixedLocation | Should -BeFalse
	}
}

Describe 'Get-PackageChange' {
	BeforeAll {
		function New-Set([string[]] $Scoop = @(), [string[]] $Winget = @(), [string[]] $MsStore = @(), [string[]] $Steam = @()) {
			[pscustomobject]@{ scoop = $Scoop; winget = $Winget; msstore = $MsStore; steam = $Steam }
		}
	}

	It 'uninstalls steam games it applied before' {
		$change = Get-PackageChange -Desired (New-Set -Steam '431960') -Previous (New-Set -Steam '431960', '578080')

		$change.install.steam | Should -BeExactly @('431960')
		$change.uninstall.steam | Should -BeExactly @('578080')
	}

	It 'reads a state file written before steam was a source' {
		$previous = [pscustomobject]@{ scoop = @('main/git'); winget = @(); msstore = @() }

		$change = Get-PackageChange -Desired (New-Set -Scoop 'main/git' -Steam '431960') -Previous $previous

		$change.install.steam | Should -BeExactly @('431960')
		$change.uninstall.steam | Should -BeNullOrEmpty
	}

	It 'installs everything desired' {
		$change = Get-PackageChange -Desired (New-Set -Scoop 'main/git', 'extras/vlc' -Winget 'Docker.DockerDesktop') -Previous (New-Set -Scoop 'main/git')

		$change.install.scoop | Should -BeExactly @('main/git', 'extras/vlc')
		$change.install.winget | Should -BeExactly @('Docker.DockerDesktop')
	}

	It 'uninstalls what was applied before and is no longer desired' {
		$change = Get-PackageChange -Desired (New-Set -Scoop 'main/git') -Previous (New-Set -Scoop 'main/git', 'games/steam' -Winget 'Overwolf.CurseForge')

		$change.uninstall.scoop | Should -BeExactly @('games/steam')
		$change.uninstall.winget | Should -BeExactly @('Overwolf.CurseForge')
		$change.uninstall.msstore | Should -BeNullOrEmpty
	}

	It 'uninstalls nothing on the first run' {
		$change = Get-PackageChange -Desired (New-Set -Scoop 'main/git') -Previous $null

		$change.uninstall.scoop | Should -BeNullOrEmpty
		$change.uninstall.winget | Should -BeNullOrEmpty
		$change.uninstall.msstore | Should -BeNullOrEmpty
	}

	It 'never uninstalls something it did not apply before' {
		$change = Get-PackageChange -Desired (New-Set) -Previous (New-Set -Scoop 'main/git')

		$change.uninstall.scoop | Should -BeExactly @('main/git')
		$change.uninstall.winget | Should -BeNullOrEmpty
	}
}
