# Goals

Where this repo is heading. Nothing here is done yet; the [readme](../readme.md) describes what is.

## Machine

- Move this repo to `D:\Code\dotfiles` and point chezmoi's `sourceDir` at it.
- Known folders → `D:\Users\*` (Windows reverted them to `C:\Users\aries\OneDrive\*` on 2026-10-17).
- Install location on E: for CurseForge; Claude's MSIX on E:.
- Docker without Docker Desktop: the CLI, compose and buildx from Scoop (`main/docker`, `main/docker-compose`,
  `main/docker-buildx`), talking to a Docker Engine inside the WSL distro on `D:\WSL`, configured by this repo.
  Docker Desktop was uninstalled on 2026-10-19 because Scoop doesn't package it and it can't be fully declared.
- Declare winget install locations (`--location`), so a fresh League install lands in `E:\Games\Riot`
  (moved there by hand on 2026-10-18). VALORANT has no winget package; the Riot Client installs it.
- Claude Code data (`~\.claude`) as a placement on D:.
- Declare Windows settings now made by hand.
- Configs outside `~` as chezmoi files: a second source (e.g. `drives/e/`) applied with `--destination E:\` and
  its own state, run from the main apply. First targets: Scoop's persist folders (Firefox, VS Code).
- Claude Code's status line and scratch helper on Windows (both are bash scripts today, kept for WSL).
- Unset user environment variables that leave `layout.environment`, the way packages that leave a group are
  uninstalled (track the applied set in `D:\Machine`). Today a removed variable stays set until removed by hand.
- Shrink C: to `layout.yaml`'s size on an existing machine, not only when creating D: and E:. When Windows
  refuses, read the blocker from the Defrag event log (ID 259) and clear what's safe to clear: the pagefile,
  the hibernation file, restore points, and the change journal (`fsutil usn deletejournal`, then recreate it).
  Then ask for a restart, finish on the next apply, and turn the pagefile back on. Done by hand on 2026-10-19,
  500 → 200 GB, in that order of blockers.
- `autounattend.xml`, then prove the whole repo with a Windows reset.

## WSL

- Install, import the laptop distro to `D:\WSL\Ubuntu`.
- Mount `E:\WSL\cache.vhdx` at `~/.cache`.

## Repo

- Migrate the old dotfiles from `main` into `home/`, then merge `next`.
- Backups: restic → R2.
- Renovate + CI.

## Apps

Not found in Scoop yet: Caido, nRF Connect, SEGGER J-Link, VRChat Creator Companion, T3 Code, Buzz, Paper, AngKorGit.

## 1Password as the one source of secrets

Everything that needs a secret or a sign-in gets it from 1Password, unlocked by Windows Hello. After a reset,
unlocking 1Password once should be the only sign-in a tool needs.

**Rules**

- The repo holds references (`op://vault/item/field`), never secrets. A reference is safe to commit.
- Secrets are read at apply time or run time, through the desktop app's CLI integration (`op` asks Windows Hello).
  No service account token or exported secret on disk.
- Where a tool can call 1Password itself (SSH agent, shell plugins, password commands), prefer that over
  writing the secret into its config. Write a secret into a file only when the tool can read nothing else, and
  then keep that file out of backups that leave the machine.

**Building blocks**

| Mechanism | Gives | Use for |
|---|---|---|
| chezmoi `onepasswordRead` in templates | a secret rendered into a file on apply | configs that only take a literal secret |
| SSH agent (`\\.\pipe\openssh-ssh-agent`) | SSH keys that never leave 1Password | git over SSH, servers |
| `op-ssh-sign` | SSH commit signing | git |
| shell plugins (`op plugin init`) | CLIs authenticated per call | gh, aws-compatible tools (R2) |
| `op run` / `op inject` | env vars or files resolved at run time | `.env` files, one-off scripts |
| password commands (`op read …`) | a secret on demand | restic (`RESTIC_PASSWORD_COMMAND`) |
| browser extension | autofill and passkeys | Firefox, forced on through `policies.json` |

**Targets**

| Thing | How |
|---|---|
| git commit signing | `op-ssh-sign` (in the lnk config on `main`, to port) |
| git over SSH, GitHub | SSH agent |
| gh | shell plugin, no stored token |
| restic → R2 | password command + R2 keys from 1Password |
| ShareX → R2 uploader | uploader config templated from 1Password (the secret now lives only in the `.sxb`) |
| Firefox | 1Password extension forced on via policy |
| WSL | Windows SSH agent bridged in, `op.exe` for secrets |
| npm / pnpm, Docker registries | `op inject` into `.npmrc`, credential helper, when needed |
| apps without integration (Steam, Discord, Riot) | autofill only; sign in by hand once |

**Open questions**

- One vault for machine secrets, or items tagged in the main one?
- First apply on a fresh machine: 1Password is installed by the same apply that needs it. Either split secret
  templates into a later apply or skip them until `op` is signed in.
- Does `op` reach Windows Hello from an unattended apply (Renovate-triggered, no one at the keyboard)? If not,
  those applies skip secret templates.
