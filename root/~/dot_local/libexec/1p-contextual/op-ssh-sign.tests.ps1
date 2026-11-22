BeforeAll {
	. (Join-Path $PSScriptRoot 'test-fixture.ps1')
	$env:OP_SSH_SIGN_CONTEXTUAL_PROGRAM = $listerForSh
}

AfterAll {
	Remove-Item env:OP_SSH_SIGN_CONTEXTUAL_PROGRAM
	Restore-Environment
}

Describe 'op-ssh-sign' {
	It 'names a commit signature for its subject, repository, branch and checkout, then deletes the name' {
		git @git -C $elsewhere commit --quiet --gpg-sign --allow-empty --message 'feat(git): sign it' 2> $null
		Get-Listing | Should -BeExactly @("signing ${open}feat(git)$colon sign it$close in owner${slash}repo${colon}claude${slash}feature (elsewhere).exe")
		Get-LeftBehind | Should -BeNullOrEmpty
	}

	It 'names a tag signature for the tag, and keeps the checkout since a tag shows no branch' {
		git @git -C $namedForBranch tag --sign --message 'release it' v1 2> $null
		Get-Listing | Should -BeExactly @("signing tag v1 ${open}release it$close in owner${slash}repo (feature-x).exe")
	}

	It 'names a signature in a repository with no origin for its folder' {
		$localOnly = Join-Path $TestDrive 'local-only'
		git @git init --quiet $localOnly
		git @git -C $localOnly commit --quiet --gpg-sign --allow-empty --message 'feat(git): sign it' 2> $null
		Get-Listing | Should -BeExactly @("signing ${open}feat(git)$colon sign it$close in local-only${colon}main.exe")
	}

	It 'hands git the signature and status of a signer that exits at once, every time' {
		$env:OP_SSH_SIGN_CONTEXTUAL_PROGRAM = 'C:/Windows/System32/OpenSSH/ssh-keygen.exe'
		$statuses = foreach ($attempt in 1..5) {
			git @git -C $namedForRepository commit --quiet --gpg-sign --allow-empty --message "feat(git): sign it $attempt" 2> $null
			$LASTEXITCODE
		}
		$statuses | Should -BeExactly @(0, 0, 0, 0, 0)
		$signatures = foreach ($commit in git -C $namedForRepository rev-list -5 HEAD) {
			@(git -C $namedForRepository cat-file commit $commit | Where-Object { $_.StartsWith('gpgsig ') })
		}
		$signatures | Should -BeExactly @(1..5 | ForEach-Object { 'gpgsig -----BEGIN SSH SIGNATURE-----' })
		Get-LeftBehind | Should -BeNullOrEmpty
	}
}
