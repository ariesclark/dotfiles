BeforeAll {
	Import-Module (Join-Path $PSScriptRoot 'shortcuts.psm1') -Force
	$target = Join-Path $env:SystemRoot 'System32\notepad.exe'
}

Describe 'Sync-Shortcut' {
	It 'writes the target, arguments and app id' {
		$path = Join-Path $TestDrive 'Notepad.lnk'
		Sync-Shortcut -Path $path -Target $target -Arguments '--flag "a b"' -AppId 'Contoso.Notepad'

		$shortcut = Get-Shortcut -Path $path
		$shortcut.Target | Should -Be $target
		$shortcut.Arguments | Should -BeExactly '--flag "a b"'
		$shortcut.AppId | Should -BeExactly 'Contoso.Notepad'
	}

	It 'rewrites a shortcut whose arguments changed' {
		$path = Join-Path $TestDrive 'Changed.lnk'
		Sync-Shortcut -Path $path -Target $target -Arguments '--old' -AppId 'Contoso.Notepad'
		Sync-Shortcut -Path $path -Target $target -Arguments '--new' -AppId 'Contoso.Notepad'

		(Get-Shortcut -Path $path).Arguments | Should -BeExactly '--new'
	}

	It 'leaves an up-to-date shortcut untouched' {
		$path = Join-Path $TestDrive 'Current.lnk'
		Sync-Shortcut -Path $path -Target $target -Arguments '--same' -AppId 'Contoso.Notepad'
		$written = (Get-Item -LiteralPath $path).LastWriteTimeUtc
		Start-Sleep -Milliseconds 50
		Sync-Shortcut -Path $path -Target $target -Arguments '--same' -AppId 'Contoso.Notepad'

		(Get-Item -LiteralPath $path).LastWriteTimeUtc | Should -Be $written
	}

	It 'writes no app id when none is declared' {
		$path = Join-Path $TestDrive 'Plain.lnk'
		Sync-Shortcut -Path $path -Target $target -Arguments '' -AppId ''

		(Get-Shortcut -Path $path).AppId | Should -BeNullOrEmpty
	}
}
