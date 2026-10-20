BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'environment.psm1') -Force
}

Describe 'Get-EnvironmentChange' {
	BeforeAll {
		$desired = [pscustomobject]@{ TEMP = 'E:\Temp'; TMP = 'E:\Temp' }
	}

	It 'sets the variables whose value differs' {
		$current = @{ TEMP = 'C:\Users\aries\AppData\Local\Temp'; TMP = 'E:\Temp' }

		Get-EnvironmentChange -Desired $desired -Current $current | ForEach-Object Name | Should -BeExactly @('TEMP')
	}

	It 'sets variables that are not there yet' {
		$changes = @(Get-EnvironmentChange -Desired $desired -Current @{})

		$changes.Name | Should -BeExactly @('TEMP', 'TMP')
		$changes[0].Value | Should -BeExactly 'E:\Temp'
	}

	It 'changes nothing when every value matches, ignoring the case of paths' {
		Get-EnvironmentChange -Desired $desired -Current @{ TEMP = 'e:\temp'; TMP = 'E:\Temp' } | Should -BeNullOrEmpty
	}
}
