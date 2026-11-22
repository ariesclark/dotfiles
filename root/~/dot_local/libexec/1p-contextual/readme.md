# 1p-contextual

When git asks 1Password's SSH agent for a key, 1Password's prompt names the program that asked. That is usually the terminal or editor that started git, so two pushes or two signed commits look the same. 1p-contextual makes the prompt say which one is asking:

- Allow **a push to ariesclark∕dotfiles꞉claude∕pc-github-auth-55cf05** to use SSH key
- Allow **signing “feat(git)꞉ add the backup job” in ariesclark∕dotfiles꞉main** to use SSH key
- Allow **signing tag v1 “release it” in ariesclark∕dotfiles (some-worktree)** to use SSH key

It works on Windows, with Git for Windows, and in WSL, with 1Password for Windows as the agent.

## Use

chezmoi puts `ssh`, `op-ssh-sign` and `run` in `~/.local/libexec/1p-contextual/`, and [the git config](../../../dot_config/git/readonly_config.tmpl) points git at them:

```ini
[gpg "ssh"]
	program = ~/.local/libexec/1p-contextual/op-ssh-sign
[core]
	sshCommand = sh ~/.local/libexec/1p-contextual/ssh C:/Windows/System32/OpenSSH/ssh.exe
[ssh]
	variant = ssh
```

In WSL, the ssh is `ssh.exe`, the Windows ssh that talks to 1Password. `ssh.variant = ssh` keeps git from probing the ssh with `-G`.

git runs `gpg.ssh.program` itself, with no shell, so `op-ssh-sign` must be executable, and here it is `executable_op-ssh-sign` for that. `ssh` and `run` start through `sh`, so they need no mode. The tests and this readme stay in the repo: [`.chezmoiignore`](../../../.chezmoiignore) leaves them out of `~`.

## The name

- A push names the repository from the remote it goes to, and the branch that is checked out, which is usually the branch being pushed.
- A signature names the first line of the commit or tag message, and the repository from the `origin` remote. A tag shows its name in place of the branch.
- The checkout's folder name follows in brackets, unless it is the repository's name or the branch's name, or the last part of it.
- File names cannot hold `/` or `:`, so the name has `∕` (U+2215) and `꞉` (U+A789) in their place. A subject longer than 60 characters is cut with `…`.
- A fetch, and every other ssh command, runs plain ssh, under no name. So does every `op-ssh-sign` command other than `-Y sign`, such as verification.

## How

1Password names the program at the top of the chain of parent processes that it can follow from the request. `run` copies Windows PowerShell to `%TEMP%\1p-contextual\<pid>\<name>.exe` and starts it through a helper process that exits at once. So the copy has no living parent, and 1Password stops there and shows its name. The copy runs the real ssh or `op-ssh-sign`, waits for it, and stays until `run` has opened it, so the exit status reaches git even when the program exits at once. Then `run` deletes the copy.

The copy is Windows PowerShell, which Microsoft signs, so Smart App Control lets it run. A copy with its own icon would need its own signature from a certificate authority that Windows trusts.

## Limits

- It relies on how 1Password names a requester, which 1Password does not document.
- The prompt shows the PowerShell icon.
- Each push or signature starts three PowerShell processes, which adds about 0.8 seconds.
- After you tick "Approve for all applications" in a prompt, 1Password stops asking, so no name shows.

## Tests

```powershell
Invoke-Pester root/~/dot_local/libexec/1p-contextual
```

The tests run on Windows with Git for Windows. They push to an unresolvable host, and sign with a stand-in signer, so they need no network and no 1Password. `OP_SSH_SIGN_CONTEXTUAL_PROGRAM` sets the stand-in.
