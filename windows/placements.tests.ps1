BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'placements.psm1') -Force
}

Describe 'Install-Placement' {
	BeforeEach {
		$root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
		$link = Join-Path $root 'app\library'
		$target = Join-Path $root 'Data\Library'
		$placement = @{ Link = $link; Target = $target }
	}

	It 'creates the target and a junction to it when neither exists' {
		Install-Placement -Placements @($placement)

		Test-Path -LiteralPath $target -PathType Container | Should -BeTrue
		(Get-Item -LiteralPath $link -Force).LinkType | Should -Be 'Junction'
		(Get-Item -LiteralPath $link -Force).Target | Should -Be $target
	}

	It 'leaves a junction that already points at its target alone' {
		Install-Placement -Placements @($placement)
		Set-Content -LiteralPath (Join-Path $target 'game.txt') -Value 'installed'

		Install-Placement -Placements @($placement)

		(Get-Item -LiteralPath $link -Force).Target | Should -Be $target
		Get-Content -LiteralPath (Join-Path $link 'game.txt') | Should -Be 'installed'
	}

	It 'retargets a junction that points somewhere else' {
		$old = Join-Path $root 'old'
		New-Item -ItemType Directory -Force $old, (Split-Path $link) | Out-Null
		New-Item -ItemType Junction -Path $link -Target $old | Out-Null

		Install-Placement -Placements @($placement)

		(Get-Item -LiteralPath $link -Force).Target | Should -Be $target
		Test-Path -LiteralPath $old -PathType Container | Should -BeTrue
	}

	It 'replaces an empty real folder at the link with the junction' {
		New-Item -ItemType Directory -Force $link | Out-Null

		Install-Placement -Placements @($placement)

		(Get-Item -LiteralPath $link -Force).LinkType | Should -Be 'Junction'
	}

	It 'refuses a real folder with contents at the link and keeps them' {
		New-Item -ItemType Directory -Force $link | Out-Null
		Set-Content -LiteralPath (Join-Path $link 'save.dat') -Value 'progress'

		{ Install-Placement -Placements @($placement) } | Should -Throw "*$link*"

		(Get-Item -LiteralPath $link -Force).LinkType | Should -BeNullOrEmpty
		Get-Content -LiteralPath (Join-Path $link 'save.dat') | Should -Be 'progress'
	}

	It 'fixes the casing of an existing target' {
		New-Item -ItemType Directory -Force (Join-Path $root 'data\library') | Out-Null

		Install-Placement -Placements @($placement)

		(Get-ChildItem -LiteralPath $root -Directory | Where-Object Name -ieq 'data').Name | Should -BeExactly 'Data'
		(Get-ChildItem -LiteralPath (Join-Path $root 'Data') -Directory).Name | Should -BeExactly 'Library'
	}

	It 'expands environment variables in the link' {
		$env:PLACEMENT_TEST_ROOT = $root
		$placement.Link = '%PLACEMENT_TEST_ROOT%\app\library'

		Install-Placement -Placements @($placement)

		(Get-Item -LiteralPath $link -Force).Target | Should -Be $target
	}
}
