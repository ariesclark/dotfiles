$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot 'archive.psm1') -Force
$repository = Split-Path $PSScriptRoot
$source = chezmoi --source $repository source-path
$distribution = chezmoi --source $repository execute-template '{{ .system.wsl.distribution }}'
$user = chezmoi --source $repository execute-template '{{ .system.wsl.user }}'
function ConvertTo-LinuxPath([string] $Path) {
	wsl.exe -d $distribution --exec wslpath -u $Path
}
$work = Join-Path $env:TEMP "chezmoi-archive-$PID"
$linuxWork = "/tmp/chezmoi-archive-$PID"
$archive = Join-Path $work 'home.tar'
$wslArchive = Join-Path $work 'wsl.tar'
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
	chezmoi --source $repository archive --format tar --output $archive
	Update-Archive -Archive $archive -Destination (Join-Path $source '.archive')
	wsl.exe -d $distribution -u $user --exec chezmoi --source (ConvertTo-LinuxPath $repository) --destination / --persistent-state "$linuxWork/state.boltdb" archive --exclude symlinks --format tar --output (ConvertTo-LinuxPath $wslArchive)
	Update-Archive -Archive $wslArchive -Destination (Join-Path $source '.archive\wsl')
}
finally {
	Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
	wsl.exe -d $distribution --exec rm -rf $linuxWork
}
