BeforeAll {
	$source = Split-Path $PSScriptRoot
	$mockSigningKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockSigningKeyFromTheOpStub'
	$mockPushKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockPushKeyFromTheOpStub'
	$mockEmail = 'stub@example.com'
	$opStubSecrets = [ordered]@{
		'op://personal/rczscaa2ex5o5gqxuoo5aa6xmu/public key' = $mockSigningKey
		'op://personal/x5widjpc2mp6hr3xci4dkvbvz4/public key' = $mockPushKey
		'op://personal/6enz7r76cvm7nq3gac2xckcxke/Identification/first name' = 'Stub'
		'op://personal/6enz7r76cvm7nq3gac2xckcxke/Identification/last name' = 'Person'
		'op://personal/6enz7r76cvm7nq3gac2xckcxke/Internet Details/email' = $mockEmail
		'op://personal/6enz7r76cvm7nq3gac2xckcxke/Internet Details/website' = 'https://example.com'
	}
	$opStubForWindows = Join-Path $TestDrive 'op.cmd'
	Set-Content -LiteralPath $opStubForWindows -Value @(
		'@echo off'
		'if "%~1 %~2"=="signin --raw" ('
		'	echo mock-session'
		'	exit /b 0'
		')'
		foreach ($secret in $opStubSecrets.GetEnumerator()) {
			"if `"%~1 %~2 %~3 %~4 %~5`"==`"--session mock-session read --no-newline $($secret.Key)`" ("
			"	<nul set /p=`"$($secret.Value)`""
			'	exit /b 0'
			')'
		}
		'echo op stub: unexpected arguments: %* 1>&2'
		'exit /b 1'
	)
	$opStubForLinux = Join-Path $TestDrive 'op'
	Set-Content -LiteralPath $opStubForLinux -NoNewline -Value (@(
		'#!/bin/sh'
		'case "$*" in'
		"'signin --raw') echo mock-session ;;"
		foreach ($secret in $opStubSecrets.GetEnumerator()) {
			"'--session mock-session read --no-newline $($secret.Key)') printf '%s' '$($secret.Value)' ;;"
		}
		'*) echo "op stub: unexpected arguments: $*" >&2; exit 1 ;;'
		'esac'
		''
	) -join "`n")
	$configWithOpStub = Join-Path $TestDrive 'chezmoi.json'
	$liveConfig = chezmoi dump-config --format json | ConvertFrom-Json
	$liveConfig.onepassword.command = $opStubForWindows
	$liveConfig | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configWithOpStub
	$archive = Join-Path $TestDrive 'target.tar'
	$rendered = Join-Path $TestDrive 'rendered'
	New-Item -ItemType Directory -Force -Path $rendered | Out-Null
	chezmoi --config $configWithOpStub --source $source archive --format tar --output $archive
	if ($LASTEXITCODE) {
		throw 'chezmoi could not render the repo.'
	}
	tar -xf $archive -C $rendered
	function Render([string] $Target) {
		(Get-Content -LiteralPath (Join-Path $rendered $Target)) -join "`n"
	}
	$reg = Render '.config\windows\user.reg'
	function Get-RegistrySection([string] $Key) {
		$lines = $reg -split "`n"
		$start = [array]::IndexOf($lines, "[$Key]")
		if ($start -lt 0) {
			return
		}
		$lines | Select-Object -Skip ($start + 1) | ForEach-Object -Begin { $open = $true } -Process {
			if ($_ -eq '' -or $_.StartsWith('[')) { $open = $false }
			if ($open) { $_ }
		}
	}
}

Describe 'generated label' {
	BeforeDiscovery {
		$repository = Split-Path $PSScriptRoot
		$targets = @(chezmoi --source $repository managed --include files --path-style absolute | ForEach-Object {
			$target = [System.IO.Path]::GetFullPath($_)
			@{ Target = $target; Leaf = Split-Path $target -Leaf }
		})
	}

	BeforeAll {
		$repository = Split-Path $PSScriptRoot
	}

	It 'opens <Leaf> with the source file to change instead, in its own comment syntax' -ForEach @($targets | Where-Object { $_.Target -notlike '*.json' }) {
		$sourceFile = if ($Target -like '*\GitHub CLI\config.yml') { Join-Path $repository 'root\~\(eq .chezmoi.os `linux`)\dot_config\gh\config.yml.tmpl' } else { [System.IO.Path]::GetFullPath((chezmoi --source $repository source-path $Target)) }
		$label = 'This file is managed by Chezmoi. To change it, update:', $sourceFile
		$expected = switch -Wildcard ($Target) {
			'*.reg' { $label | ForEach-Object { "; $_" } }
			'*.xml' { @('<!--') + $label + '-->' }
			'*.md' { @('<!--') + $label + '-->' }
			default { $label | ForEach-Object { "# $_" } }
		}
		$lines = @((Render $Target.Substring($HOME.Length + 1)) -split "`n")
		$first = if ($lines[0] -eq '---') { [array]::IndexOf($lines, '---', 1) + 1 } elseif ($lines[0] -match '^(#!|<\?xml |Windows Registry Editor )') { 1 } else { 0 }
		$lines[$first..($first + $expected.Count - 1)] | Should -BeExactly $expected
	}

	It 'leaves <Leaf> as plain JSON, which has no comments' -ForEach @($targets | Where-Object { $_.Target -like '*.json' }) {
		$json = Render $Target.Substring($HOME.Length + 1)
		$json | Should -Not -Match 'managed by Chezmoi'
		{ $json | ConvertFrom-Json -AsHashtable } | Should -Not -Throw
	}

	It 'labels the files this machine skips too' {
		$sourceRoot = Join-Path $repository 'root'
		$sources = Get-ChildItem -Recurse -File -Force $sourceRoot | Where-Object {
			$folders = [System.IO.Path]::GetRelativePath($sourceRoot, $_.DirectoryName).Split([System.IO.Path]::DirectorySeparatorChar)
			-not ($folders | Where-Object { $_.StartsWith('.') -and $_ -ne '.' }) -and
			$_.Name -notlike 'modify_*' -and $_.Name -notlike '*.json.tmpl' -and $_.Name -notlike 'run_*' -and $_.Name -notlike 'symlink_*' -and $_.Name -notlike '.chezmoi*' -and $_.Name -ne 'settings.yaml' -and $_.FullName -notlike '*\GitHub CLI\config.yml.tmpl'
		}
		$sources.Count | Should -BeGreaterThan 10
		$sources | Where-Object { (Get-Content -Raw $_.FullName) -notmatch '\{\{-? includeTemplate "generated" \. -?\}\}' } | ForEach-Object Name | Should -BeNullOrEmpty
	}
}

Describe 'user.reg' {
	It 'is a registry file reg import accepts' {
		($reg -split "`n")[0] | Should -BeExactly 'Windows Registry Editor Version 5.00'
	}

	It 'starts installed Scoop apps from their current folder, quoting the path and escaping backslashes' {
		$reg | Should -Match '(?m)^"ShareX"="\\"E:\\\\Scoop\\\\apps\\\\sharex\\\\current\\\\ShareX\.exe\\" -silent"$'
	}

	It 'keeps absolute startup paths as they are' {
		$reg | Should -Match '(?m)^"WallpaperEngine"="\\"E:\\\\Games\\\\Steam\\\\common\\\\wallpaper_engine\\\\wallpaper64\.exe\\" -silent"$'
	}

	It 'registers URL handlers under the user''s classes' {
		$reg | Should -Match '(?m)^\[HKEY_CURRENT_USER\\Software\\Classes\\steam\\Shell\\Open\\Command\]$'
		$reg | Should -Match '(?m)^"URL Protocol"=""$'
	}

	It 'maps the WSL distribution to its drive letter through the Plan 9 provider, so sign-in restores it' {
		Get-RegistrySection 'HKEY_CURRENT_USER\Network\W' | Should -BeExactly @(
			'"RemotePath"="\\\\wsl.localhost\\Ubuntu"'
			'"UserName"=dword:00000000'
			'"ProviderName"="Plan 9 Network Provider"'
			'"ProviderType"=dword:00480000'
			'"ConnectionType"=dword:00000001'
			'"DeferFlags"=dword:00000004'
		)
	}

	It 'ticks every volume and the WSL drive in the WinDirStat drive picker' {
		Get-RegistrySection 'HKEY_CURRENT_USER\Software\WinDirStat\WinDirStat\DriveSelect' | Should -BeExactly @(
			'"SelectDrivesRadio"=dword:00000001'
			'"SelectDrivesDrives"="C:|D:|E:|W:"'
		)
	}

}

Describe 'WSL root' {
	BeforeAll {
		$repository = Split-Path $PSScriptRoot
		$linuxGroup = Join-Path $repository 'root\(eq .chezmoi.os `linux`)'
		$rootArchive = Join-Path $TestDrive 'root.tar'
		$rootRendered = Join-Path $TestDrive 'root-rendered'
		New-Item -ItemType Directory -Force -Path $rootRendered | Out-Null
		$rootWork = "/tmp/chezmoi-root-test-$PID"
		$linuxPaths = @($repository, $rootArchive | ForEach-Object { wsl.exe -d Ubuntu -u aries --exec wslpath -u $_ })
		wsl.exe -d Ubuntu -u aries --exec chezmoi --source $linuxPaths[0] --destination / --persistent-state "$rootWork/state.boltdb" archive --format tar --output $linuxPaths[1] /etc /var
		if ($LASTEXITCODE) {
			throw 'chezmoi could not render / inside WSL.'
		}
		wsl.exe -d Ubuntu -u aries --exec rm -rf $rootWork
		tar -xf $rootArchive -C $rootRendered 2> $null
		function Get-RootSetting([string] $Target) {
			@((Get-Content -LiteralPath (Join-Path $rootRendered $Target)) | Where-Object { $_ -and -not $_.StartsWith('#') })
		}
	}

	It 'trusts only GitHub CLI''s current signing key for its apt repository' {
		$sources = Get-RootSetting 'etc\apt\sources.list.d\github-cli.sources'
		$sources[4] | Should -BeExactly 'Signed-By:'
		$key = ($sources | Select-Object -Skip 5 | ForEach-Object { $_.Substring(1) -replace '^\.$', '' }) -join "`n"
		$key | Should -Match '^-----BEGIN PGP PUBLIC KEY BLOCK-----'
		$fingerprints = @($key | wsl.exe -d Ubuntu -u aries --exec gpg --show-keys --with-colons 2> $null | Where-Object { $_ -like 'fpr:*' } | ForEach-Object { $_.Split(':')[9] })
		$fingerprints[0] | Should -BeExactly '7F38BBB59D064DBCB3D84D725612B36462313325'
		@(($key | wsl.exe -d Ubuntu -u aries --exec gpg --show-keys --with-colons 2> $null) | Where-Object { $_ -like 'pub:*' }).Count | Should -Be 1
	}

	It 'reruns the wsl.conf script when the rendered wsl.conf changes, also through data, and only then' {
		function Get-ScriptHash([hashtable] $Wsl) {
			$data = @{ system = @{ wsl = $Wsl } } | ConvertTo-Json -Depth 5 -Compress
			@((chezmoi --source $repository --override-data $data execute-template --file (Join-Path $linuxGroup 'etc\run_onchange_after_wsl.conf.sh.tmpl')) -split "`n")[1]
		}
		function Get-DeclaredWsl {
			(chezmoi --source $repository execute-template '{{ .system.wsl | toJson }}') -join "`n" | ConvertFrom-Json -AsHashtable
		}
		$withUser = Get-DeclaredWsl
		$withUser.user = 'someone'
		$withPackage = Get-DeclaredWsl
		$withPackage.packages += 'htop'

		$original = Get-ScriptHash (Get-DeclaredWsl)
		$original | Should -Match '^# [0-9a-f]{64}$'
		Get-ScriptHash $withUser | Should -Not -Be $original
		Get-ScriptHash $withPackage | Should -Be $original
	}
	It 'names every run_onchange_after script after a file next to it' {
		$scripts = @(Get-ChildItem (Join-Path $repository 'root') -Recurse -File -Filter 'run_onchange_after_*' | Where-Object { $_.FullName -notmatch '\\\.(archive|chezmoiscripts)\\' })
		$scripts.Count | Should -BeGreaterThan 5
		$unmatched = foreach ($script in $scripts) {
			$watched = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($script.Name.Substring('run_onchange_after_'.Length)))
			$candidates = "readonly_$watched.tmpl", "$watched.tmpl", "readonly_$watched", $watched
			if (-not ($candidates | Where-Object { Test-Path -LiteralPath (Join-Path $script.DirectoryName $_) })) {
				$script.Name
			}
		}
		$unmatched | Should -BeNullOrEmpty
	}
}

Describe 'WSL memory limits' {
	BeforeAll {
		$repository = Split-Path $PSScriptRoot
		$linuxGroup = Join-Path $repository 'root\(eq .chezmoi.os `linux`)'
		$memoryMB = [math]::Floor((Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1MB)
		function Get-Setting([string[]] $Lines) {
			@($Lines | Where-Object { $_ -and -not $_.StartsWith('#') })
		}
		function Render-WslConfig([string] $Memory, [string] $Swap) {
			$data = @{ system = @{ wsl = @{ memory = $Memory; swap = $Swap } } } | ConvertTo-Json -Depth 5 -Compress
			Get-Setting (chezmoi --source $repository --override-data $data execute-template --file (Join-Path $repository 'root\~\(eq .chezmoi.os `windows`)\dot_wslconfig.tmpl') 2>&1 | ForEach-Object { "$_" })
		}
		function Render-DockerLimit([string] $DropIn, [hashtable] $Docker) {
			$data = @{ system = @{ wsl = @{ docker = $Docker } } } | ConvertTo-Json -Depth 5 -Compress
			Get-Setting (chezmoi --source $repository --override-data $data execute-template --file (Join-Path $linuxGroup "var\lib\dockerd\dot_config\systemd\user\$DropIn\memory.conf.tmpl") 2>&1 | ForEach-Object { "$_" })
		}
	}

	It 'gives the VM and its swap a percent of the Windows memory, rounded down to whole GB' {
		Render-WslConfig '40%' '25%' | Should -BeExactly @(
			'[wsl2]'
			"memory=$([math]::Floor($memoryMB * 0.4 / 1024))GB"
			"swap=$([math]::Floor($memoryMB * 0.25 / 1024))GB"
			'swapFile=E:\\WSL\\swap.vhdx'
			'loadKernelModules=zram'
			'[experimental]'
			'sparseVhd=true'
		)
	}

	It 'takes a size in GB as given' {
		Render-WslConfig '12GB' '4GB' | Select-Object -Index 1, 2 | Should -BeExactly @('memory=12GB', 'swap=4GB')
	}

	It 'leaves the memory and the swap to WSL for auto' {
		Render-WslConfig 'auto' 'auto' | Should -BeExactly @('[wsl2]', 'swapFile=E:\\WSL\\swap.vhdx', 'loadKernelModules=zram', '[experimental]', 'sparseVhd=true')
	}

	It 'refuses a percent that comes to less than 1 GB' {
		(Render-WslConfig '1%' '4GB') -join "`n" | Should -Match "The memory value '1%' comes to less than 1GB"
	}

	It 'refuses a WSL memory value it can''t read' {
		(Render-WslConfig 'huge' '4GB') -join "`n" | Should -Match "Can't read the memory value 'huge'"
	}

	It 'passes a memory percent to systemd, which takes it of the VM memory' {
		Render-DockerLimit 'user.slice.d' @{ memory = '66.67%'; swap = '2GB'; container = @{ memory = 'auto'; swap = 'auto' } } | Should -BeExactly @('[Slice]', 'MemoryMax=66.67%', 'MemorySwapMax=2G')
	}

	It 'refuses a swap percent, which systemd 259 takes of the memory instead of the swap' {
		(Render-DockerLimit 'user.slice.d' @{ memory = 'auto'; swap = '25%'; container = @{ memory = 'auto'; swap = 'auto' } }) -join "`n" | Should -Match "Can't read the swap value '25%'; use a size like 2GB, or auto\."
	}

	It 'gives each container a size in systemd''s units' {
		Render-DockerLimit 'docker-.scope.d' @{ memory = 'auto'; swap = 'auto'; container = @{ memory = '4GB'; swap = '1GB' } } | Should -BeExactly @('[Scope]', 'MemoryMax=4G', 'MemorySwapMax=1G')
	}

	It 'takes a container percent of the percent for all containers' {
		Render-DockerLimit 'docker-.scope.d' @{ memory = '50%'; swap = 'auto'; container = @{ memory = '25%'; swap = '1GB' } } | Should -BeExactly @('[Scope]', 'MemoryMax=12.5%', 'MemorySwapMax=1G')
	}

	It 'takes a container percent of the size for all containers' {
		Render-DockerLimit 'docker-.scope.d' @{ memory = '8GB'; swap = 'auto'; container = @{ memory = '25%'; swap = 'auto' } } | Should -BeExactly @('[Scope]', 'MemoryMax=2048M')
	}

	It 'takes a container percent of the VM memory when all containers have no limit' {
		Render-DockerLimit 'docker-.scope.d' @{ memory = 'auto'; swap = 'auto'; container = @{ memory = '25%'; swap = 'auto' } } | Should -BeExactly @('[Scope]', 'MemoryMax=25%')
	}

	It 'sets no container limit for auto' {
		Render-DockerLimit 'docker-.scope.d' @{ memory = '8GB'; swap = '2GB'; container = @{ memory = 'auto'; swap = 'auto' } } | Should -BeExactly @('[Scope]')
	}

	It 'refuses a container memory value it can''t read' {
		(Render-DockerLimit 'user.slice.d' @{ memory = 'lots'; swap = 'auto'; container = @{ memory = 'auto'; swap = 'auto' } }) -join "`n" | Should -Match "Can't read the memory value 'lots'"
	}
}

Describe 'WSL home' {
	BeforeAll {
		$work = "/tmp/chezmoi-home-test-$PID"
		$homeRendered = "$work/rendered"
		$checkout = wsl.exe -d Ubuntu -u aries --exec wslpath -u (Split-Path $PSScriptRoot)
		wsl.exe -d Ubuntu -u aries --exec sh -c "set -eu; mkdir -p $homeRendered; chezmoi --source $checkout execute-template --init --file $checkout/root/.chezmoi.yaml.tmpl < /dev/null > $work/chezmoi.yaml"
		$config = (wsl.exe -d Ubuntu -u aries --exec chezmoi --config "$work/chezmoi.yaml" dump-config --format json) -join "`n" | ConvertFrom-Json
		$withOpStub = (wsl.exe -d Ubuntu -u aries --exec chezmoi --config "$work/chezmoi.yaml" dump-config --format json) -join "`n" | ConvertFrom-Json
		$withOpStub.onepassword.command = "$work/op"
		$withOpStub | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $TestDrive 'chezmoi-linux.json')
		$stubs = wsl.exe -d Ubuntu -u aries --exec wslpath -u $TestDrive
		wsl.exe -d Ubuntu -u aries --exec sh -c "set -eu; cp $stubs/op $work/op; chmod +x $work/op; chezmoi --config $stubs/chezmoi-linux.json --persistent-state $work/state.boltdb archive --format tar --output $work/home.tar; tar -xf $work/home.tar -C $homeRendered"
		if ($LASTEXITCODE) {
			throw 'chezmoi could not render ~ inside WSL.'
		}
		$listing = @(wsl.exe -d Ubuntu -u aries --exec tar -tvf "$work/home.tar")
		function Render-Home([string] $Target) {
			(wsl.exe -d Ubuntu -u aries --exec cat "$homeRendered/$Target") -join "`n"
		}
	}

	AfterAll {
		wsl.exe -d Ubuntu -u aries --exec rm -rf $work
	}

	It 'asks nothing on Linux, where the groups and partitions do nothing' {
		$config.data.machine.groups | Should -BeNullOrEmpty
		$config.data.machine.partition | Should -BeFalse
		$config.sourceDir | Should -BeExactly $checkout
	}

	It 'reads 1Password through op.exe on the Windows PATH, so the first apply finds it' {
		$config.onepassword.command | Should -BeExactly 'op.exe'
	}

	It 'runs a Windows tool by its name without .exe in an interactive bash, with its arguments and exit status' {
		$tools = "$work/windows-tools"
		Set-Content -LiteralPath (Join-Path $TestDrive 'greet.exe') -NoNewline -Value "#!/bin/sh`nprintf '[%s]' `"`$@`"`nexit 3`n"
		wsl.exe -d Ubuntu -u aries --exec sh -c "mkdir -p $tools && cp $stubs/greet.exe $tools/greet.exe && chmod +x $tools/greet.exe"
		wsl.exe -d Ubuntu -u aries --exec env -i "HOME=$homeRendered" "PATH=/usr/bin:/bin:$tools" bash -i -c 'greet a "b c"; echo " $?"' 2> $null | Should -BeExactly '[a][b c] 3'
	}

	It 'keeps Ubuntu''s command-not-found hint for a name with no .exe either' {
		$output = wsl.exe -d Ubuntu -u aries --exec env -i "HOME=$homeRendered" PATH=/usr/bin:/bin bash -i -c 'sl; echo "status $?"' 2>&1 | ForEach-Object { "$_" }
		$output | Should -Contain 'sudo apt install sl'
		$output | Should -Contain 'status 127'
	}

	It 'puts the home tools on PATH and exports what ~/.profile.d sets, once, in <Shell>' -ForEach @(
		@{ Shell = 'a POSIX login shell'; ReadsEtcProfile = $false; Command = @('sh', '-c', '. "$HOME/.profile"; echo "$PATH"; echo "$DOCKER_HOST"; echo "$DO_NOT_TRACK"') }
		@{ Shell = 'a bash login shell'; ReadsEtcProfile = $true; Command = @('bash', '-l', '-c', 'echo "$PATH"; echo "$DOCKER_HOST"; echo "$DO_NOT_TRACK"') }
		@{ Shell = 'an interactive bash that is not a login shell'; ReadsEtcProfile = $false; Command = @('bash', '-i', '-c', 'echo "$PATH"; echo "$DOCKER_HOST"; echo "$DO_NOT_TRACK"') }
		@{ Shell = 'an interactive bash inside a bash login shell'; ReadsEtcProfile = $true; Command = @('bash', '-l', '-c', 'bash -i -c ''echo "$PATH"; echo "$DOCKER_HOST"; echo "$DO_NOT_TRACK"''') }
	) {
		$systemPath = if ($ReadsEtcProfile) {
			wsl.exe -d Ubuntu -u aries --exec env -i "HOME=$homeRendered" PATH=/usr/bin:/bin sh -c '. /etc/profile; echo "$PATH"'
		} else {
			'/usr/bin:/bin'
		}
		$environment = @(wsl.exe -d Ubuntu -u aries --exec env -i "HOME=$homeRendered" PATH=/usr/bin:/bin @Command 2> $null)
		$environment | Should -BeExactly @(
			"$homeRendered/.local/bin:$homeRendered/.cargo/bin:$homeRendered/.asdf/shims:${systemPath}:$homeRendered/.local/share/pnpm/bin"
			'unix:///run/dockerd/docker.sock'
			'1'
		)
	}

	It 'keeps Ubuntu''s own interactive bash setup' {
		wsl.exe -d Ubuntu -u aries --exec env -i "HOME=$homeRendered" PATH=/usr/bin:/bin bash -i -c 'echo "$HISTCONTROL"' 2> $null | Should -BeExactly 'ignoreboth'
	}

	It 'signs git commits through 1Password on Windows, with the key from 1Password' {
		$git = Render-Home '.config/git/config'
		$git | Should -Match "(?m)^\tsigningkey = $([regex]::Escape($mockSigningKey))$"
		$git | Should -Match '(?m)^\tprogram = /[^\n]+/\.local/libexec/1p-contextual/op-ssh-sign$'
		$git | Should -Match '(?m)^\tsshCommand = ~/\.local/libexec/1p-contextual/ssh ssh\.exe$'
		$git | Should -Match '(?m)^\tvariant = ssh$'
		((Render-Home '.config/git/allowed_signers').Trim() -split "`n")[-1] | Should -BeExactly "$mockEmail namespaces=`"git`" $mockSigningKey"
	}

	It 'gives Claude Code its instructions and settings' {
		Render-Home '.claude/CLAUDE.md' | Should -Match '(?m)^# Principles$'
		(Render-Home '.claude/settings.json' | ConvertFrom-Json).PSObject.Properties['statusLine'] | Should -Not -BeNullOrEmpty
	}

	It 'leaves the Windows files out' {
		@($listing | Where-Object { $_ -match ' (\.config/windows|\.wslconfig|AppData|Documents)(/| |$)' }) | Should -BeNullOrEmpty
	}
}

Describe 'zram swap' {
	BeforeAll {
		$repository = Split-Path $PSScriptRoot
		$unit = @(chezmoi --source $repository execute-template --file (Join-Path $repository 'root\(eq .chezmoi.os `linux`)\etc\systemd\system\zram-swap.service.tmpl') | Where-Object { $_ -match '^Exec' })
	}

	It 'creates /dev/zram0 again when a restart has reset it away, then sizes it at 8 GB' {
		$unit | Should -BeExactly @(
			"ExecStartPre=/bin/sh -c 'test -e /dev/zram0 || cat /sys/class/zram-control/hot_add'"
			'ExecStart=/usr/sbin/zramctl --size 8G /dev/zram0'
			'ExecStart=/usr/sbin/mkswap /dev/zram0'
			'ExecStart=/usr/sbin/swapon --priority 100 /dev/zram0'
			'ExecStop=/usr/sbin/swapoff /dev/zram0'
			'ExecStop=/usr/sbin/zramctl --reset /dev/zram0'
		)
	}
}

Describe 'WSL home on Windows' {
	It 'leaves the Linux links and profile out' {
		$managed = @(chezmoi --source (Split-Path $PSScriptRoot) managed --path-style relative)
		$managed | Should -Not -Contain '.profile'
		$managed | Should -Not -Contain '.bashrc'
		$managed | Should -Not -Contain '.local/bin/op'
		$managed | Should -Not -Contain '.local/share/jadx'
		$managed | Should -Contain '.config/git/config'
	}

	It 'leaves the Vite+ install out on Windows' {
		$scripts = @(chezmoi --source (Split-Path $PSScriptRoot) managed --include scripts --path-style relative)
		$scripts | Should -Not -Contain '.chezmoiscripts/40-vite-plus.sh'
		$scripts | Should -Contain '.chezmoiscripts/20-packages.ps1'
	}

	It 'keeps 1Password''s default command on Windows' {
		chezmoi --source (Split-Path $PSScriptRoot) execute-template --init --file (Join-Path (Split-Path $PSScriptRoot) 'root\.chezmoi.yaml.tmpl') | Should -Not -Match 'onepassword'
	}
}

Describe 'windows configuration script' {
	BeforeAll {
		$repository = Split-Path $PSScriptRoot
		function Render-Script([string] $Name) {
			(chezmoi --source $repository execute-template --file (Join-Path $repository "root\~\$Name")) -join "`n"
		}
	}

	It 'installs the pinned cheznous in WSL, not the one running this apply' {
		$data = @{ system = @{ cheznous = @{ version = '9.8.7-cheznous.6' } } } | ConvertTo-Json -Depth 3 -Compress
		$script = (chezmoi --source $repository --override-data $data execute-template --file (Join-Path $repository 'root\~\(eq .chezmoi.os `windows`)\run_after_wsl.ps1.tmpl')) -join "`n"
		$script | Should -Match ([regex]::Escape("chezmoi --version 2> /dev/null | grep -q `"v9.8.7-cheznous.6,`" || curl -fsSL https://raw.githubusercontent.com/ariesclark/cheznous/v9.8.7-cheznous.6/assets/scripts/install.sh | sh -s -- -b /usr/local/bin -t v9.8.7-cheznous.6'"))
	}

	It 'applies / and ~ in WSL in one apply, as root with the user''s home directory, after the user''s init' {
		$lines = @((chezmoi --source $repository execute-template --file (Join-Path $repository 'root\~\(eq .chezmoi.os `windows`)\run_after_wsl.ps1.tmpl')) -split "`n")
		$applies = @($lines | Where-Object { $_ -match '\bchezmoi\b.*\b(apply|init)\b' -and $_ -notmatch '--version' })
		$applies | Should -BeExactly @(
			'wsl.exe -d Ubuntu -u aries --exec chezmoi init --no-tty --source $checkout'
			'wsl.exe -d Ubuntu -u root --exec env HOME=/home/aries chezmoi --source $checkout --destination / --persistent-state /var/lib/chezmoi-root/state.boltdb --cache /var/cache/chezmoi-root apply --force --no-tty'
		)
	}

	It 'pins the taskbar in a script of its own, which reruns for the layout and the shortcuts only' {
		$script = Render-Script '(eq .chezmoi.os `windows`)\dot_config\windows\run_onchange_after_taskbar.xml.ps1.tmpl'
		$script | Should -Match '(?m)^Restart-Explorer$'
		$script | Should -Not -Match '(?i)winget configure'
	}
}

Describe 'git' {
	BeforeAll {
		$config = Render '.config\git\config'
	}

	It 'signs with SSH through 1Password on Windows' {
		$config | Should -Match '(?m)^\tgpgsign = true$'
		$config | Should -Match '(?m)^\tprogram = C:/Users/[^/]+/\.local/libexec/1p-contextual/op-ssh-sign\.exe$'
		$config | Should -Match '(?m)^\tsshCommand = ~/\.local/libexec/1p-contextual/ssh\.exe C:/Windows/System32/OpenSSH/ssh\.exe$'
		$config | Should -Match '(?m)^\tvariant = ssh$'
	}

	It 'reads the name and email from 1Password, on lines of their own' {
		$config | Should -Match '(?m)^\tname = Stub Person$'
		$config | Should -Match "(?m)^\temail = $([regex]::Escape($mockEmail))$"
	}

	It 'reads the signing key from 1Password instead of keeping it in the repo' {
		Get-Content (Join-Path $source 'root\~\dot_config\git\readonly_config.tmpl') -Raw | Should -Not -Match 'AAAAC3Nza'
		$config | Should -Match "(?m)^\tsigningkey = $([regex]::Escape($mockSigningKey))$"
	}

	It 'trusts the signing key for the email, only for git signatures' {
		$config | Should -Match '(?m)^\tallowedSignersFile = ~/\.config/git/allowed_signers$'
		$signers = Render '.config\git\allowed_signers'
		($signers.Trim() -split "`n")[-1] | Should -BeExactly "$mockEmail namespaces=`"git`" $mockSigningKey"
	}

	It 'leaves the WSL settings out on Windows' {
		$config | Should -Not -Match 'op-ssh-sign-wsl'
	}

	It 'fetches from GitHub over HTTPS and pushes over SSH, so 1Password approves each push, from an <Form> remote' -ForEach @(
		@{ Form = 'HTTPS'; Url = 'https://github.com/owner/repo.git' }
		@{ Form = 'SSH'; Url = 'git@github.com:owner/repo.git' }
	) {
		$repository = Join-Path $TestDrive "remote-$Form"
		git init --quiet $repository
		git -C $repository remote add origin $Url
		$env:GIT_CONFIG_GLOBAL = Join-Path $rendered '.config\git\config'
		try {
			git -C $repository remote get-url origin | Should -BeExactly 'https://github.com/owner/repo.git'
			git -C $repository remote get-url --push origin | Should -BeExactly 'git@github.com:owner/repo.git'
		} finally {
			Remove-Item env:GIT_CONFIG_GLOBAL
		}
	}

	It 'leaves the 1p-contextual source out of ~, since its build script installs the binaries' {
		Test-Path -LiteralPath (Join-Path $rendered '.local\libexec\1p-contextual') | Should -BeFalse
	}
}

Describe 'ssh' {
	It 'trusts exactly the host keys GitHub publishes, by their documented fingerprints' {
		ssh-keygen -l -f (Join-Path $rendered '.ssh\known_hosts.d\github.com') | Should -BeExactly @(
			'256 SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU github.com (ED25519)'
			'256 SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM github.com (ECDSA)'
			'3072 SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s github.com (RSA)'
		)
	}

	It 'checks github.com against those keys only, and offers it only the push key' {
		(Render '.ssh\config') -split "`n" | Where-Object { $_ -notmatch '^#' } | Should -BeExactly @(
			'Host github.com'
			"`tUserKnownHostsFile ~/.ssh/known_hosts.d/github.com"
			"`tIdentityFile ~/.ssh/github.com.pub"
			"`tIdentitiesOnly yes"
		)
	}

	It 'reads the push key from 1Password instead of keeping it in the repo' {
		(Render '.ssh\github.com.pub') -split "`n" | Where-Object { $_ -notmatch '^#' } | Should -BeExactly $mockPushKey
	}
}

Describe 'Claude Code settings' {
	BeforeAll {
		$settings = (Render '.claude\settings.json') | ConvertFrom-Json
	}

	It 'leaves the Linux-only plugins, marketplaces and status line out on Windows' {
		$settings.PSObject.Properties['statusLine'] | Should -BeNullOrEmpty
		$settings.extraKnownMarketplaces.PSObject.Properties['ariesclark'] | Should -BeNullOrEmpty
		$settings.enabledPlugins.PSObject.Properties['github@ariesclark'] | Should -BeNullOrEmpty
	}

	It 'never writes settings.yaml itself to ~' {
		chezmoi --source $source managed --include files --path-style relative | Should -Not -Contain '.claude/settings.yaml'
	}
}
