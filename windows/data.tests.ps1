BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'packages.psm1') -Force
	$data = chezmoi --source (Split-Path $PSScriptRoot) data --format json | ConvertFrom-Json
	$layout = $data.layout
	$groups = $data.groups
	$apps = $data.apps
	$listed = @($groups.PSObject.Properties.Value | ForEach-Object { $_.PSObject.Properties['apps'] } | Where-Object { $_ } | ForEach-Object { $_.Value })
}

Describe 'layout.yaml' {
	It 'never declares two placements for the same link' {
		$duplicates = $layout.placements.link | Group-Object { $_.ToLowerInvariant() } | Where-Object Count -gt 1
		$duplicates | Should -BeNullOrEmpty
	}

	It 'puts every placement target on a declared volume, with an uppercase drive letter' {
		$letters = $layout.volumes.letter
		$layout.placements.target | Where-Object { $_.Substring(0, 1) -cnotin $letters } | Should -BeNullOrEmpty
	}

	It 'installs winget apps to a declared volume, not C:' {
		$layout.winget.Substring(0, 1) | Should -BeIn @($layout.volumes.letter)
	}
}

Describe 'groups.yaml' {
	It 'only uses the keys needs and apps, and never empty' {
		foreach ($group in $groups.PSObject.Properties) {
			$group.Value.PSObject.Properties.Name | Where-Object { $_ -notin 'needs', 'apps' } | Should -BeNullOrEmpty -Because $group.Name
			$group.Value.PSObject.Properties | Where-Object { @($_.Value).Count -eq 0 } | Should -BeNullOrEmpty -Because $group.Name
		}
	}

	It 'only needs groups that exist and has no cycles' {
		{ Resolve-Group -Groups $groups -Selected @($groups.PSObject.Properties.Name) } | Should -Not -Throw
	}

	It 'names every app source:id (scoop:bucket/app, winget:id, msstore:id, steam:appid)' {
		$listed.Count | Should -BeGreaterThan 0
		$listed | Where-Object { $_ -notmatch '^(scoop:[a-z0-9-]+/[a-z0-9.-]+|winget:[A-Za-z0-9.-]+|msstore:[A-Z0-9]+|steam:[0-9]+)$' } | Should -BeNullOrEmpty
	}

	It 'lists each app in one group only' {
		$listed | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name | Should -BeNullOrEmpty
	}
}

Describe 'apps.yaml' {
	It 'only configures apps that some group lists' {
		$apps.PSObject.Properties.Name | Where-Object { $_ -notin $listed } | Should -BeNullOrEmpty
	}

	It 'gives apps from other sources only install options, since their files are not in a Scoop folder' {
		$apps.PSObject.Properties | Where-Object { $_.Name -notlike 'scoop:*' } | ForEach-Object {
			$_.Value.PSObject.Properties.Name | Where-Object { $_ -notin 'location', 'installerType', 'fixedLocation' } | Should -BeNullOrEmpty -Because $_.Name
		}
	}

	It 'only gives install options to apps winget installs' {
		foreach ($app in $apps.PSObject.Properties) {
			foreach ($key in 'location', 'installerType', 'fixedLocation') {
				if ($app.Value.PSObject.Properties[$key]) {
					$app.Name | Should -Match '^(winget|msstore):' -Because "$($app.Name).$key"
				}
			}
		}
	}

	It 'only gives install locations to winget apps, and never on C:' {
		foreach ($app in $apps.PSObject.Properties | Where-Object { $_.Value.PSObject.Properties['location'] }) {
			$app.Name | Should -BeLike 'winget:*'
			$app.Value.location | Should -Not -BeLike 'C:*' -Because $app.Name
		}
	}

	It 'only declares a location that differs from the default under layout.winget' {
		foreach ($app in $apps.PSObject.Properties | Where-Object { $_.Value.PSObject.Properties['location'] }) {
			$default = Join-Path $layout.winget ($app.Name -split ':', 2)[1]
			$app.Value.location | Should -Not -Be $default -Because "$($app.Name) would get that folder anyway"
		}
	}

	It 'only uses known keys, and never empty' {
		foreach ($app in $apps.PSObject.Properties) {
			@($app.Value.PSObject.Properties).Count | Should -BeGreaterThan 0 -Because $app.Name
			$app.Value.PSObject.Properties.Name | Where-Object { $_ -notin 'removeAppx', 'registry', 'scripts', 'startup', 'shims', 'protocols', 'location', 'installerType', 'fixedLocation' } | Should -BeNullOrEmpty -Because $app.Name
			$app.Value.PSObject.Properties | Where-Object { @($_.Value).Count -eq 0 } | Should -BeNullOrEmpty -Because $app.Name
		}
	}
}
