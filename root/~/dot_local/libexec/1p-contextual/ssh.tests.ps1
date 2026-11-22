BeforeAll {
	. (Join-Path $PSScriptRoot 'test-fixture.ps1')
}

AfterAll {
	Restore-Environment
}

Describe 'ssh' {
	It 'names a push for the repository, branch and checkout, then deletes the name' {
		git -C $elsewhere -c "core.sshCommand=$sshContextual $listerForSh" push --dry-run $unresolvable HEAD 2> $null
		Get-Listing | Should -BeExactly @("a push to owner${slash}repo${colon}claude${slash}feature (elsewhere).exe")
		Get-LeftBehind | Should -BeNullOrEmpty
	}

	It 'leaves the checkout out when the branch is named for it' {
		git -C $namedForBranch -c "core.sshCommand=$sshContextual $listerForSh" push --dry-run $unresolvable HEAD 2> $null
		Get-Listing | Should -BeExactly @("a push to owner${slash}repo${colon}claude${slash}feature-x.exe")
	}

	It 'leaves the checkout out when it is named for the repository' {
		git -C $namedForRepository -c "core.sshCommand=$sshContextual $listerForSh" push --dry-run $unresolvable HEAD 2> $null
		Get-Listing | Should -BeExactly @("a push to owner${slash}repo${colon}main.exe")
	}

	It 'gives git the exit status of the push''s ssh' {
		Push-Location -LiteralPath $elsewhere
		try {
			& $sh -c "$sshContextual $listerForSh git@nonexistent.invalid `"git-receive-pack 'owner/repo.git'`""
			$LASTEXITCODE | Should -Be 3
		} finally {
			Pop-Location
		}
		Remove-Item -LiteralPath $listing
	}

	It 'leaves a fetch to plain ssh' {
		$output = @(git -C $elsewhere -c "core.sshCommand=$sshContextual C:/Windows/System32/OpenSSH/ssh.exe" ls-remote $unresolvable 2>&1 | ForEach-Object { "$_" })
		$output[0] | Should -BeExactly 'ssh: Could not resolve hostname nonexistent.invalid: No such host is known. '
		Test-Path -LiteralPath $listing | Should -BeFalse
	}
}
