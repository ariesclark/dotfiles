BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'archive.psm1') -Force
}

Describe 'Update-Archive' {
	BeforeEach {
		$root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
		$rendered = Join-Path $root 'rendered'
		New-Item -ItemType Directory -Force (Join-Path $rendered '.config\git'), (Join-Path $rendered '.chezmoiscripts') | Out-Null
		Set-Content -LiteralPath (Join-Path $rendered '.config\git\config') -Value "[user]`n`tname = Test" -NoNewline
		Set-Content -LiteralPath (Join-Path $rendered '.chezmoiscripts\00-partition.ps1') -Value 'Sync-Partition' -NoNewline
		$archive = Join-Path $root 'target.tar'
		tar -cf $archive -C $rendered .config .chezmoiscripts
		$destination = Join-Path $root '.archive'
	}

	It 'lays the managed files and scripts out as chezmoi renders them' {
		Update-Archive -Archive $archive -Destination $destination

		Get-Content -Raw -LiteralPath (Join-Path $destination '.config\git\config') | Should -BeExactly "[user]`n`tname = Test"
		Get-Content -Raw -LiteralPath (Join-Path $destination '.chezmoiscripts\00-partition.ps1') | Should -BeExactly 'Sync-Partition'
	}

	It 'replaces the earlier archive, so files chezmoi no longer renders are gone' {
		New-Item -ItemType Directory -Force $destination | Out-Null
		Set-Content -LiteralPath (Join-Path $destination 'removed.txt') -Value 'stale'

		Update-Archive -Archive $archive -Destination $destination

		Test-Path -LiteralPath (Join-Path $destination 'removed.txt') | Should -BeFalse
		Test-Path -LiteralPath (Join-Path $destination '.config\git\config') | Should -BeTrue
	}

	It 'keeps the earlier archive when the new one can''t be read' {
		New-Item -ItemType Directory -Force $destination | Out-Null
		Set-Content -LiteralPath (Join-Path $destination 'kept.txt') -Value 'earlier'

		{ Update-Archive -Archive (Join-Path $root 'missing.tar') -Destination $destination } | Should -Throw

		Get-Content -LiteralPath (Join-Path $destination 'kept.txt') | Should -Be 'earlier'
	}

	It 'leaves nothing but the archive folder behind' {
		Update-Archive -Archive $archive -Destination $destination

		@(Get-ChildItem -Force -LiteralPath $root).Name | Sort-Object | Should -Be @('.archive', 'rendered', 'target.tar')
	}
}
