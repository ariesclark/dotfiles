BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'pagefile.psm1') -Force
}

Describe 'importing pagefile.psm1' {
	It 'leaves volumes.psm1''s functions with whoever imported it first, in <Shell>' -ForEach @(@{ Shell = 'pwsh' }, @{ Shell = 'powershell' }) {
		$command = "Import-Module '$PSScriptRoot\volumes.psm1' -Force; Import-Module '$PSScriptRoot\pagefile.psm1' -Force; [bool](Get-Command Sync-Volume -ErrorAction SilentlyContinue)"
		& $Shell -NoProfile -ExecutionPolicy Bypass -Command $command | Should -BeExactly 'True'
	}
}

Describe 'Get-PagefileDeclaration' {
	It 'sizes a memory pagefile to the installed memory, rounded up to whole GB' {
		$volumes = '{ "c": { "label": "System", "size": "100GB" }, "e": { "label": "Apps", "size": "fill", "pagefile": "memory" } }' | ConvertFrom-Json

		$pagefile = Get-PagefileDeclaration -Volumes $volumes -MemoryBytes ([long](31.9 * 1GB))

		$pagefile.letter | Should -BeExactly 'E'
		$pagefile.sizeGB | Should -Be 32
	}

	It 'takes a fixed size as given' {
		$volumes = '{ "d": { "label": "Data", "size": "500GB", "pagefile": "16gb" } }' | ConvertFrom-Json

		$pagefile = Get-PagefileDeclaration -Volumes $volumes -MemoryBytes (32GB)

		$pagefile.letter | Should -BeExactly 'D'
		$pagefile.sizeGB | Should -Be 16
	}

	It 'declares nothing when no volume has a pagefile' {
		$volumes = '{ "c": { "label": "System", "size": "100GB" } }' | ConvertFrom-Json

		Get-PagefileDeclaration -Volumes $volumes -MemoryBytes (32GB) | Should -BeNullOrEmpty
	}

	It 'refuses a pagefile on more than one volume' {
		$volumes = '{ "d": { "label": "Data", "size": "500GB", "pagefile": "memory" }, "e": { "label": "Apps", "size": "fill", "pagefile": "memory" } }' | ConvertFrom-Json

		{ Get-PagefileDeclaration -Volumes $volumes -MemoryBytes (32GB) } | Should -Throw '*one volume*'
	}

	It 'refuses a size it can''t read' {
		$volumes = '{ "e": { "label": "Apps", "size": "fill", "pagefile": "huge" } }' | ConvertFrom-Json

		{ Get-PagefileDeclaration -Volumes $volumes -MemoryBytes (32GB) } | Should -Throw '*huge*'
	}
}

Describe 'Get-PagefileChange' {
	BeforeAll {
		$desired = [pscustomobject]@{ letter = 'E'; sizeGB = 32 }
		function New-Setting($Name, $SizeMB) { [pscustomobject]@{ Name = $Name; InitialSize = $SizeMB; MaximumSize = $SizeMB } }
	}

	It 'adds a fixed-size pagefile on the declared volume when there is none' {
		$changes = @(Get-PagefileChange -Desired $desired -Automatic $false -Settings @())

		$changes.Count | Should -Be 1
		$changes[0].Action | Should -BeExactly 'Set'
		$changes[0].Name | Should -BeExactly 'E:\pagefile.sys'
		$changes[0].SizeMB | Should -Be 32768
	}

	It 'turns off Windows managing it first' {
		$changes = @(Get-PagefileChange -Desired $desired -Automatic $true -Settings @())

		$changes.Action | Should -BeExactly @('DisableAutomatic', 'Set')
	}

	It 'removes pagefiles on other volumes' {
		$changes = @(Get-PagefileChange -Desired $desired -Automatic $false -Settings @((New-Setting 'C:\pagefile.sys' 4096), (New-Setting 'E:\pagefile.sys' 32768)))

		$changes.Count | Should -Be 1
		$changes[0].Action | Should -BeExactly 'Remove'
		$changes[0].Name | Should -BeExactly 'C:\pagefile.sys'
	}

	It 'resizes a pagefile of the wrong size' {
		$changes = @(Get-PagefileChange -Desired $desired -Automatic $false -Settings @([pscustomobject]@{ Name = 'E:\pagefile.sys'; InitialSize = 0; MaximumSize = 0 }))

		$changes.Action | Should -BeExactly @('Set')
		$changes[0].SizeMB | Should -Be 32768
	}

	It 'changes nothing when it already matches, ignoring the case of the path' {
		Get-PagefileChange -Desired $desired -Automatic $false -Settings @(New-Setting 'e:\PAGEFILE.SYS' 32768) | Should -BeNullOrEmpty
	}
}
