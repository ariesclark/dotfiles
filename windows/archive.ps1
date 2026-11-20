$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Import-Module (Join-Path $PSScriptRoot 'archive.psm1') -Force
$source = chezmoi source-path
$repository = Split-Path $PSScriptRoot
$rootSource = Join-Path $repository 'root'
$distribution = chezmoi execute-template '{{ .system.wsl.distribution }}'
$user = chezmoi execute-template '{{ .system.wsl.user }}'
function ConvertTo-LinuxPath([string] $Path) {
	wsl.exe -d $distribution --exec wslpath -u $Path
}
$work = Join-Path $env:TEMP "chezmoi-archive-$PID"
$linuxWork = "/tmp/chezmoi-archive-$PID"
$archive = Join-Path $work 'home.tar'
$rootArchive = Join-Path $work 'root.tar'
$wslHomeArchive = Join-Path $work 'wsl-home.tar'
$rootData = Join-Path $work 'root-data.json'
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
	chezmoi archive --format tar --output $archive
	Update-Archive -Archive $archive -Destination (Join-Path $source '.archive')
	chezmoi execute-template '{{ includeTemplate "wsl-root-data" . }}' | Set-Content -LiteralPath $rootData -NoNewline
	wsl.exe -d $distribution --exec chezmoi --source (ConvertTo-LinuxPath $rootSource) --destination "$linuxWork/root" --persistent-state "$linuxWork/root.boltdb" --override-data-file (ConvertTo-LinuxPath $rootData) archive --exclude symlinks --format tar --output (ConvertTo-LinuxPath $rootArchive)
	Update-Archive -Archive $rootArchive -Destination (Join-Path $source '.archive\root')
	wsl.exe -d $distribution -u $user --exec chezmoi --source (ConvertTo-LinuxPath $repository) --persistent-state "$linuxWork/wsl-home.boltdb" archive --exclude symlinks --format tar --output (ConvertTo-LinuxPath $wslHomeArchive)
	Update-Archive -Archive $wslHomeArchive -Destination (Join-Path $source '.archive\wsl-home')
}
finally {
	Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
	wsl.exe -d $distribution --exec rm -rf $linuxWork
}
