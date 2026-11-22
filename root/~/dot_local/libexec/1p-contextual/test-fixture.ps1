$tool = $PSScriptRoot -replace '\\', '/'
$sshContextual = "sh $tool/ssh"
$signContextual = "$tool/executable_op-ssh-sign"
$sh = [IO.Path]::GetFullPath((Join-Path (git --exec-path) '..\..\..\usr\bin\sh.exe'))
$slash = [char] 0x2215
$colon = [char] 0xA789
$open = [char] 0x201C
$close = [char] 0x201D
$temp = Join-Path $TestDrive 'temp'
New-Item -ItemType Directory -Path $temp | Out-Null
$listing = Join-Path $TestDrive 'listing'
$lister = Join-Path $TestDrive 'lister.cmd'
Set-Content -LiteralPath $lister -Value @(
	'@powershell.exe -NoProfile -NonInteractive -Command "Get-ChildItem -LiteralPath (Join-Path $env:TEMP ''1p-contextual'') -Recurse -File | ForEach-Object Name | Set-Content -Encoding UTF8 -LiteralPath $env:CONTEXTUAL_LISTING"'
	'@exit /b 3'
)
$listerForSh = $lister -replace '\\', '/'
$signingKey = Join-Path $TestDrive 'signing-key'
ssh-keygen -q -t ed25519 -N '' -C '' -f $signingKey
$unresolvable = 'ssh://git@nonexistent.invalid/owner/repo.git'
$environmentBefore = @{ GIT_CONFIG_GLOBAL = $env:GIT_CONFIG_GLOBAL; GIT_CONFIG_NOSYSTEM = $env:GIT_CONFIG_NOSYSTEM; TEMP = $env:TEMP; CONTEXTUAL_LISTING = $env:CONTEXTUAL_LISTING }
$env:GIT_CONFIG_GLOBAL = 'NUL'
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:TEMP = $temp
$env:CONTEXTUAL_LISTING = $listing
$git = @(
	'-c', 'init.defaultBranch=main'
	'-c', 'user.name=Stub'
	'-c', 'user.email=stub@example.com'
	'-c', 'gpg.format=ssh'
	'-c', "gpg.ssh.program=$signContextual"
	'-c', "user.signingkey=$($signingKey -replace '\\', '/')"
)

function Restore-Environment {
	foreach ($variable in $environmentBefore.GetEnumerator()) {
		Set-Item -Path "env:$($variable.Key)" -Value $variable.Value
	}
}

function New-Checkout([string] $Name, [string] $Branch) {
	$path = Join-Path $TestDrive $Name
	git @git init --quiet $path
	git @git -C $path commit --quiet --allow-empty --message scratch
	if ($Branch) {
		git -C $path switch --quiet --create $Branch
	}
	git -C $path remote add origin https://github.com/owner/repo.git
	$path
}

function Get-Listing {
	$names = @(Get-Content -LiteralPath $listing -Encoding UTF8)
	Remove-Item -LiteralPath $listing
	$names
}

function Get-LeftBehind {
	@(Get-ChildItem -LiteralPath $temp -Recurse -File)
}

$elsewhere = New-Checkout 'elsewhere' 'claude/feature'
$namedForBranch = New-Checkout 'feature-x' 'claude/feature-x'
$namedForRepository = New-Checkout 'repo' ''
