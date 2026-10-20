Set-StrictMode -Version Latest

# The user environment variables layout.yaml declares, such as TEMP on E:.

function Get-EnvironmentChange {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Desired,
		[Parameter(Mandatory)] [hashtable] $Current
	)

	foreach ($variable in $Desired.PSObject.Properties) {
		if ("$($Current[$variable.Name])" -ine "$($variable.Value)") {
			[pscustomobject]@{ Name = $variable.Name; Value = $variable.Value }
		}
	}
}

# Sets them for the user (new processes see them; already running ones keep the old values),
# creating the folder for any value that is a path.
function Sync-Environment {
	[CmdletBinding()]
	param([Parameter(Mandatory)] [object] $Variables)

	$current = @{}
	foreach ($variable in $Variables.PSObject.Properties) {
		$current[$variable.Name] = [Environment]::GetEnvironmentVariable($variable.Name, 'User')
	}
	foreach ($change in @(Get-EnvironmentChange -Desired $Variables -Current $current)) {
		if ([System.IO.Path]::IsPathRooted($change.Value)) {
			New-Item -ItemType Directory -Force -Path $change.Value | Out-Null
		}
		[Environment]::SetEnvironmentVariable($change.Name, $change.Value, 'User')
		Write-Host "Environment: $($change.Name) = $($change.Value) (for new processes)"
	}
}

Export-ModuleMember -Function Get-EnvironmentChange, Sync-Environment
