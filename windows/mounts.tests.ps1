BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'mounts.psm1') -Force
}

Describe 'Install-Mount' {
	BeforeEach {
		$root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
		$from = Join-Path $root 'app\library'
		$to = Join-Path $root 'Data\Library'
		$mount = @{ From = $from; To = $to }
	}

	It 'creates the to folder and a junction to it when neither exists' {
		Install-Mount -Mounts @($mount)

		Test-Path -LiteralPath $to -PathType Container | Should -BeTrue
		(Get-Item -LiteralPath $from -Force).LinkType | Should -Be 'Junction'
		(Get-Item -LiteralPath $from -Force).Target | Should -Be $to
	}

	It 'leaves a junction that already points at its to folder alone' {
		Install-Mount -Mounts @($mount)
		Set-Content -LiteralPath (Join-Path $to 'game.txt') -Value 'installed'

		Install-Mount -Mounts @($mount)

		(Get-Item -LiteralPath $from -Force).Target | Should -Be $to
		Get-Content -LiteralPath (Join-Path $from 'game.txt') | Should -Be 'installed'
	}

	It 'retargets a junction that points somewhere else' {
		$old = Join-Path $root 'old'
		New-Item -ItemType Directory -Force $old, (Split-Path $from) | Out-Null
		New-Item -ItemType Junction -Path $from -Target $old | Out-Null

		Install-Mount -Mounts @($mount)

		(Get-Item -LiteralPath $from -Force).Target | Should -Be $to
		Test-Path -LiteralPath $old -PathType Container | Should -BeTrue
	}

	It 'replaces an empty real folder at from with the junction' {
		New-Item -ItemType Directory -Force $from | Out-Null

		Install-Mount -Mounts @($mount)

		(Get-Item -LiteralPath $from -Force).LinkType | Should -Be 'Junction'
	}

	It 'refuses a real folder with contents at from and keeps them' {
		New-Item -ItemType Directory -Force $from | Out-Null
		Set-Content -LiteralPath (Join-Path $from 'save.dat') -Value 'progress'

		{ Install-Mount -Mounts @($mount) } | Should -Throw "*$from*"

		(Get-Item -LiteralPath $from -Force).LinkType | Should -BeNullOrEmpty
		Get-Content -LiteralPath (Join-Path $from 'save.dat') | Should -Be 'progress'
	}

	It 'fixes the casing of an existing to folder' {
		New-Item -ItemType Directory -Force (Join-Path $root 'data\library') | Out-Null

		Install-Mount -Mounts @($mount)

		(Get-ChildItem -LiteralPath $root -Directory | Where-Object Name -ieq 'data').Name | Should -BeExactly 'Data'
		(Get-ChildItem -LiteralPath (Join-Path $root 'Data') -Directory).Name | Should -BeExactly 'Library'
	}

	It 'expands environment variables in from' {
		$env:MOUNT_TEST_ROOT = $root
		$mount.From = '%MOUNT_TEST_ROOT%\app\library'

		Install-Mount -Mounts @($mount)

		(Get-Item -LiteralPath $from -Force).Target | Should -Be $to
	}
}
