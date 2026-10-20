BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'volumes.psm1') -Force
	$layout = '{
		"system": { "label": "System", "letter": "C", "sizeGB": 100 },
		"volumes": [
			{ "label": "Data", "letter": "D", "sizeGB": 500 },
			{ "label": "Apps", "letter": "E", "sizeGB": null }
		]
	}' | ConvertFrom-Json

	function New-Volume([string] $Label, [string] $Letter, [int] $Disk = 0) {
		[pscustomobject]@{ FileSystemLabel = $Label; DriveLetter = $Letter; DiskNumber = $Disk }
	}
}

Describe 'ConvertTo-Layout' {
	BeforeAll {
		$declared = '{
			"c": { "label": "System", "size": "100GB" },
			"e": { "label": "Apps", "size": "fill", "pagefile": "memory" },
			"d": { "label": "Data", "size": "500gb" }
		}' | ConvertFrom-Json
	}

	It 'takes Windows'' own volume from the system drive letter' {
		$converted = ConvertTo-Layout -Volumes $declared -SystemLetter 'C'

		$converted.System.Letter | Should -BeExactly 'C'
		$converted.System.Label | Should -BeExactly 'System'
		$converted.System.SizeGB | Should -Be 100
	}

	It 'reads sizes in any case, and fill as the rest of the disk, which goes last' {
		$converted = ConvertTo-Layout -Volumes $declared -SystemLetter 'c'

		$converted.Volumes.Letter | Should -BeExactly @('D', 'E')
		$converted.Volumes[0].SizeGB | Should -Be 500
		$converted.Volumes[1].SizeGB | Should -BeNullOrEmpty
		$converted.Volumes[1].Label | Should -BeExactly 'Apps'
	}

	It 'refuses more than one volume that fills the rest' {
		$two = '{ "c": { "label": "System", "size": "100GB" }, "d": { "label": "Data", "size": "fill" }, "e": { "label": "Apps", "size": "fill" } }' | ConvertFrom-Json

		{ ConvertTo-Layout -Volumes $two -SystemLetter 'C' } | Should -Throw '*fill*'
	}

	It 'refuses a size it can''t read' {
		$bad = '{ "c": { "label": "System", "size": "lots" } }' | ConvertFrom-Json

		{ ConvertTo-Layout -Volumes $bad -SystemLetter 'C' } | Should -Throw '*lots*'
	}

	It 'refuses when Windows'' own volume isn''t declared, or would fill the disk' {
		{ ConvertTo-Layout -Volumes $declared -SystemLetter 'F' } | Should -Throw '*F:*'
		$filling = '{ "c": { "label": "System", "size": "fill" } }' | ConvertFrom-Json
		{ ConvertTo-Layout -Volumes $filling -SystemLetter 'C' } | Should -Throw '*fill*'
	}
}

Describe 'Get-VolumeProblem' {
	It 'reports nothing when every letter is on Windows'' disk, whatever its label' {
		$volumes = @(
			New-Volume 'Windows' 'C'
			New-Volume 'data' 'D'
			New-Volume 'Apps & Cache' 'E'
		)

		Get-VolumeProblem -Layout $layout -Volumes $volumes -SystemDisk 0 | Should -BeNullOrEmpty
	}

	It 'reports a letter that has no volume' {
		$problems = @(Get-VolumeProblem -Layout $layout -Volumes @((New-Volume 'System' 'C'), (New-Volume 'Data' 'D')) -SystemDisk 0)

		$problems.Count | Should -Be 1
		$problems[0].Kind | Should -BeExactly 'missing'
		$problems[0].Letter | Should -BeExactly 'E'
		$problems[0].Label | Should -BeExactly 'Apps'
	}

	It 'reports a letter held by a volume on another disk' {
		$volumes = @(
			New-Volume 'System' 'C'
			New-Volume 'Data' 'D'
			New-Volume 'usb' 'E' 1
		)

		$problems = @(Get-VolumeProblem -Layout $layout -Volumes $volumes -SystemDisk 0)

		$problems.Count | Should -Be 1
		$problems[0].Kind | Should -BeExactly 'letter-taken'
		$problems[0].Letter | Should -BeExactly 'E'
		$problems[0].Holder | Should -BeExactly 'usb'
	}
}

Describe 'Get-LabelChange' {
	It 'relabels a volume whose label differs, including only in case' {
		$volumes = @(
			New-Volume 'Windows' 'C'
			New-Volume 'data' 'D'
			New-Volume 'Apps' 'E'
		)

		$changes = @(Get-LabelChange -Layout $layout -Volumes $volumes -SystemDisk 0)

		$changes.Letter | Should -BeExactly @('C', 'D')
		$changes[0].Current | Should -BeExactly 'Windows'
		$changes[0].Expected | Should -BeExactly 'System'
		$changes[1].Expected | Should -BeExactly 'Data'
	}

	It 'labels an unlabelled volume' {
		$changes = @(Get-LabelChange -Layout $layout -Volumes @((New-Volume '' 'C'), (New-Volume 'Data' 'D'), (New-Volume 'Apps' 'E')) -SystemDisk 0)

		$changes.Letter | Should -BeExactly @('C')
		$changes[0].Current | Should -BeNullOrEmpty
	}

	It 'changes nothing when every label matches exactly' {
		Get-LabelChange -Layout $layout -Volumes @((New-Volume 'System' 'C'), (New-Volume 'Data' 'D'), (New-Volume 'Apps' 'E')) -SystemDisk 0 | Should -BeNullOrEmpty
	}

	It 'leaves volumes the layout doesn''t declare alone' {
		Get-LabelChange -Layout $layout -Volumes @((New-Volume 'System' 'C'), (New-Volume 'Data' 'D'), (New-Volume 'Apps' 'E'), (New-Volume 'usb stick' 'F' 1)) -SystemDisk 0 | Should -BeNullOrEmpty
	}

	It 'never relabels a volume on another disk that holds a declared letter' {
		Get-LabelChange -Layout $layout -Volumes @((New-Volume 'System' 'C'), (New-Volume 'Data' 'D'), (New-Volume 'usb' 'E' 1)) -SystemDisk 0 | Should -BeNullOrEmpty
	}
}

Describe 'Get-PartitionPlan' {
	BeforeAll {
		function New-System([double] $SizeGB, [double] $MinimumGB) {
			[pscustomobject]@{ SizeBytes = [long]($SizeGB * 1GB); MinimumBytes = [long]($MinimumGB * 1GB); DiskNumber = 0 }
		}
	}

	It 'shrinks the system volume and creates every missing volume on a single-partition disk' {
		$plan = @(Get-PartitionPlan -Layout $layout -System (New-System 1906 60) -FreeBytes 0 -Volumes @(New-Volume '' 'C'))

		$plan.Action | Should -BeExactly @('shrink', 'create', 'create')
		$plan[0].Letter | Should -BeExactly 'C'
		$plan[0].SizeBytes | Should -Be (100GB)
		$plan[1].Letter | Should -BeExactly 'D'
		$plan[1].Label | Should -BeExactly 'Data'
		$plan[1].SizeBytes | Should -Be (500GB)
		$plan[2].Letter | Should -BeExactly 'E'
		$plan[2].Label | Should -BeExactly 'Apps'
		$plan[2].SizeBytes | Should -BeNullOrEmpty
	}

	It 'plans nothing when every letter already has a volume on Windows'' disk, even under another label' {
		$volumes = @(
			New-Volume 'Windows' 'C'
			New-Volume 'Data' 'D'
			New-Volume 'Apps & Cache' 'E'
		)

		Get-PartitionPlan -Layout $layout -System (New-System 100 60) -FreeBytes 0 -Volumes $volumes | Should -BeNullOrEmpty
	}

	It 'creates only the missing volume without shrinking when free space is enough' {
		$plan = @(Get-PartitionPlan -Layout $layout -System (New-System 100 60) -FreeBytes (100GB) -Volumes @((New-Volume 'System' 'C'), (New-Volume 'Data' 'D')))

		$plan.Action | Should -BeExactly @('create')
		$plan[0].Letter | Should -BeExactly 'E'
	}

	It 'does not shrink a system volume that is already at its target size' {
		$plan = @(Get-PartitionPlan -Layout $layout -System (New-System 100 60) -FreeBytes (1806GB) -Volumes @(New-Volume '' 'C'))

		$plan.Action | Should -BeExactly @('create', 'create')
	}

	It 'refuses when Windows cannot shrink the system volume far enough' {
		{ Get-PartitionPlan -Layout $layout -System (New-System 1906 600) -FreeBytes 0 -Volumes @(New-Volume '' 'C') } |
			Should -Throw '*shrink*600*'
	}

	It 'refuses when a target letter belongs to a volume on another disk' {
		{ Get-PartitionPlan -Layout $layout -System (New-System 1906 60) -FreeBytes 0 -Volumes @((New-Volume '' 'C'), (New-Volume 'usb' 'E' 1)) } |
			Should -Throw '*E:*usb*'
	}

	It 'refuses when the space left after shrinking cannot fit the new volumes' {
		{ Get-PartitionPlan -Layout $layout -System (New-System 550 60) -FreeBytes 0 -Volumes @(New-Volume '' 'C') } |
			Should -Throw '*space*'
	}
}

Describe 'Get-PartitionAction' {
	BeforeAll {
		$plan = @([pscustomobject]@{ Action = 'create'; Letter = 'E'; Label = 'Apps'; SizeBytes = $null })
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
