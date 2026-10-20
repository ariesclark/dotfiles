Set-StrictMode -Version Latest

# What starts with Windows that desktop.yaml turns off. Run entries get Settings > Startup's "disabled" flag
# (StartupApproved), so an app that re-adds its entry stays off; logon tasks get disabled.

$runKeys = @(
	@{ Scope = 'user'; Run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
	@{ Scope = 'machine'; Run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
	@{ Scope = 'machine'; Run = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
)

function Get-StartupEntry {
	foreach ($key in $runKeys) {
		$run = Get-ItemProperty -Path $key.Run -ErrorAction SilentlyContinue
		if (-not $run) {
			continue
		}
		$approved = Get-ItemProperty -Path $key.Approved -ErrorAction SilentlyContinue
		foreach ($value in $run.PSObject.Properties | Where-Object Name -notlike 'PS*') {
			$flag = if ($approved -and $approved.PSObject.Properties[$value.Name]) { $approved.($value.Name)[0] } else { 2 }
			[pscustomobject]@{ Kind = 'run'; Scope = $key.Scope; Name = $value.Name; Enabled = ($flag % 2 -eq 0); Approved = $key.Approved }
		}
	}
	foreach ($task in Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }) {
		if ($task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }) {
			[pscustomobject]@{ Kind = 'task'; Scope = 'machine'; Name = "$($task.TaskPath)$($task.TaskName)"; Enabled = ($task.State -ne 'Disabled'); Approved = $null }
		}
	}
}

function Get-StartupChange {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Disabled,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Entries
	)

	foreach ($entry in $Entries) {
		if ($entry.Enabled -and @($Disabled | Where-Object { $entry.Name -like $_ }).Count -gt 0) {
			$entry
		}
	}
}

function Sync-Startup {
	[CmdletBinding()]
	param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Disabled)

	$changes = @(Get-StartupChange -Disabled $Disabled -Entries @(Get-StartupEntry))
	# 0x03 followed by zeros is what Settings > Startup writes for "off".
	$off = [byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
	foreach ($change in $changes | Where-Object Scope -eq 'user') {
		New-Item -Path $change.Approved -Force -ErrorAction SilentlyContinue | Out-Null
		Set-ItemProperty -Path $change.Approved -Name $change.Name -Value $off -Type Binary
		Write-Host "Startup: turned off $($change.Name)."
	}

	$machine = @($changes | Where-Object Scope -eq 'machine')
	if ($machine.Count -eq 0) {
		return
	}
	# Machine-wide entries need admin: one prompt for all of them.
	Write-Host "Startup: turning off $(($machine.Name) -join ', ') (admin prompt)."
	$commands = foreach ($change in $machine) {
		if ($change.Kind -eq 'task') {
			$path = $change.Name.Substring(0, $change.Name.LastIndexOf('\') + 1)
			$name = $change.Name.Substring($change.Name.LastIndexOf('\') + 1)
			"Disable-ScheduledTask -TaskPath '$path' -TaskName '$name' | Out-Null"
		}
		else {
			"New-Item -Path '$($change.Approved)' -Force -ErrorAction SilentlyContinue | Out-Null; Set-ItemProperty -Path '$($change.Approved)' -Name '$($change.Name)' -Value ([byte[]](3,0,0,0,0,0,0,0,0,0,0,0)) -Type Binary"
		}
	}
	$process = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList '-NoProfile', '-Command', ($commands -join '; ')
	if ($process.ExitCode -ne 0) {
		throw 'Could not turn off the machine-wide startup entries.'
	}
}

Export-ModuleMember -Function Get-StartupEntry, Get-StartupChange, Sync-Startup
