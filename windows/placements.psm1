Set-StrictMode -Version Latest

function Install-Placement {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [object[]] $Placements
	)

	foreach ($placement in $Placements) {
		$link = [Environment]::ExpandEnvironmentVariables($placement.Link)
		$target = $placement.Target

		Repair-PathCasing -Path $target
		New-Item -ItemType Directory -Force -Path $target | Out-Null

		$existing = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
		if ($existing -and $existing.LinkType -eq 'Junction') {
			if ("$($existing.Target)" -ieq $target) {
				continue
			}
			[System.IO.Directory]::Delete($link)
		}
		elseif ($existing) {
			if (Get-ChildItem -LiteralPath $link -Force | Select-Object -First 1) {
				throw "$link is a real folder with contents - move them into $target, then rerun."
			}
			[System.IO.Directory]::Delete($link)
		}
		else {
			New-Item -ItemType Directory -Force -Path (Split-Path $link) | Out-Null
		}

		New-Item -ItemType Junction -Path $link -Target $target | Out-Null
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

Export-ModuleMember -Function Install-Placement
