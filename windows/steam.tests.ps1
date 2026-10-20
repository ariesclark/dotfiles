BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'steam.psm1') -Force
}

Describe 'Get-SteamLibrary' {
	It 'lists Steam''s own library and every library in libraryfolders.vdf, once each' {
		$vdf = @'
"libraryfolders"
{
	"0"
	{
		"path"		"E:\\Scoop\\apps\\steam\\current"
	}
	"1"
	{
		"path"		"F:\\SteamLibrary"
	}
}
'@

		Get-SteamLibrary -Steam 'E:\Scoop\apps\steam\current' -Folders $vdf |
			Should -BeExactly @('E:\Scoop\apps\steam\current\steamapps', 'F:\SteamLibrary\steamapps')
	}

	It 'lists Steam''s own library when there is no libraryfolders.vdf yet' {
		Get-SteamLibrary -Steam 'E:\Scoop\apps\steam\current' -Folders $null | Should -BeExactly @('E:\Scoop\apps\steam\current\steamapps')
	}
}

Describe 'Get-SteamInstalled' {
	It 'reads app ids from the app manifests in every library' {
		$first = Join-Path $TestDrive 'one'
		$second = Join-Path $TestDrive 'two'
		New-Item -ItemType Directory -Force $first, $second | Out-Null
		Set-Content (Join-Path $first 'appmanifest_431960.acf') ''
		Set-Content (Join-Path $second 'appmanifest_578080.acf') ''
		Set-Content (Join-Path $second 'libraryfolders.vdf') ''

		Get-SteamInstalled -Libraries @($first, $second, (Join-Path $TestDrive 'missing')) | Sort-Object | Should -BeExactly @('431960', '578080')
	}
}
