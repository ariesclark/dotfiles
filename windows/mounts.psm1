Set-StrictMode -Version Latest

function Get-AppMount {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object] $Apps,
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Selected
	)

	foreach ($app in $Apps.PSObject.Properties | Where-Object Name -in $Selected) {
		if ($app.Value.PSObject.Properties['mounts']) {
			$app.Value.mounts
		}
	}
}

function Install-Mount {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Mounts
	)

	foreach ($mount in $Mounts) {
		$from = [Environment]::ExpandEnvironmentVariables($mount.From)
		$to = $mount.To

		Repair-PathCasing -Path $to
		New-Item -ItemType Directory -Force -Path $to | Out-Null

		$existing = Get-Item -LiteralPath $from -Force -ErrorAction SilentlyContinue
		if ($existing -and $existing.LinkType -eq 'Junction') {
			if ("$($existing.Target)" -ieq $to) {
				continue
			}
			[System.IO.Directory]::Delete($from)
		}
		elseif ($existing) {
			if (Get-ChildItem -LiteralPath $from -Force | Select-Object -First 1) {
				throw "$from is a real folder with contents - move them into $to, then rerun."
			}
			[System.IO.Directory]::Delete($from)
		}
		else {
			New-Item -ItemType Directory -Force -Path (Split-Path $from) | Out-Null
		}

		New-Item -ItemType Junction -Path $from -Target $to | Out-Null
	}
}

function Repair-PathCasing {
	param([Parameter(Mandatory)] [string] $Path)

	$root = [System.IO.Path]::GetPathRoot($Path)
	$current = $root
	foreach ($segment in $Path.Substring($root.Length).Split([System.IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)) {
		$existing = Get-ChildItem -LiteralPath $current -Directory -Force -ErrorAction SilentlyContinue |
			Where-Object { $_.Name -ieq $segment } |
			Select-Object -First 1
		if (-not $existing) {
			return
		}
		if ($existing.Name -cne $segment) {
			$temporary = "$segment.casing-$([guid]::NewGuid().ToString('n'))"
			Rename-Item -LiteralPath $existing.FullName -NewName $temporary
			Rename-Item -LiteralPath (Join-Path $current $temporary) -NewName $segment
		}
		$current = Join-Path $current $segment
	}
}

Export-ModuleMember -Function Get-AppMount, Install-Mount
