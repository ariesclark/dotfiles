Set-StrictMode -Version Latest

# home/.archive/ from one chezmoi archive: every managed file as it lands under ~, and .chezmoiscripts/ with every
# script. It's built beside the old one and swapped in, so a failed build leaves the old one.
function Update-Archive {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)] [string] $Archive,
		[Parameter(Mandatory)] [string] $Destination
	)

	if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) {
		throw "No archive at $Archive."
	}
	$staging = "$Destination.new"
	if (Test-Path -LiteralPath $staging) {
		Remove-Item -LiteralPath $staging -Recurse -Force
	}
	try {
		New-Item -ItemType Directory -Force -Path $staging | Out-Null
		tar -xf $Archive -C $staging
		if ($LASTEXITCODE) {
			throw "tar couldn't unpack $Archive."
		}
		if (Test-Path -LiteralPath $Destination) {
			Remove-Item -LiteralPath $Destination -Recurse -Force
		}
		Move-Item -LiteralPath $staging -Destination $Destination
	}
	finally {
		if (Test-Path -LiteralPath $staging) {
			Remove-Item -LiteralPath $staging -Recurse -Force
		}
	}
}

Export-ModuleMember -Function Update-Archive
