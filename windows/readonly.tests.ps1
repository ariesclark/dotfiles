BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'readonly.psm1') -Force
}

Describe 'Get-ReadOnlyTarget' {
	BeforeEach {
		$source = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
		New-Item -ItemType Directory -Force (Join-Path $source 'dot_config\git'), (Join-Path $source '.archive\.config'), (Join-Path $source '.chezmoiscripts') | Out-Null
		New-Item -ItemType File (Join-Path $source 'readonly_dot_editorconfig.tmpl'), (Join-Path $source 'dot_config\git\readonly_config.tmpl'), (Join-Path $source 'dot_config\git\writable.tmpl') | Out-Null
		New-Item -ItemType File (Join-Path $source '.archive\.config\readonly_leftover'), (Join-Path $source '.chezmoiscripts\readonly_script.ps1') | Out-Null
		$script:calls = [System.Collections.Generic.List[object]]::new()
		$targetPath = { param([string[]] $Sources) $script:calls.Add($Sources); $Sources | ForEach-Object { "target of $(Split-Path $_ -Leaf)" } }
	}

	It 'maps every readonly_ source to its target in one call' {
		$targets = Get-ReadOnlyTarget -SourceDirectory $source -TargetPath $targetPath

		$script:calls.Count | Should -Be 1
		@($script:calls[0] | Split-Path -Leaf | Sort-Object) | Should -Be @('readonly_config.tmpl', 'readonly_dot_editorconfig.tmpl')
		@($targets | Sort-Object) | Should -Be @('target of readonly_config.tmpl', 'target of readonly_dot_editorconfig.tmpl')
	}

	It 'skips folders chezmoi ignores, like .archive and .chezmoiscripts' {
		Get-ReadOnlyTarget -SourceDirectory $source -TargetPath $targetPath | Should -Not -Match 'leftover|script'
	}

	It 'asks for nothing when no source is read-only' {
		Get-ChildItem -LiteralPath $source -Recurse -File -Filter 'readonly_*' | Remove-Item

		Get-ReadOnlyTarget -SourceDirectory $source -TargetPath $targetPath | Should -BeNullOrEmpty
		$script:calls.Count | Should -Be 0
	}
}

Describe 'Set-TargetReadOnly' {
	BeforeEach {
		$folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
		New-Item -ItemType Directory -Force $folder | Out-Null
		$file = Join-Path $folder 'config'
		Set-Content -LiteralPath $file -Value 'managed'
	}

	AfterEach {
		if (Test-Path -LiteralPath $file) { (Get-Item -LiteralPath $file).IsReadOnly = $false }
	}

	It 'marks a target read-only' {
		Set-TargetReadOnly -Path $file -ReadOnly $true

		(Get-Item -LiteralPath $file).IsReadOnly | Should -BeTrue
	}

	It 'makes a read-only target writable again' {
		(Get-Item -LiteralPath $file).IsReadOnly = $true

		Set-TargetReadOnly -Path $file -ReadOnly $false

		(Get-Item -LiteralPath $file).IsReadOnly | Should -BeFalse
	}

	It 'skips a target that doesn''t exist yet' {
		{ Set-TargetReadOnly -Path (Join-Path $folder 'missing') -ReadOnly $true } | Should -Not -Throw
		Test-Path -LiteralPath (Join-Path $folder 'missing') | Should -BeFalse
	}
}
