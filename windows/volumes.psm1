Set-StrictMode -Version Latest

function Get-VolumeProblem {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Layout,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Volumes
	)

	foreach ($declared in $Layout.Volumes) {
		$expected = $declared.Letter.ToUpperInvariant()
		$matching = @($Volumes | Where-Object { $_.FileSystemLabel -and $_.FileSystemLabel -ieq $declared.Label })

		$problem = @{ Label = $declared.Label; Expected = $expected; Current = $null; Holder = $null }

		if ($matching.Count -eq 0) {
			[pscustomobject]($problem + @{ Kind = 'missing' })
			continue
		}

		if ($matching.Count -gt 1) {
			[pscustomobject]($problem + @{ Kind = 'duplicate-label' })
			continue
		}

		$current = "$($matching[0].DriveLetter)".ToUpperInvariant()
		if ($current -eq $expected) {
			continue
		}

		$problem.Current = $current
		$holder = $Volumes | Where-Object { "$($_.DriveLetter)" -ieq $expected } | Select-Object -First 1
		if ($holder) {
			$problem.Holder = $holder.FileSystemLabel
			[pscustomobject]($problem + @{ Kind = 'letter-taken' })
		}
		else {
			[pscustomobject]($problem + @{ Kind = 'wrong-letter' })
		}
	}
}

function Get-LabelChange {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Layout,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Volumes
	)

	$declared = @($Layout.System) + @($Layout.Volumes)
	foreach ($entry in $declared) {
		$volume = $Volumes | Where-Object { "$($_.DriveLetter)" -ieq $entry.Letter } | Select-Object -First 1
		if (-not $volume) {
			continue
		}
		if ("$($volume.FileSystemLabel)" -cne $entry.Label) {
			[pscustomobject]@{ Letter = $entry.Letter; Current = $volume.FileSystemLabel; Expected = $entry.Label }
		}
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
	$missing = @($Layout.Volumes | Where-Object {
			$label = $_.Label
			-not ($Volumes | Where-Object { $_.FileSystemLabel -and $_.FileSystemLabel -ieq $label })
		})

	if ($missing.Count -eq 0) {
		return
	}

	foreach ($declared in $missing) {
		$holder = $Volumes | Where-Object { "$($_.DriveLetter)" -ieq $declared.Letter } | Select-Object -First 1
		if ($holder) {
			throw "Cannot create '$($declared.Label)' on $($declared.Letter): - the letter belongs to '$($holder.FileSystemLabel)'."
		}
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
	$system = [pscustomobject]@{ SizeBytes = $systemPartition.Size; MinimumBytes = $minimumBytes }
	$freeBytes = (Get-Disk -Number $systemPartition.DiskNumber).LargestFreeExtent
	Get-PartitionPlan -Layout $Layout -System $system -FreeBytes $freeBytes -Volumes @(Get-Volume)
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

	$volumes = @(Get-Volume)
	$problems = @(Get-VolumeProblem -Layout $Layout -Volumes $volumes)
	foreach ($problem in $problems) {
		switch ($problem.Kind) {
			'missing' { Write-Warning "No volume labelled '$($problem.Label)'." }
			'duplicate-label' { Write-Warning "More than one volume is labelled '$($problem.Label)'." }
			'wrong-letter' { Write-Warning "'$($problem.Label)' is on $($problem.Current): but belongs on $($problem.Expected):." }
			'letter-taken' { Write-Warning "'$($problem.Label)' belongs on $($problem.Expected):, which '$($problem.Holder)' is using." }
		}
	}
	if ($problems.Count -gt 0) {
		throw 'Volumes do not match layout.yaml.'
	}

	$isAdministrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	foreach ($change in @(Get-LabelChange -Layout $Layout -Volumes $volumes)) {
		if ($isAdministrator) {
			Set-Volume -DriveLetter $change.Letter -NewFileSystemLabel $change.Expected
		}
		else {
			Write-Warning "$($change.Letter): should be labelled '$($change.Expected)' (is '$($change.Current)'). Apply as admin to fix."
		}
	}
}

Export-ModuleMember -Function Get-VolumeProblem, Get-LabelChange, Get-PartitionPlan, Invoke-PartitionPlan, Get-PartitionAction, Get-CurrentPartitionPlan, Sync-Partition, Sync-Volume
