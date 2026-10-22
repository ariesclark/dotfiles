$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'archive.psm1') -Force
$source = chezmoi source-path
$archive = Join-Path $env:TEMP "chezmoi-archive-$PID.tar"
try {
	chezmoi archive --format tar --output $archive
	if ($LASTEXITCODE) {
		throw 'chezmoi archive failed.'
	}
	Update-Archive -Archive $archive -Destination (Join-Path $source '.archive')
}
finally {
	Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
}
