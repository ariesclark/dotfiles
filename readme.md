# dotfiles (`next`)

This repository contains the configuration of a Windows computer and of its WSL distribution. [chezmoi](https://www.chezmoi.io/) applies it.

## Install

1. Open Windows PowerShell.
2. Get chezmoi:

   ```powershell
   iex "&{$(irm 'https://get.chezmoi.io/ps1')} -b '$env:TEMP'"
   ```

3. Apply the configuration:

   ```powershell
   & "$env:TEMP\chezmoi.exe" init --apply --branch next ariesclark/dotfiles
   ```

4. Type the groups for the computer.
5. Type yes or no to let chezmoi change the partitions.
6. Approve each administrator prompt.
7. Sign in to 1Password.
8. In 1Password, set the SSH agent and the CLI integration to on.
9. Type `gh auth login` and sign in to GitHub.
10. Sign in to Steam.

## Files

- [`home/`](home): the chezmoi [source state](https://www.chezmoi.io/reference/source-state-attributes/). Each file name gives the target in `~`.
  - [`.chezmoidata/`](home/.chezmoidata): the [data](https://www.chezmoi.io/reference/special-files/chezmoidata-format/) for the templates and scripts.
    - [`system.yaml`](home/.chezmoidata/system.yaml): the volumes by drive letter, with label, size and pagefile. The install folders for Scoop and winget. The WSL distribution: its user, drive letter, read-only Windows folders and apt packages.
    - [`groups.yaml`](home/.chezmoidata/groups.yaml): the groups of packages, as `source:id` (Scoop, winget, Microsoft Store, Steam). A group can need other groups.
    - [`apps.yaml`](home/.chezmoidata/apps.yaml): the settings of each package. These are registrations (right-click menus, startup entries, URL handlers), mounts (junctions to other drives) and install options.
  - [`.chezmoiscripts/`](home/.chezmoiscripts): the [scripts](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/) that are not for one file. They do the partitions, packages, registrations and WinGet configuration. On Linux, a script installs [Vite+](https://viteplus.dev/guide/), which supplies `node` and `pnpm`. A script for one file is next to that file.
  - [`dot_config/windows/`](home/dot_config/windows): the Windows settings.
    - [`readonly_configuration.winget.tmpl`](home/dot_config/windows/readonly_configuration.winget.tmpl): a [WinGet configuration](https://learn.microsoft.com/en-us/windows/package-manager/configuration/) file. It sets the taskbar, the environment variables, the startup entries to keep off and the [taskbar pin policy](https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps).
    - [`readonly_taskbar.xml.tmpl`](home/dot_config/windows/readonly_taskbar.xml.tmpl): the taskbar pins, in order.
- [`root/`](root): a second chezmoi source for `/` in the WSL distribution. Root applies it inside the distribution, from this checkout. The Windows apply starts it. It sets `wsl.conf`, the read-only Windows mounts, the apt packages, GitHub's apt repository for `gh` and rootless Docker for the `dockerd` user. A script `run_onchange_after_<file>.sh.tmpl` runs again when the file `<file>` next to it changes.
- [`windows/`](windows): the PowerShell modules for the scripts, and their [Pester](https://pester.dev/) tests.
- [`docs/goals.md`](docs/goals.md): the planned work.

## Apply

One `chezmoi apply` on Windows does these steps, in this order:

1. The scripts before the files: partitions, volumes and the pagefile, Scoop, the packages.
2. The files from `home/` go into `~`. This includes `.wslconfig`.
3. The scripts after the files: read-only attributes, registrations, `user.reg`, `winget configure`, the taskbar pins (only when the pins change).
4. The WSL script ([`run_after_wsl.ps1.tmpl`](home/run_after_wsl.ps1.tmpl)) runs on each apply:
   1. It mounts this checkout, read-only, at `/mnt/windows/dotfiles` in the distribution, if the mount is not there.
   2. It installs chezmoi in the distribution, at the same version as on Windows, if that version is not there.
   3. It applies `root/` to `/` as root, inside the distribution. This apply has its own state and cache. It gets its data from [`wsl-root-data`](home/.chezmoitemplates/wsl-root-data).
   4. It applies `home/` to `~` as `aries`, inside the distribution, from the same checkout. First, `chezmoi init` writes the configuration for Linux. This configuration has no questions, and it reads 1Password through the mounted `op.exe`.
   5. If `wsl.conf` changed, it stops WSL. The change starts on the next start of the distribution.

The apply of `root/` does these steps, in this order:

1. The scripts before the files: the apt packages, and the `dockerd` user with its group, lingering and access to `~/repos`.
2. The files go into `/`: `wsl.conf`, `fstab`, the apt source for `gh`, and the service and socket of `dockerd`.
3. The scripts after the files, each one only when its file changed: install `gh`, mount the Windows folders again, ask Windows to stop WSL, start the Docker service of `dockerd` again.

In the distribution, the user `aries` has no drives from Windows. It has only the read-only folders in `/mnt/windows`, and no Windows folders in `PATH`. Links in `~/.local/bin` give it `op`, `ssh.exe`, `op-ssh-sign-wsl.exe` and `code` from these folders. The user `dockerd` runs Docker without root. `aries` uses it through the socket `/run/dockerd/docker.sock`. Containers can use `~/repos`, but not the other files in `~`.

## Rules

- Keep on C: only the data that you cannot move.
- To see the changes before you apply them, type `chezmoi diff`.
- To see all the files that chezmoi makes, type `pwsh windows/archive.ps1`. The files for `~` go into `home/.archive`, and the files for `/` in the WSL distribution go into `home/.archive/root`. Symbolic links are not in the preview, because Windows cannot make them without administrator rights.
- To do the tests, type `Invoke-Pester windows`.
