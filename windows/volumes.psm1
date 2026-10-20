Set-StrictMode -Version Latest

function ConvertFrom-Size {
	[CmdletBinding()]
	param([Parameter(Mandatory)] [string] $Size)

	if ($Size -ieq 'fill') {
		return $null
	}
	if ($Size -match '^\s*(\d+)\s*GB\s*$') {
		return [int]$Matches[1]
	}
	throw "Can't read the size '$Size'; use a number of GB like 100GB, or fill."
}

function ConvertTo-Layout {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Volumes,
		[Parameter(Mandatory)] [string] $SystemLetter
	)

	$systemLetter = $SystemLetter.TrimEnd(':').ToUpperInvariant()
	$all = foreach ($entry in $Volumes.PSObject.Properties) {
		[pscustomobject]@{ Label = $entry.Value.label; Letter = $entry.Name.ToUpperInvariant(); SizeGB = ConvertFrom-Size $entry.Value.size }
	}
	$system = $all | Where-Object Letter -eq $systemLetter
	if (-not $system) {
		throw "system.yaml declares no volume for $($systemLetter):, where Windows is."
	}
	if ($null -eq $system.SizeGB) {
		throw "Windows' own volume ($($systemLetter):) needs a size, not fill."
	}
	$others = @($all | Where-Object Letter -ne $systemLetter)
	$filling = @($others | Where-Object { $null -eq $_.SizeGB })
	if ($filling.Count -gt 1) {
		throw "Only one volume can fill the rest of the disk, not $($filling.Letter -join ', ')."
	}
	[pscustomobject]@{
		System = $system
		Volumes = @($others | Sort-Object { $null -eq $_.SizeGB }, Letter)
	}
}

function Get-VolumeProblem {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Layout,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Volumes,
		[Parameter(Mandatory)] [int] $SystemDisk
	)

	foreach ($declared in @($Layout.System) + @($Layout.Volumes)) {
		$holder = $Volumes | Where-Object { "$($_.DriveLetter)" -ieq $declared.Letter } | Select-Object -First 1
		if (-not $holder) {
			[pscustomobject]@{ Kind = 'missing'; Letter = $declared.Letter; Label = $declared.Label; Holder = $null }
		}
		elseif ($holder.DiskNumber -ne $SystemDisk) {
			[pscustomobject]@{ Kind = 'letter-taken'; Letter = $declared.Letter; Label = $declared.Label; Holder = $holder.FileSystemLabel }
		}
	}
}

function Get-LabelChange {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Layout,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Volumes,
		[Parameter(Mandatory)] [int] $SystemDisk
	)

	foreach ($entry in @($Layout.System) + @($Layout.Volumes)) {
		$volume = $Volumes | Where-Object { "$($_.DriveLetter)" -ieq $entry.Letter -and $_.DiskNumber -eq $SystemDisk } | Select-Object -First 1
		if ($volume -and "$($volume.FileSystemLabel)" -cne $entry.Label) {
			[pscustomobject]@{ Letter = $entry.Letter; Current = $volume.FileSystemLabel; Expected = $entry.Label }
		}
	}
}

function Get-CurrentVolume {
	$disks = @{}
	foreach ($partition in Get-Partition | Where-Object DriveLetter) {
		$disks["$($partition.DriveLetter)"] = $partition.DiskNumber
	}
	foreach ($volume in Get-Volume | Where-Object DriveLetter) {
		[pscustomobject]@{ FileSystemLabel = $volume.FileSystemLabel; DriveLetter = "$($volume.DriveLetter)"; DiskNumber = $disks["$($volume.DriveLetter)"] }
	}
}

function Get-PartitionPlan {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Layout,
		[Parameter(Mandatory)] [object] $System,
		[Parameter(Mandatory)] [long] $FreeBytes,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Volumes
	)

	$minimumRemainderBytes = 1GB
	$problems = @(Get-VolumeProblem -Layout ([pscustomobject]@{ System = @(); Volumes = $Layout.Volumes }) -Volumes $Volumes -SystemDisk $System.DiskNumber)
	foreach ($taken in $problems | Where-Object Kind -eq 'letter-taken') {
		throw "Cannot create '$($taken.Label)' on $($taken.Letter): - the letter belongs to '$($taken.Holder)'."
	}
	$missingLetters = @($problems | Where-Object Kind -eq 'missing' | ForEach-Object Letter)
	$missing = @($Layout.Volumes | Where-Object { $_.Letter -in $missingLetters })
	if ($missing.Count -eq 0) {
		return
	}

	$targetBytes = [long]($Layout.System.SizeGB * 1GB)
	$plan = [System.Collections.Generic.List[object]]::new()
	$availableBytes = $FreeBytes

	if ($System.SizeBytes -gt $targetBytes) {
		if ($System.MinimumBytes -gt $targetBytes) {
			$minimumGB = [math]::Ceiling($System.MinimumBytes / 1GB)
			throw "Windows can only shrink $($Layout.System.Letter): to $minimumGB GB, not $($Layout.System.SizeGB) GB."
		}
		$plan.Add([pscustomobject]@{ Action = 'shrink'; Letter = $Layout.System.Letter; Label = $null; SizeBytes = $targetBytes })
		$availableBytes += $System.SizeBytes - $targetBytes
	}

	$neededBytes = 0
	foreach ($declared in $missing) {
		$neededBytes += if ($declared.SizeGB) { [long]($declared.SizeGB * 1GB) } else { $minimumRemainderBytes }
	}
	if ($availableBytes -lt $neededBytes) {
		throw ('Not enough space: the new volumes need {0:N0} GB but only {1:N0} GB is free after shrinking.' -f ($neededBytes / 1GB), ($availableBytes / 1GB))
	}

	foreach ($declared in $missing) {
		$sizeBytes = if ($declared.SizeGB) { [long]($declared.SizeGB * 1GB) } else { $null }
		$plan.Add([pscustomobject]@{ Action = 'create'; Letter = $declared.Letter; Label = $declared.Label; SizeBytes = $sizeBytes })
	}

	$plan
}

function Invoke-PartitionPlan {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory)] [object[]] $Plan,
		[Parameter(Mandatory)] [int] $DiskNumber
	)

	foreach ($step in $Plan) {
		switch ($step.Action) {
			'shrink' {
				if ($PSCmdlet.ShouldProcess("$($step.Letter):", "shrink to $($step.SizeBytes / 1GB) GB")) {
					Resize-Partition -DriveLetter $step.Letter -Size $step.SizeBytes
				}
			}
			'create' {
				$size = if ($step.SizeBytes) { "$($step.SizeBytes / 1GB) GB" } else { 'the remaining space' }
				if ($PSCmdlet.ShouldProcess("disk $DiskNumber", "create '$($step.Label)' as $($step.Letter): using $size")) {
					$partition = if ($step.SizeBytes) {
						New-Partition -DiskNumber $DiskNumber -Size $step.SizeBytes -DriveLetter $step.Letter
					}
					else {
						New-Partition -DiskNumber $DiskNumber -UseMaximumSize -DriveLetter $step.Letter
					}
					$partition | Format-Volume -FileSystem NTFS -NewFileSystemLabel $step.Label -Confirm:$false | Out-Null
				}
			}
		}
	}
}

function Get-PartitionAction {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan,
		[Parameter(Mandatory)] [bool] $OptedIn
	)

	if ($Plan.Count -eq 0) {
		return 'nothing'
	}
	if (-not $OptedIn) {
		return 'refuse'
	}
	'apply'
}

function Get-CurrentPartitionPlan {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Layout,
		[switch] $CheckMinimum
	)

	$systemPartition = Get-Partition -DriveLetter $Layout.system.letter
	$minimumBytes = if ($CheckMinimum) { (Get-PartitionSupportedSize -DriveLetter $Layout.system.letter).SizeMin } else { 0 }
	$system = [pscustomobject]@{ SizeBytes = $systemPartition.Size; MinimumBytes = $minimumBytes; DiskNumber = $systemPartition.DiskNumber }
	$freeBytes = (Get-Disk -Number $systemPartition.DiskNumber).LargestFreeExtent
	Get-PartitionPlan -Layout $Layout -System $system -FreeBytes $freeBytes -Volumes @(Get-CurrentVolume)
}

function Write-PartitionPlan {
	param([object[]] $Plan)

	Write-Host 'Partition plan:'
	foreach ($step in $Plan) {
		$size = if ($step.SizeBytes) { '{0:N0} GB' -f ($step.SizeBytes / 1GB) } else { 'the rest' }
		switch ($step.Action) {
			'shrink' { Write-Host "  shrink $($step.Letter): to $size" }
			'create' { Write-Host "  create $($step.Letter): '$($step.Label)' with $size (NTFS)" }
		}
	}
}

function Sync-Partition {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Layout,
		[Parameter(Mandatory)] [bool] $OptedIn
	)

	$plan = @(Get-CurrentPartitionPlan -Layout $Layout)
	switch (Get-PartitionAction -Plan $plan -OptedIn $OptedIn) {
		'nothing' {
			return
		}
		'refuse' {
			Write-PartitionPlan -Plan $plan
			throw 'Volumes are missing. To let apply create them, set machine.partition to true (chezmoi edit-config), then apply again.'
		}
		'apply' {
			Write-PartitionPlan -Plan $plan
			$id = [guid]::NewGuid().ToString('n')
			$layoutFile = Join-Path $env:TEMP "partition-layout-$id.json"
			$logFile = Join-Path $env:TEMP "partition-$id.log"
			$Layout | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $layoutFile -Encoding utf8

			$command = "Start-Transcript -LiteralPath '$logFile' | Out-Null; try { Import-Module '$PSCommandPath' -Force; " +
				"`$layout = Get-Content -LiteralPath '$layoutFile' -Raw | ConvertFrom-Json; " +
				"`$plan = @(Get-CurrentPartitionPlan -Layout `$layout -CheckMinimum); " +
				"if (`$plan.Count -gt 0) { Invoke-PartitionPlan -Plan `$plan -DiskNumber (Get-Partition -DriveLetter `$layout.system.letter).DiskNumber } " +
				"} catch { Write-Host `$_; exit 1 } finally { Stop-Transcript | Out-Null }"
			$shell = (Get-Process -Id $PID).Path
			$process = Start-Process -FilePath $shell -Verb RunAs -Wait -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command

			if (Test-Path -LiteralPath $logFile) {
				Get-Content -LiteralPath $logFile | Write-Host
				Remove-Item -LiteralPath $logFile
			}
			Remove-Item -LiteralPath $layoutFile
			if ($process.ExitCode -ne 0 -or @(Get-CurrentPartitionPlan -Layout $Layout).Count -gt 0) {
				throw 'Partitioning did not finish; the volumes are still missing. See the output above.'
			}
		}
	}
}

function Sync-Volume {
	[CmdletBinding()]
	param([Parameter(Mandatory)] [object] $Layout)

	$volumes = @(Get-CurrentVolume)
	$systemDisk = (Get-Partition -DriveLetter $Layout.System.Letter).DiskNumber
	$problems = @(Get-VolumeProblem -Layout $Layout -Volumes $volumes -SystemDisk $systemDisk)
	foreach ($problem in $problems) {
		switch ($problem.Kind) {
			'missing' { Write-Warning "No volume on $($problem.Letter): for '$($problem.Label)'." }
			'letter-taken' { Write-Warning "$($problem.Letter): belongs to '$($problem.Label)', but '$($problem.Holder)' on another disk is using it." }
		}
	}
	if ($problems.Count -gt 0) {
		throw 'Volumes do not match system.yaml.'
	}

	$isAdministrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	foreach ($change in @(Get-LabelChange -Layout $Layout -Volumes $volumes -SystemDisk $systemDisk)) {
		if ($isAdministrator) {
			Set-Volume -DriveLetter $change.Letter -NewFileSystemLabel $change.Expected
		}
		else {
			Write-Warning "$($change.Letter): should be labelled '$($change.Expected)' (is '$($change.Current)'). Apply as admin to fix."
		}
	}
}

Export-ModuleMember -Function ConvertFrom-Size, ConvertTo-Layout, Get-VolumeProblem, Get-LabelChange, Get-PartitionPlan, Invoke-PartitionPlan, Get-PartitionAction, Get-CurrentPartitionPlan, Sync-Partition, Sync-Volume
