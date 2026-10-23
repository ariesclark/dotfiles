BeforeAll {
	$source = Split-Path $PSScriptRoot
	$archive = Join-Path $TestDrive 'target.tar'
	$rendered = Join-Path $TestDrive 'rendered'
	New-Item -ItemType Directory -Force -Path $rendered | Out-Null
	chezmoi --source $source archive --format tar --output $archive
	if ($LASTEXITCODE) {
		throw 'chezmoi could not render the repo; is 1Password unlocked?'
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
	$layout = [xml](Render '.config\windows\taskbar.xml')
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
		$sourceFile = if ($Target -like '*\GitHub CLI\config.yml') { Join-Path $repository 'home\dot_config\gh\config.yml.tmpl' } else { [System.IO.Path]::GetFullPath((chezmoi --source $repository source-path $Target)) }
		$label = 'This file is managed by Chezmoi. To change it, update:', $sourceFile
		$expected = switch -Wildcard ($Target) {
			'*.reg' { $label | ForEach-Object { "; $_" } }
			'*.xml' { @('<!--') + $label + '-->' }
			'*.md' { @('<!--') + $label + '-->' }
			default { $label | ForEach-Object { "# $_" } }
		}
		$lines = @((Render $Target.Substring($HOME.Length + 1)) -split "`n")
		$first = if ($lines[0] -match '^(#!|<\?xml |Windows Registry Editor )') { 1 } else { 0 }
		$lines[$first..($first + $expected.Count - 1)] | Should -BeExactly $expected
	}

	It 'leaves <Leaf> as plain JSON, which has no comments' -ForEach @($targets | Where-Object { $_.Target -like '*.json' }) {
		$json = Render $Target.Substring($HOME.Length + 1)
		$json | Should -Not -Match 'managed by Chezmoi'
		{ $json | ConvertFrom-Json -AsHashtable } | Should -Not -Throw
	}

	It 'labels the files this machine skips too' {
		$sourceRoot = Join-Path $repository 'home'
		$sources = Get-ChildItem -Recurse -File -Force $sourceRoot | Where-Object {
			$folders = [System.IO.Path]::GetRelativePath($sourceRoot, $_.DirectoryName).Split([System.IO.Path]::DirectorySeparatorChar)
			-not ($folders | Where-Object { $_.StartsWith('.') -and $_ -ne '.' }) -and
			$_.Name -notlike 'modify_*' -and $_.Name -notlike 'run_*' -and $_.Name -notlike 'symlink_*' -and $_.Name -notlike '.chezmoi*' -and $_.Name -ne 'settings.yaml' -and $_.FullName -notlike '*\GitHub CLI\config.yml.tmpl'
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

	It 'sizes and sorts WinDirStat by logical size, which WSL''s drive reports where physical size is zero' {
		Get-RegistrySection 'HKEY_CURRENT_USER\Software\WinDirStat\WinDirStat\TreeMapView' | Should -BeExactly @(
			'"TreeMapUseLogicalSize"=dword:00000001'
		)
	}
}

Describe 'taskbar.xml' {
	BeforeAll {
		$namespaces = [System.Xml.XmlNamespaceManager]::new($layout.NameTable)
		$namespaces.AddNamespace('taskbar', 'http://schemas.microsoft.com/Start/2014/TaskbarLayout')
		$pins = @($layout.SelectNodes('//taskbar:TaskbarPinList/*', $namespaces))
	}

	It 'replaces the default pins' {
		$layout.LayoutModificationTemplate.CustomTaskbarLayoutCollection.PinListPlacement | Should -BeExactly 'Replace'
	}

	It 'pins its apps in order, by the right kind of id' {
		$identities = $pins | ForEach-Object {
			switch ($_) {
				{ $_.LocalName -eq 'UWA' } { "uwa:$($_.AppUserModelID)"; break }
				{ $_.HasAttribute('DesktopApplicationID') } { "id:$($_.DesktopApplicationID)"; break }
				default { "link:$($_.DesktopApplicationLinkPath)" }
			}
		}

		$identities | Should -BeExactly @(
			'link:%APPDATA%\Microsoft\Windows\Start Menu\Programs\Firefox.lnk'
			'id:com.squirrel.Discord.Discord'
			'link:%APPDATA%\Microsoft\Windows\Start Menu\Programs\Visual Studio Code.lnk'
			'id:Microsoft.Windows.Explorer'
			'uwa:Claude_pzs8sxrjxfjjc!Claude'
			'link:%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\System Tools\Task Manager.lnk'
			'link:%APPDATA%\Microsoft\Windows\Start Menu\Programs\Chromium.lnk'
			'link:%APPDATA%\Microsoft\Windows\Start Menu\Programs\Firefox Developer Edition.lnk'
			'link:%APPDATA%\Microsoft\Windows\Start Menu\Programs\Firefox Nightly.lnk'
		)
	}
}

Describe '.wslconfig' {
	It 'keeps swap off C:, gives memory back gradually and lets the disks shrink' {
		$lines = @((Render '.wslconfig') -split "`n" | Where-Object { $_ -and -not $_.StartsWith('#') })

		$lines | Should -BeExactly @(
			'[wsl2]'
			'swapFile=E:\\WSL\\swap.vhdx'
			'[experimental]'
			'autoMemoryReclaim=gradual'
			'sparseVhd=true'
		)
	}
}

Describe 'WSL root source' {
	BeforeAll {
		$repository = Split-Path $PSScriptRoot
		$rootSource = Join-Path $repository 'root'
		$data = Join-Path $TestDrive 'wsl-root-data.json'
		(chezmoi --source $repository execute-template '{{ includeTemplate "wsl-root-data" . }}') -join "`n" | Set-Content -LiteralPath $data -NoNewline
		$rootArchive = Join-Path $TestDrive 'root.tar'
		$rootRendered = Join-Path $TestDrive 'root-rendered'
		New-Item -ItemType Directory -Force -Path $rootRendered | Out-Null
		chezmoi --source $rootSource --destination (Join-Path $TestDrive 'rootfs') --persistent-state (Join-Path $TestDrive 'root-state.boltdb') --override-data-file $data archive --format tar --output $rootArchive
		if ($LASTEXITCODE) {
			throw 'chezmoi could not render the root source.'
		}
		tar -xf $rootArchive -C $rootRendered 2> $null
		$listing = @(tar -tvf $rootArchive)
		function Get-RootSetting([string] $Target) {
			@((Get-Content -LiteralPath (Join-Path $rootRendered $Target)) | Where-Object { $_ -and -not $_.StartsWith('#') })
		}
		function Render-RootScript([string] $Name) {
			@((chezmoi --source $rootSource --override-data-file $data execute-template --file (Join-Path $rootSource $Name)) | Where-Object { $_ -and -not $_.StartsWith('#') })
		}
	}

	It 'turns off drive automount and the Windows PATH, and mounts only what fstab lists' {
		Get-RootSetting 'etc\wsl.conf' | Should -BeExactly @(
			'[boot]'
			'systemd=true'
			'[user]'
			'default=aries'
			'[automount]'
			'enabled=false'
			'mountFsTab=true'
			'[interop]'
			'enabled=true'
			'appendWindowsPath=false'
		)
	}

	It 'mounts each declared Windows folder and the Windows checkout read-only, owned by the user' {
		$options = 'drvfs ro,noatime,uid=1000,gid=1000,x-mount.mkdir 0 0'
		Get-RootSetting 'etc\fstab' | Should -BeExactly @(
			"C:/Windows/System32/OpenSSH /mnt/windows/openssh $options"
			"$($env:LOCALAPPDATA.Replace('\', '/'))/Microsoft/WindowsApps/Agilebits.1Password_amwd9z03whsfe /mnt/windows/1password $options"
			"E:/Scoop/apps/1password-cli/current /mnt/windows/1password-cli $options"
			"E:/Scoop/apps/vscode/current /mnt/windows/vscode $options"
			"E:/Scoop/apps/firefox/current /mnt/windows/firefox $options"
			"$($repository.Replace('\', '/')) /mnt/windows/dotfiles $options"
		)
	}

	It 'runs rootless Docker as the dockerd user, with its socket in a folder only the dockerd group can enter' {
		$unit = Get-RootSetting 'var\lib\dockerd\.config\systemd\user\docker.service'
		$unit | Should -Contain 'ExecStart=/usr/share/docker.io/contrib/dockerd-rootless.sh --host=unix:///run/dockerd/docker.sock --group=0'
		$unit | Should -Contain 'Environment=PATH=/usr/share/docker.io/contrib:/usr/sbin:/usr/bin:/sbin:/bin'
		$unit | Should -Contain 'WantedBy=default.target'
		($listing | Where-Object { $_ -like '*default.target.wants/docker.service -> ../docker.service' }).Count | Should -Be 1
		Get-RootSetting 'etc\tmpfiles.d\dockerd.conf' | Should -BeExactly @('d /run/dockerd 0750 dockerd dockerd -')
	}

	It 'leaves the user''s environment to home/' {
		Join-Path $rootRendered 'etc\profile.d' | Should -Not -Exist
	}

	It 'installs the declared packages and keeps the root Docker daemon off' {
		Render-RootScript 'run_onchange_before_10-packages.sh.tmpl' | Should -BeExactly @(
			'set -eu'
			'apt-get install -y --no-install-recommends git jq docker.io docker-compose-v2 docker-buildx uidmap dbus-user-session rootlesskit slirp4netns acl'
			'systemctl disable --now docker.service docker.socket'
		)
	}

	It 'adds GitHub''s apt repository for gh, trusting only GitHub CLI''s current signing key' {
		$sources = Get-RootSetting 'etc\apt\sources.list.d\github-cli.sources'
		$sources[0..4] | Should -BeExactly @(
			'Types: deb'
			'URIs: https://cli.github.com/packages'
			'Suites: stable'
			'Components: main'
			'Signed-By:'
		)
		$key = ($sources | Select-Object -Skip 5 | ForEach-Object { $_.Substring(1) -replace '^\.$', '' }) -join "`n"
		$key | Should -Match '^-----BEGIN PGP PUBLIC KEY BLOCK-----'
		$fingerprints = @($key | wsl.exe -d Ubuntu -u aries --exec gpg --show-keys --with-colons 2> $null | Where-Object { $_ -like 'fpr:*' } | ForEach-Object { $_.Split(':')[9] })
		$fingerprints[0] | Should -BeExactly '7F38BBB59D064DBCB3D84D725612B36462313325'
		@(($key | wsl.exe -d Ubuntu -u aries --exec gpg --show-keys --with-colons 2> $null) | Where-Object { $_ -like 'pub:*' }).Count | Should -Be 1
	}

	It 'installs gh from that repository when its sources change' {
		Render-RootScript 'etc\apt\sources.list.d\run_onchange_after_github-cli.sources.sh.tmpl' | Should -BeExactly @(
			'set -eu'
			'apt-get update'
			'apt-get install -y --no-install-recommends gh'
		)
	}

	It 'creates the dockerd user and gives it the repos, but only passage through the home folder' {
		Render-RootScript 'var\lib\dockerd\run_onchange_before_create-user.sh.tmpl' | Should -BeExactly @(
			'set -eu'
			'id dockerd > /dev/null 2>&1 || useradd --system --user-group --add-subids-for-system --create-home --home-dir /var/lib/dockerd --shell /usr/sbin/nologin dockerd'
			'usermod --append --groups dockerd aries'
			'loginctl enable-linger dockerd'
			'setfacl --modify user:dockerd:x /home/aries'
			'setfacl --recursive --modify user:dockerd:rwX,user:aries:rwX,default:user:dockerd:rwX,default:user:aries:rwX /home/aries/repos'
		)
	}

	It 'reruns the fstab script when the rendered fstab changes, also through data, and only then' {
		function Get-ScriptHash([string] $DataJson) {
			$file = Join-Path $TestDrive 'variant.json'
			Set-Content -LiteralPath $file -Value $DataJson -NoNewline
			@((chezmoi --source $rootSource --override-data-file $file execute-template --file (Join-Path $rootSource 'etc\run_onchange_after_fstab.sh.tmpl')) -split "`n")[1]
		}
		$declared = Get-Content -Raw -LiteralPath $data | ConvertFrom-Json
		$withMount = Get-Content -Raw -LiteralPath $data | ConvertFrom-Json
		$withMount.wsl.mounts += [pscustomobject]@{ from = 'C:/Extra'; to = '/mnt/windows/extra' }
		$withPackage = Get-Content -Raw -LiteralPath $data | ConvertFrom-Json
		$withPackage.wsl.packages += 'htop'

		$original = Get-ScriptHash ($declared | ConvertTo-Json -Depth 5)
		$original | Should -Match '^# [0-9a-f]{64}$'
		Get-ScriptHash ($withMount | ConvertTo-Json -Depth 5) | Should -Not -Be $original
		Get-ScriptHash ($withPackage | ConvertTo-Json -Depth 5) | Should -Be $original
	}
	It 'names every run_onchange_after script after a file next to it, in both sources' {
		$scripts = @(Get-ChildItem $rootSource, (Join-Path $repository 'home') -Recurse -File -Filter 'run_onchange_after_*' | Where-Object { $_.FullName -notmatch '\\\.(archive|chezmoiscripts)\\' })
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
	It 'remounts the Windows folders live when fstab changes' {
		Render-RootScript 'etc\run_onchange_after_fstab.sh.tmpl' | Should -Contain 'findmnt -rn -t 9p,drvfs -o TARGET | grep ^/mnt/windows/ | grep -vx /mnt/windows/dotfiles | xargs -r umount -l'
		Render-RootScript 'etc\run_onchange_after_fstab.sh.tmpl' | Should -Contain 'mount -a'
	}

	It 'asks Windows for a WSL restart when wsl.conf changes' {
		Render-RootScript 'etc\run_onchange_after_wsl.conf.sh.tmpl' | Should -Contain 'touch /run/wsl-restart-needed'
	}

	It 'reloads and restarts the dockerd service when its unit changes' {
		Render-RootScript 'var\lib\dockerd\dot_config\systemd\user\run_onchange_after_docker.service.sh.tmpl' | Should -Contain 'systemctl --user -M dockerd@ daemon-reload'
		Render-RootScript 'var\lib\dockerd\dot_config\systemd\user\run_onchange_after_docker.service.sh.tmpl' | Should -Contain 'systemctl --user -M dockerd@ restart docker'
	}
}

Describe 'WSL home' {
	BeforeAll {
		$work = "/tmp/chezmoi-home-test-$PID"
		$homeRendered = "$work/rendered"
		wsl.exe -d Ubuntu -u aries --exec sh -c "set -eu; mkdir -p $homeRendered; chezmoi --source /mnt/windows/dotfiles execute-template --init --file /mnt/windows/dotfiles/home/.chezmoi.yaml.tmpl < /dev/null > $work/chezmoi.yaml; chezmoi --config $work/chezmoi.yaml --persistent-state $work/state.boltdb archive --format tar --output $work/home.tar; tar -xf $work/home.tar -C $homeRendered"
		if ($LASTEXITCODE) {
			throw 'chezmoi could not render home/ inside WSL; is 1Password unlocked?'
		}
		$config = (wsl.exe -d Ubuntu -u aries --exec chezmoi --config "$work/chezmoi.yaml" dump-config --format json) -join "`n" | ConvertFrom-Json
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
		$config.sourceDir | Should -BeExactly '/mnt/windows/dotfiles'
	}

	It 'reads 1Password through the mounted op.exe, so the first apply finds it' {
		$config.onepassword.command | Should -BeExactly '/mnt/windows/1password-cli/op.exe'
		wsl.exe -d Ubuntu -u aries --exec test -x $config.onepassword.command
		$LASTEXITCODE | Should -Be 0
	}

	It 'links <Link> to <Target> in ~/.local/bin, and the target is there' -ForEach @(
		@{ Link = 'op'; Target = '/mnt/windows/1password-cli/op.exe' }
		@{ Link = 'op-ssh-sign-wsl.exe'; Target = '/mnt/windows/1password/op-ssh-sign-wsl.exe' }
		@{ Link = 'ssh.exe'; Target = '/mnt/windows/openssh/ssh.exe' }
		@{ Link = 'code'; Target = '/mnt/windows/vscode/bin/code' }
	) {
		@($listing | Where-Object { $_ -like "* .local/bin/$Link -> $Target" }).Count | Should -Be 1
		wsl.exe -d Ubuntu -u aries --exec test -e $Target
		$LASTEXITCODE | Should -Be 0
	}

	It 'puts ~/.local/bin first in PATH and exports what ~/.profile.d sets, at login' {
		$environment = @(wsl.exe -d Ubuntu -u aries --exec env -i "HOME=$homeRendered" PATH=/usr/bin:/bin sh -c '. "$HOME/.profile"; echo "$PATH"; echo "$DOCKER_HOST"; echo "$DO_NOT_TRACK"')
		$environment | Should -BeExactly @(
			"$homeRendered/.local/bin:/usr/bin:/bin"
			'unix:///run/dockerd/docker.sock'
			'1'
		)
	}

	It 'installs Vite+ for Node and pnpm once, without letting it edit the shell profiles' {
		@((wsl.exe -d Ubuntu -u aries --exec chezmoi --config "$work/chezmoi.yaml" execute-template --file /mnt/windows/dotfiles/home/.chezmoiscripts/run_after_40-vite-plus.sh.tmpl) | Where-Object { $_ }) | Should -BeExactly @(
			'#!/bin/sh'
			'set -eu'
			'[ -x "$HOME/.local/share/vite-plus/current/bin/vp" ] || curl -fsSL https://vite.plus | VP_NODE_MANAGER=yes VP_PM_MANAGER=yes VP_SELF_SETUP_NO_MODIFY_PATH=1 bash'
		)
	}

	It 'loads the Vite+ environment at login' {
		@((Render-Home '.profile.d/vite-plus.sh') -split "`n" | Where-Object { $_ -and -not $_.StartsWith('#') }) | Should -BeExactly @(
			'[ -r "$HOME/.config/vite-plus/env" ] && . "$HOME/.config/vite-plus/env"'
		)
	}

	It 'signs git commits through 1Password on Windows, with the key from 1Password' {
		$git = Render-Home '.config/git/config'
		$git | Should -Match '(?m)^\tsigningkey = ssh-ed25519 AAAAC3Nza\S+$'
		$git | Should -Match '(?m)^\tprogram = op-ssh-sign-wsl\.exe$'
		$git | Should -Match '(?m)^\tsshCommand = ssh\.exe$'
		$key = ([regex]::Match($git, '(?m)^\tsigningkey = (.+)$')).Groups[1].Value
		((Render-Home '.config/git/allowed_signers').Trim() -split "`n")[-1] | Should -BeExactly "me@ariesclark.com namespaces=`"git`" $key"
	}

	It 'gives Claude Code its instructions and settings' {
		Render-Home '.claude/CLAUDE.md' | Should -Match '(?m)^# Excellence$'
		(Render-Home '.claude/settings.json' | ConvertFrom-Json).PSObject.Properties['statusLine'] | Should -Not -BeNullOrEmpty
	}

	It 'leaves the Windows files out' {
		@($listing | Where-Object { $_ -match ' (\.config/windows|\.wslconfig|AppData|Documents)(/| |$)' }) | Should -BeNullOrEmpty
	}
}

Describe 'WSL home on Windows' {
	It 'leaves the Linux links and profile out' {
		$managed = @(chezmoi --source (Split-Path $PSScriptRoot) managed --path-style relative)
		$managed | Should -Not -Contain '.profile'
		$managed | Should -Not -Contain '.local/bin/op'
		$managed | Should -Contain '.config/git/config'
	}

	It 'leaves the Vite+ install out on Windows' {
		chezmoi --source (Split-Path $PSScriptRoot) execute-template --file (Join-Path (Split-Path $PSScriptRoot) 'home\.chezmoiscripts\run_after_40-vite-plus.sh.tmpl') | Should -BeNullOrEmpty
	}

	It 'keeps 1Password''s default command on Windows' {
		chezmoi --source (Split-Path $PSScriptRoot) execute-template --init --file (Join-Path (Split-Path $PSScriptRoot) 'home\.chezmoi.yaml.tmpl') | Should -Not -Match 'onepassword'
	}
}

Describe 'WSL trigger' {
	BeforeAll {
		$repository = Split-Path $PSScriptRoot
		$trigger = @((chezmoi --source $repository execute-template --file (Join-Path $repository 'home\run_after_wsl.ps1.tmpl')) -split "`n")
	}

	It 'mounts the Windows checkout read-only before the first apply' {
		$trigger | Should -Contain "wsl.exe -d Ubuntu -u root --exec sh -c 'mountpoint -q /mnt/windows/dotfiles || mount -t drvfs $($repository.Replace('\', '/')) /mnt/windows/dotfiles -o ro,noatime,uid=1000,gid=1000,x-mount.mkdir'"
	}

	It 'installs chezmoi in the distribution at the version Windows runs' {
		$version = chezmoi execute-template '{{ .chezmoi.version.version }}'
		$trigger | Should -Contain "wsl.exe -d Ubuntu -u root --exec sh -c 'chezmoi --version 2> /dev/null | grep -q `"v$version,`" || curl -fsSL https://get.chezmoi.io | sh -s -- -b /usr/local/bin -t v$version'"
	}

	It 'applies the root source to / as root, with state and data of its own' {
		($trigger | Where-Object { $_ -like 'wsl.exe -d Ubuntu -u root --exec chezmoi --source /mnt/windows/dotfiles/root --destination / --persistent-state /var/lib/chezmoi-root/state.boltdb --cache /var/cache/chezmoi-root --override-data *apply --force --no-tty' }).Count | Should -Be 1
	}

	It 'applies home/ to ~ as the user after the root apply, from the same checkout, with the config init writes' {
		$rootApply = [array]::FindIndex([string[]] $trigger, [Predicate[string]] { param($line) $line -like 'wsl.exe -d Ubuntu -u root --exec chezmoi --source /mnt/windows/dotfiles/root *' })
		$homeInit = [array]::IndexOf($trigger, 'wsl.exe -d Ubuntu -u aries --exec chezmoi init --no-tty --source /mnt/windows/dotfiles')
		$homeApply = [array]::IndexOf($trigger, 'wsl.exe -d Ubuntu -u aries --exec chezmoi apply --force --no-tty')
		$rootApply | Should -BeGreaterThan 0
		$homeInit | Should -BeGreaterThan $rootApply
		$homeApply | Should -BeGreaterThan $homeInit
		@($trigger | Where-Object { $_ -like '*init --apply*' }) | Should -BeNullOrEmpty
	}

	It 'restarts WSL only when the root apply asks for it' {
		$trigger | Should -Contain 'if ((wsl.exe -d Ubuntu -u root --exec sh -c ''test -e /run/wsl-restart-needed && echo restart || true'') -eq ''restart'') {'
		$trigger | Should -Contain '	wsl.exe --shutdown'
	}

	It 'replaces the old copy scripts' {
		Join-Path $repository 'home\.chezmoiscripts\run_onchange_after_38-wsl-system.ps1.tmpl' | Should -Not -Exist
		Join-Path $repository 'home\.chezmoiscripts\run_onchange_after_39-wsl-files.ps1.tmpl' | Should -Not -Exist
		Join-Path $repository 'home\dot_config\wsl' | Should -Not -Exist
	}
}

Describe 'windows configuration script' {
	BeforeAll {
		$repository = Split-Path $PSScriptRoot
		function Render-Script([string] $Name) {
			(chezmoi --source $repository execute-template --file (Join-Path $repository "home\$Name")) -join "`n"
		}
	}

	It 'leaves Explorer running, so settings changes cost no restart' {
		Render-Script 'dot_config\windows\run_onchange_after_configuration.winget.ps1.tmpl' | Should -Not -Match '(?i)explorer'
	}

	It 'pins the taskbar in a script of its own, which reruns for the layout and the shortcuts only' {
		$script = Render-Script 'dot_config\windows\run_onchange_after_taskbar.xml.ps1.tmpl'
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
		$config | Should -Match '(?m)^\tprogram = C:/Users/[^/]+/AppData/Local/Microsoft/WindowsApps/op-ssh-sign\.exe$'
		$config | Should -Match '(?m)^\tsshCommand = C:/Windows/System32/OpenSSH/ssh\.exe$'
	}

	It 'keeps the email and the signing key on lines of their own' {
		$config | Should -Match '(?m)^\temail = me@ariesclark\.com$'
	}

	It 'reads the signing key from 1Password instead of keeping it in the repo' {
		Get-Content (Join-Path $source 'home\dot_config\git\readonly_config.tmpl') -Raw | Should -Not -Match 'AAAAC3Nza'
		$config | Should -Match '(?m)^\tsigningkey = ssh-ed25519 AAAAC3Nza\S+$'
	}

	It 'trusts the signing key for the email, only for git signatures' {
		$config | Should -Match '(?m)^\tallowedSignersFile = ~/\.config/git/allowed_signers$'
		$signers = Render '.config\git\allowed_signers'
		$key = ([regex]::Match($config, '(?m)^\tsigningkey = (.+)$')).Groups[1].Value
		($signers.Trim() -split "`n")[-1] | Should -BeExactly "me@ariesclark.com namespaces=`"git`" $key"
	}

	It 'leaves the WSL settings out on Windows' {
		$config | Should -Not -Match 'op-ssh-sign-wsl'
	}
}

Describe 'Claude Code settings' {
	BeforeAll {
		$settings = (Render '.claude\settings.json') | ConvertFrom-Json
	}

	It 'renders the shared settings from settings.yaml' {
		$settings.permissions.defaultMode | Should -BeExactly 'auto'
		$settings.includeGitInstructions | Should -BeFalse
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

Describe 'gh config' {
	It 'is the same file in gh''s Windows location' {
		$gh = Render 'AppData\Roaming\GitHub CLI\config.yml'
		$gh | Should -Match '(?m)^git_protocol: https$'
		$gh | Should -Match '(?m)^telemetry: disabled$'
	}
}
