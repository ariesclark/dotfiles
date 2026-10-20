BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'volumes.psm1') -Force
	$layout = '{
		"system": { "label": "Windows", "letter": "C", "sizeGB": 500 },
		"volumes": [
			{ "label": "Data", "letter": "D", "sizeGB": 400 },
			{ "label": "Apps & Cache", "letter": "E", "sizeGB": null }
		]
	}' | ConvertFrom-Json

	function New-Volume([string] $Label, [string] $Letter) {
		[pscustomobject]@{ FileSystemLabel = $Label; DriveLetter = $Letter }
	}
}

Describe 'Get-VolumeProblem' {
	It 'reports nothing when every label sits on its letter' {
		$volumes = @(
			New-Volume 'system' 'C'
			New-Volume 'data' 'D'
			New-Volume 'apps & cache' 'E'
		)

		Get-VolumeProblem -Layout $layout -Volumes $volumes | Should -BeNullOrEmpty
	}

	It 'matches labels case-insensitively' {
		$volumes = @(
			New-Volume 'Data' 'D'
			New-Volume 'APPS & CACHE' 'E'
		)

		Get-VolumeProblem -Layout $layout -Volumes $volumes | Should -BeNullOrEmpty
	}

	It 'reports a volume that does not exist' {
		$volumes = @(
			New-Volume 'system' 'C'
			New-Volume 'data' 'D'
		)

		$problems = @(Get-VolumeProblem -Layout $layout -Volumes $volumes)

		$problems.Count | Should -Be 1
		$problems[0].Kind | Should -Be 'missing'
		$problems[0].Label | Should -Be 'Apps & Cache'
		$problems[0].Expected | Should -Be 'E'
	}

	It 'reports a volume on the wrong letter' {
		$volumes = @(
			New-Volume 'data' 'F'
			New-Volume 'apps & cache' 'E'
		)

		$problems = @(Get-VolumeProblem -Layout $layout -Volumes $volumes)

		$problems.Count | Should -Be 1
		$problems[0].Kind | Should -Be 'wrong-letter'
		$problems[0].Label | Should -Be 'data'
		$problems[0].Current | Should -Be 'F'
		$problems[0].Expected | Should -Be 'D'
	}

	It 'reports when the expected letter is held by another volume' {
		$volumes = @(
			New-Volume 'data' 'F'
			New-Volume 'usb' 'D'
			New-Volume 'apps & cache' 'E'
		)

		$problems = @(Get-VolumeProblem -Layout $layout -Volumes $volumes)

		$problems.Count | Should -Be 1
		$problems[0].Kind | Should -Be 'letter-taken'
		$problems[0].Label | Should -Be 'data'
		$problems[0].Holder | Should -Be 'usb'
	}

	It 'reports a label that appears on more than one volume' {
		$volumes = @(
			New-Volume 'data' 'D'
			New-Volume 'data' 'G'
			New-Volume 'apps & cache' 'E'
		)

		$problems = @(Get-VolumeProblem -Layout $layout -Volumes $volumes)

		$problems.Count | Should -Be 1
		$problems[0].Kind | Should -Be 'duplicate-label'
		$problems[0].Label | Should -Be 'data'
	}
}

Describe 'Get-LabelChange' {
	It 'labels an unlabelled system volume' {
		$volumes = @(
			New-Volume '' 'C'
			New-Volume 'Data' 'D'
			New-Volume 'Apps & Cache' 'E'
		)

		$changes = @(Get-LabelChange -Layout $layout -Volumes $volumes)

		$changes.Count | Should -Be 1
		$changes[0].Letter | Should -Be 'C'
		$changes[0].Current | Should -BeNullOrEmpty
		$changes[0].Expected | Should -BeExactly 'Windows'
	}

	It 'fixes the casing of a label that differs only in case' {
		$volumes = @(
			New-Volume 'Windows' 'C'
			New-Volume 'data' 'D'
			New-Volume 'Apps & Cache' 'E'
		)

		$changes = @(Get-LabelChange -Layout $layout -Volumes $volumes)

		$changes.Count | Should -Be 1
		$changes[0].Letter | Should -Be 'D'
		$changes[0].Current | Should -BeExactly 'data'
		$changes[0].Expected | Should -BeExactly 'Data'
	}

	It 'changes nothing when every label matches exactly' {
		$volumes = @(
			New-Volume 'Windows' 'C'
			New-Volume 'Data' 'D'
			New-Volume 'Apps & Cache' 'E'
		)

		Get-LabelChange -Layout $layout -Volumes $volumes | Should -BeNullOrEmpty
	}

	It 'leaves volumes the layout does not declare alone' {
		$volumes = @(
			New-Volume 'Windows' 'C'
			New-Volume 'Data' 'D'
			New-Volume 'Apps & Cache' 'E'
			New-Volume 'usb stick' 'F'
		)

		Get-LabelChange -Layout $layout -Volumes $volumes | Should -BeNullOrEmpty
	}

	It 'skips a declared letter that has no volume yet' {
		$volumes = @(New-Volume '' 'C')

		$changes = @(Get-LabelChange -Layout $layout -Volumes $volumes)

		$changes.Letter | Should -BeExactly @('C')
	}
}

Describe 'Get-PartitionPlan' {
	BeforeAll {
		function New-System([double] $SizeGB, [double] $MinimumGB) {
			[pscustomobject]@{ SizeBytes = [long]($SizeGB * 1GB); MinimumBytes = [long]($MinimumGB * 1GB) }
		}
	}

	It 'shrinks the system volume and creates every missing volume on a single-partition disk' {
		$plan = @(Get-PartitionPlan -Layout $layout -System (New-System 1906 120) -FreeBytes 0 -Volumes @(New-Volume '' 'C'))

		$plan.Count | Should -Be 3
		$plan[0].Action | Should -Be 'shrink'
		$plan[0].Letter | Should -Be 'C'
		$plan[0].SizeBytes | Should -Be (500GB)
		$plan[1].Action | Should -Be 'create'
		$plan[1].Label | Should -Be 'data'
		$plan[1].Letter | Should -Be 'D'
		$plan[1].SizeBytes | Should -Be (400GB)
		$plan[2].Action | Should -Be 'create'
		$plan[2].Label | Should -Be 'Apps & Cache'
		$plan[2].Letter | Should -Be 'E'
		$plan[2].SizeBytes | Should -BeNullOrEmpty
	}

	It 'plans nothing when every volume already exists' {
		$volumes = @(
			New-Volume '' 'C'
			New-Volume 'data' 'D'
			New-Volume 'apps & cache' 'E'
		)

		Get-PartitionPlan -Layout $layout -System (New-System 500 120) -FreeBytes 0 -Volumes $volumes | Should -BeNullOrEmpty
	}

	It 'creates only the missing volume without shrinking when free space is enough' {
		$volumes = @(
			New-Volume '' 'C'
			New-Volume 'data' 'D'
		)

		$plan = @(Get-PartitionPlan -Layout $layout -System (New-System 500 120) -FreeBytes (100GB) -Volumes $volumes)

		$plan.Count | Should -Be 1
		$plan[0].Action | Should -Be 'create'
		$plan[0].Label | Should -Be 'Apps & Cache'
	}

	It 'does not shrink a system volume that is already at its target size' {
		$plan = @(Get-PartitionPlan -Layout $layout -System (New-System 500 120) -FreeBytes (1406GB) -Volumes @(New-Volume '' 'C'))

		$plan.Action | Should -Not -Contain 'shrink'
		$plan.Count | Should -Be 2
	}

	It 'refuses when Windows cannot shrink the system volume far enough' {
		{ Get-PartitionPlan -Layout $layout -System (New-System 1906 600) -FreeBytes 0 -Volumes @(New-Volume '' 'C') } |
			Should -Throw '*shrink*600*'
	}

	It 'refuses when a target letter belongs to another volume' {
		$volumes = @(
			New-Volume '' 'C'
			New-Volume 'usb' 'E'
		)

		{ Get-PartitionPlan -Layout $layout -System (New-System 1906 120) -FreeBytes 0 -Volumes $volumes } |
			Should -Throw '*E:*usb*'
	}

	It 'refuses when the space left after shrinking cannot fit the new volumes' {
		{ Get-PartitionPlan -Layout $layout -System (New-System 800 120) -FreeBytes 0 -Volumes @(New-Volume '' 'C') } |
			Should -Throw '*space*'
	}
}

Describe 'Get-PartitionAction' {
	BeforeAll {
		$plan = @([pscustomobject]@{ Action = 'create'; Letter = 'E'; Label = 'Apps & Cache'; SizeBytes = $null })
	}

	It 'does nothing when the volumes already exist, whether or not the machine opted in' {
		Get-PartitionAction -Plan @() -OptedIn $false | Should -BeExactly 'nothing'
		Get-PartitionAction -Plan @() -OptedIn $true | Should -BeExactly 'nothing'
	}

	It 'refuses to change the disk when the machine has not opted in' {
		Get-PartitionAction -Plan $plan -OptedIn $false | Should -BeExactly 'refuse'
	}

	It 'applies the plan when the machine opted in' {
		Get-PartitionAction -Plan $plan -OptedIn $true | Should -BeExactly 'apply'
	}
}
