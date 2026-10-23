$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot 'archive.psm1') -Force
$source = chezmoi source-path
$rootSource = Join-Path (Split-Path $PSScriptRoot) 'root'
$work = Join-Path $env:TEMP "chezmoi-archive-$PID"
$archive = Join-Path $work 'home.tar'
$rootArchive = Join-Path $work 'root.tar'
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
	chezmoi archive --format tar --output $archive
	Update-Archive -Archive $archive -Destination (Join-Path $source '.archive')
	$rootData = chezmoi execute-template '{{ includeTemplate "wsl-root-data" . }}'
	chezmoi --source $rootSource --destination (Join-Path $work 'root') --persistent-state (Join-Path $work 'root.boltdb') --override-data $rootData archive --exclude symlinks --format tar --output $rootArchive
	Update-Archive -Archive $rootArchive -Destination (Join-Path $source '.archive\root')
}
finally {
	Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
