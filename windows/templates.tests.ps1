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
	$layout = [xml](Render '.config\windows\taskbar.xml')
}

Describe 'generated label' {
	BeforeDiscovery {
		$repository = Split-Path $PSScriptRoot
		$targets = @(chezmoi --source $repository managed --include files --path-style absolute | ForEach-Object {
			@{ Target = $_; Leaf = Split-Path $_ -Leaf }
		})
	}

	BeforeAll {
		$repository = Split-Path $PSScriptRoot
	}

	It 'opens <Leaf> with the source file to change instead, in its own comment syntax' -ForEach @($targets | Where-Object { $_.Target -notlike '*.json' }) {
		$sourceFile = if ($Target -like '*\GitHub CLI\config.yml') { Join-Path $repository 'home\dot_config\gh\config.yml.tmpl' } else { chezmoi --source $repository source-path $Target }
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
		$sources = Get-ChildItem -Recurse -File -Force (Join-Path $repository 'home') | Where-Object { $_.Name -notlike 'modify_*' -and $_.Name -notlike '.chezmoi*' -and $_.Name -ne 'settings.yaml' -and $_.FullName -notmatch '\\\.chezmoi(data|templates|scripts)\\' -and $_.FullName -notlike '*\GitHub CLI\config.yml.tmpl' }
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
		$pins.Count | Should -Be 6
		$pins[0].DesktopApplicationID | Should -BeExactly 'Microsoft.Windows.Explorer'
		$pins[1].LocalName | Should -BeExactly 'UWA'
		$pins[1].AppUserModelID | Should -BeExactly 'Claude_pzs8sxrjxfjjc!Claude'
		$pins[2].DesktopApplicationLinkPath | Should -BeLike '*\Task Manager.lnk'
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
