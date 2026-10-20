Set-StrictMode -Version Latest

function Get-ReadOnlyTarget {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [string] $SourceDirectory,
		[Parameter(Mandatory)] [scriptblock] $TargetPath
	)

	$root = (Resolve-Path -LiteralPath $SourceDirectory).Path.TrimEnd('\') + '\'
	$sources = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -Filter 'readonly_*' | Where-Object {
		-not ($_.FullName.Substring($root.Length).Split('\') | Select-Object -SkipLast 1 | Where-Object { $_.StartsWith('.') })
	} | ForEach-Object FullName)
	if ($sources.Count) {
		& $TargetPath $sources
	}
}

function Set-TargetReadOnly {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Path,
		[Parameter(Mandatory)] [bool] $ReadOnly
	)

	foreach ($target in $Path) {
		if (Test-Path -LiteralPath $target -PathType Leaf) {
			(Get-Item -LiteralPath $target -Force).IsReadOnly = $ReadOnly
		}
	}
}

Export-ModuleMember -Function Get-ReadOnlyTarget, Set-TargetReadOnly
