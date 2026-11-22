# 1p-contextual

When git asks 1Password's SSH agent for a key, 1Password's prompt names the program that asked. That is usually the terminal or editor that started git, so two pushes or two signed commits look the same. 1p-contextual makes the prompt say who is asking for what:

- Allow **Claude, pushing 3 commits to ariesclark∕dotfiles꞉main (pc-github-auth-55cf05),** to use SSH key
- Allow **Visual Studio Code, signing “feat(git)꞉ add the backup job” in ariesclark∕dotfiles꞉main,** to use SSH key
- Allow **PowerShell 7, signing tag v1 “release it” in ariesclark∕dotfiles (some-worktree),** to use SSH key
- Allow **Claude, fetching from someone∕project (some-worktree),** to use SSH key

It works on Windows, with Git for Windows, and in WSL, with 1Password for Windows as the agent.

## Use

Two programs, `ssh` and `op-ssh-sign`, stand in for the programs git runs. [The build script](<../../../(eq .chezmoi.os `linux`)/.chezmoiscripts/run_onchange_after_42-1p-contextual.sh.tmpl>) builds them in WSL whenever this folder changes, checks that Windows will run the new build, and installs:

- the Windows build as `ssh.exe` and `op-ssh-sign.exe` in `%USERPROFILE%\.local\libexec\1p-contextual\`
- the Linux build as `ssh` and `op-ssh-sign` in `~/.local/libexec/1p-contextual/` in WSL, next to `1p-contextual.exe`, a link to the Windows build

[The git config](../../../dot_config/git/readonly_config.tmpl) points git at them:

```ini
[gpg "ssh"]
	program = ~/.local/libexec/1p-contextual/op-ssh-sign.exe
[core]
	sshCommand = ~/.local/libexec/1p-contextual/ssh.exe C:/Windows/System32/OpenSSH/ssh.exe
[ssh]
	variant = ssh
```

In WSL, the programs have no `.exe`, and the ssh is `ssh.exe`, the Windows ssh that talks to 1Password. `ssh.variant = ssh` keeps git from probing the ssh with `-G`. [`.chezmoiignore`](../../../.chezmoiignore) keeps this folder out of `~`.

## The label

- **A push** names the commits it carries, the repository, and the branch it goes to. The branch comes from git's own command line, so `git push origin HEAD:main` names `main`; a push with no branch names where git would push the current branch (`@{push}`). The commits are those the remote does not have yet, by your remote-tracking refs.
- **A fetch**, an archive or an LFS transfer names the repository.
- **A signature** names the first line of the commit or tag message, the repository from the `origin` remote or the repository's folder, and the checked-out branch. A tag shows its name in place of the branch.
- The worktree's folder follows in brackets, unless it is the repository's name, or the branch's name or its last part.
- The label begins with the application that ran git, and the request follows between commas, so the label fits 1Password's sentence: "Allow Claude, pushing …, to use SSH key". The application is the topmost program in the chain of parent processes that is outside the Windows folder, which is the program 1Password itself would name. Its name is its file description, else its product name, else its file name. When there is none, the label begins with git. The chain stops at a parent that has ended, or that started after its child, since Windows reuses process IDs.
- File names cannot hold `/` or `:`, so the label has `∕` (U+2215) and `꞉` (U+A789) in their place. A subject longer than 60 characters is cut with `…`, and the whole label at 120.
- Any other ssh command, and every `op-ssh-sign` command other than `-Y sign`, such as verification, runs as it is, under no name.

## How

1Password names the program at the top of the chain of parent processes that it can follow from the request. On Windows, the program copies itself to `%TEMP%\1p-contextual\<pid>\<label>.exe`, and gives the copy the icon of the application that ran git, so the prompt shows that icon. An application with no icon in its program file leaves the copy with its own. It starts a suspended copy of itself as a stand-in, starts the named copy with the stand-in as its parent ([`PROC_THREAD_ATTRIBUTE_PARENT_PROCESS`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute)), and ends the stand-in. So the named copy has no living parent, and 1Password stops there and shows its name. The named copy runs the real ssh or `op-ssh-sign`, found on `PATH` and never in the program's own folder, and returns its exit status. A [job object](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects) ties the named copy to the program, so stopping git stops them too. Each run deletes its copy, and clears copies that stopped runs left behind.

In WSL, the Linux build reads the request with WSL's git, turns the signer's file paths into Windows paths, and hands the named run to the Windows build. The named copy then gets its own hidden console and pipes, since WSL's console does not carry over to it.

## Code

- [`src/lib.rs`](src/lib.rs): the two programs, from arguments to a named run.
- [`src/request.rs`](src/request.rs) and [`src/label.rs`](src/label.rs): what is being asked, and the words for it.
- [`src/git/`](src/git): git's formats (a `git push` command line, the remote command ssh runs, a signed object, a remote URL) and, in `repository.rs`, the only calls to git.
- [`src/process/`](src/process): the chain of parent processes, for the `git push` that started the program and the application that ran git (`ancestry/`), and running a program under a name (`launch/`).

## Limits

- It relies on how 1Password names a requester, which 1Password does not document.
- It is not signed. Smart App Control lets each build run or not, by its own judgment of the file; the build script keeps the installed build when Windows will not run a new one.
- Each request adds about 0.15 seconds.
- After you tick "Approve for all applications" in a prompt, 1Password stops asking until it locks, so no label shows.
- The WSL path gives ssh a hidden console, so an ssh question, such as an unknown host key, cannot be answered there.

## Tests

In WSL, in this folder:

```sh
cargo test --target x86_64-pc-windows-gnu
cargo test
```

The first runs the unit tests and [`tests/windows.rs`](tests/windows.rs) on Windows, through WSL. The second runs the unit tests and [`tests/wsl.rs`](tests/wsl.rs), which needs the Windows build from the first. The integration tests run real git against the built programs, with [`examples/lister.rs`](examples/lister.rs) as the ssh and the signer, so they need no network and no 1Password. They start git from [`examples/app.rs`](examples/app.rs) through a parent that has ended, so the chain of parent processes stops at that app, whatever runs the tests.
