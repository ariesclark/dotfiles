# Goals

This file contains the planned work. The [readme](../readme.md) tells what the repository does now.

## Computer

- Move this repository to `D:\Code\dotfiles`. Set the chezmoi `sourceDir` to that folder.
- Move the known folders (Documents, Pictures and others) to `D:\Users`. Windows moved them back to OneDrive on 2026-10-17.
- Put CurseForge on E:. Put the Claude MSIX package on E:.
- Install Docker without Docker Desktop. Get the CLI, compose and buildx from [Scoop](https://scoop.sh/). Run the Docker Engine in the WSL distribution on `D:\WSL`. Docker Desktop was removed on 2026-10-19, because Scoop does not supply it.
- Make a mount for the Claude Code data (`~\.claude`) on D:.
- Make a mount for the Steam `config` folder. Scoop does not keep this folder when Steam changes version, and Steam then forgets the account.
- Declare the remaining Windows settings in [`configuration.winget`](../home/dot_config/windows/readonly_configuration.winget.tmpl).
- Apply configuration files outside `~`. Use a second chezmoi source (for example `drives/e/`) with `--destination E:\` and its own state. Start with the Scoop `persist` folders of Firefox and VS Code.
- Make the Claude Code status line and scratch helper work on Windows. Now they are bash scripts for WSL only.
- Shrink C: to the size in `system.yaml` on a computer that has D: and E: already. When Windows refuses, read the cause in the Defrag event log (ID 259). Then remove what is safe to remove: hibernation file, restore points, change journal (`fsutil usn deletejournal`). Ask for a restart and finish on the next apply. On 2026-10-19 this was done by hand, from 500 GB to 200 GB.
- Do the partitions, Scoop and the 1Password CLI in a [`read-source-state.pre` hook](https://www.chezmoi.io/user-guide/advanced/install-your-password-manager-on-init/). Then they are ready before chezmoi reads the templates.
- Write an `autounattend.xml`. Then do a Windows reset to prove the full repository.

## WSL

- Install WSL. Import the distribution from the laptop to `D:\WSL\Ubuntu`.
- Mount `E:\WSL\cache.vhdx` at `~/.cache`.

## Repository

- Move the old dotfiles from `main` into `home/`. Then merge `next`.
- Make backups with restic to Cloudflare R2.
- Add Renovate and CI.

## Packages

These packages are not in Scoop: Caido, nRF Connect, SEGGER J-Link, VRChat Creator Companion, T3 Code, Buzz, Paper, AngKorGit.

## 1Password for all secrets

Each tool that needs a secret or a sign-in gets it from 1Password. Windows Hello unlocks 1Password. After a reset, the only sign-in is to unlock 1Password one time.

### Rules

- Keep only references (`op://vault/item/field`) in the repository. Do not keep secrets. A reference is safe to commit.
- Read secrets when chezmoi applies or when the tool runs. Use the [CLI integration](https://www.1password.dev/cli/app-integration-security/) of the desktop app. Do not keep a service account token or an exported secret on the disk.
- If a tool can call 1Password (SSH agent, shell plugin, password command), use that. Write a secret into a file only if the tool can read nothing else. Keep that file out of backups that leave the computer.

### Methods

| Method | Result | Use |
|---|---|---|
| [`onepasswordRead`](https://www.chezmoi.io/reference/templates/1password-functions/onepasswordRead/) in a template | The secret is in the file after an apply | Configuration files that need the secret as text |
| [SSH agent](https://www.1password.dev/ssh/agent/) | The SSH keys stay in 1Password | git over SSH, servers |
| [Shell plugins](https://www.1password.dev/cli/shell-plugins/) (`op plugin init`) | The CLI gets its credentials for each command | gh, tools for R2 |
| `op run`, `op inject` | Environment variables or files that get their secrets at run time | `.env` files, scripts |
| Password commands (`op read`) | The tool gets the secret when it needs it | restic (`RESTIC_PASSWORD_COMMAND`) |
| Browser extension | Autofill and passkeys | Firefox, set to on with `policies.json` |

### Work to do

| Tool | Method |
|---|---|
| git over SSH, GitHub | SSH agent |
| gh | Shell plugin. Now gh keeps a token in Windows Credential Manager. |
| restic to R2 | Password command, and the R2 keys from 1Password |
| ShareX uploader to R2 | Uploader configuration from a template. Now the secret is only in the `.sxb` file. |
| Firefox | 1Password extension, set to on with a policy |
| WSL | The Windows SSH agent, and `op.exe` for secrets |
| npm, pnpm, Docker registries | `op inject` into `.npmrc`, or a credential helper |
| Steam, Discord, Riot | Autofill only. Sign in one time by hand. |

### Questions

- Do machine secrets go in their own vault, or in the main vault with a tag?
- Can `op` get Windows Hello approval when the apply runs with no person at the computer (for example from Renovate)? If not, those applies must skip the secret templates.
