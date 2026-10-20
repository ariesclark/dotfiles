Set-StrictMode -Version Latest

# Points the Start layout policy at the taskbar layout chezmoi renders, so Windows applies its pins at sign-in.
# Policies are only writable as admin, so this asks once, and only when the policy points elsewhere.
function Set-StartLayoutPolicy {
	[CmdletBinding()]
	param([Parameter(Mandatory)] [string] $Path)

	$key = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
	$policy = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
	if ($policy -and $policy.PSObject.Properties['StartLayoutFile'] -and $policy.StartLayoutFile -eq $Path -and $policy.LockedStartLayout -eq 1) {
		return
	}
	Write-Host "Taskbar: pointing the Start layout policy at $Path (admin prompt)."
	$command = "New-Item -Path '$key' -Force | Out-Null; " +
		"Set-ItemProperty -Path '$key' -Name StartLayoutFile -Value '$Path' -Type ExpandString; " +
		"Set-ItemProperty -Path '$key' -Name LockedStartLayout -Value 1 -Type DWord"
	$process = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList '-NoProfile', '-Command', $command
	if ($process.ExitCode -ne 0) {
		throw 'Could not set the Start layout policy.'
	}
}

Export-ModuleMember -Function Set-StartLayoutPolicy
