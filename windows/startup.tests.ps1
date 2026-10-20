BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'startup.psm1') -Force

	function New-Entry([string] $Kind, [string] $Scope, [string] $Name, [bool] $Enabled = $true) {
		[pscustomobject]@{ Kind = $Kind; Scope = $Scope; Name = $Name; Enabled = $Enabled }
	}
}

Describe 'Get-StartupChange' {
	BeforeAll {
		$entries = @(
			New-Entry run user 'MicrosoftEdgeAutoLaunch_C2A503A4344B670534C2300F7564FC15'
			New-Entry run user 'RiotClient'
			New-Entry run user 'Steam'
			New-Entry run machine 'StartAUEP'
			New-Entry task machine '\StartDVR'
			New-Entry task machine '\StartCN'
		)
	}

	It 'turns off the entries it names, matching wildcards' {
		$changes = @(Get-StartupChange -Disabled @('MicrosoftEdgeAutoLaunch_*', 'RiotClient', 'StartAUEP', '\StartDVR') -Entries $entries)

		$changes.Name | Should -BeExactly @('MicrosoftEdgeAutoLaunch_C2A503A4344B670534C2300F7564FC15', 'RiotClient', 'StartAUEP', '\StartDVR')
	}

	It 'keeps each entry''s kind and scope, so machine-wide ones can be done as admin' {
		$changes = @(Get-StartupChange -Disabled @('StartAUEP', '\StartDVR', 'RiotClient') -Entries $entries)

		($changes | Where-Object Name -eq 'StartAUEP').Scope | Should -BeExactly 'machine'
		($changes | Where-Object Name -eq '\StartDVR').Kind | Should -BeExactly 'task'
		($changes | Where-Object Name -eq 'RiotClient').Scope | Should -BeExactly 'user'
	}

	It 'leaves entries that are already off alone' {
		$off = @(New-Entry run user 'RiotClient' $false)

		Get-StartupChange -Disabled @('RiotClient') -Entries $off | Should -BeNullOrEmpty
	}

	It 'ignores names that are not there, such as an app that is not installed' {
		Get-StartupChange -Disabled @('Docker Desktop') -Entries $entries | Should -BeNullOrEmpty
	}
}

Describe 'Test-LogonTrigger' {
	BeforeAll {
		function New-Trigger([string] $Class, [switch] $WithCimClass) {
			$trigger = [pscustomobject]@{}
			$trigger.PSObject.TypeNames.Insert(0, "Microsoft.Management.Infrastructure.CimInstance#Root/Microsoft/Windows/TaskScheduler/$Class")
			if ($WithCimClass) {
				$trigger | Add-Member CimClass ([pscustomobject]@{ CimClassName = $Class })
			}
			$trigger
		}
	}

	It 'knows a logon trigger by its CIM class' {
		Test-LogonTrigger (New-Trigger MSFT_TaskLogonTrigger -WithCimClass) | Should -BeTrue
	}

	It 'knows a logon trigger that arrives without its CIM class, as under winget configure' {
		Test-LogonTrigger (New-Trigger MSFT_TaskLogonTrigger) | Should -BeTrue
	}

	It 'turns down an empty trigger, which some tasks only admins see have' {
		& { Set-StrictMode -Version Latest; Test-LogonTrigger $null } | Should -BeFalse
	}

	It 'turns down other triggers' {
		Test-LogonTrigger (New-Trigger MSFT_TaskDailyTrigger -WithCimClass) | Should -BeFalse
		Test-LogonTrigger (New-Trigger MSFT_TaskBootTrigger) | Should -BeFalse
	}
}