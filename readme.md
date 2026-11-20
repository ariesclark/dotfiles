# dotfiles

This repository contains the configuration of a Windows computer and of its WSL distribution. [cheznous](https://github.com/ariesclark/cheznous) applies it. cheznous is [chezmoi](https://www.chezmoi.io/) with [group directories](https://github.com/ariesclark/cheznous/blob/master/CHEZNOUS.md#groups) and a [`~` directory](https://github.com/ariesclark/cheznous/blob/master/CHEZNOUS.md#the--directory) for one source tree for `/` and `~`, and it installs as both `cheznous` and `chezmoi`.

## Install

1. Open Windows PowerShell.
2. Get cheznous:

   ```powershell
   iex "&{$(irm 'https://raw.githubusercontent.com/ariesclark/cheznous/master/assets/scripts/install.ps1')} -b '$env:TEMP'"
   ```

3. Apply the configuration:

   ```powershell
   & "$env:TEMP\cheznous.exe" init --apply ariesclark/dotfiles
   ```

4. Type the groups for the computer.
5. Type yes or no to let chezmoi change the partitions.
6. Approve each administrator prompt.
7. Sign in to 1Password.
8. In 1Password, set the SSH agent and the CLI integration to on.
9. Type `gh auth login` and sign in to GitHub.
10. Sign in to Steam.

## Files

- [`root/`](root): the [source state](https://www.chezmoi.io/reference/source-state-attributes/), one tree for `/`. Each file name gives the target from `/`, and [`~/`](root/~) is the home directory. The files for Windows only are in the group [``(eq .chezmoi.os `windows`)``](<root/~/(eq .chezmoi.os `windows`)>), and the files for Linux only are in [``(eq .chezmoi.os `linux`)``](<root/~/(eq .chezmoi.os `linux`)>). The other files in `~` are for both.
  - [`.chezmoidata/`](root/.chezmoidata): the [data](https://www.chezmoi.io/reference/special-files/chezmoidata-format/) for the templates and scripts.
    - [`system.yaml`](root/.chezmoidata/system.yaml): the volumes by drive letter, with label, size and pagefile. The install folders for Scoop and winget. The cheznous version for Windows. The WSL distribution: its user, drive letter, read-only Windows folders, apt packages and memory limits. Each memory limit is a size like `12GB`, a percent, or `auto`, which leaves it to WSL or systemd. `memory` and `swap` are for the WSL VM; a percent is of the Windows memory, rounded down to whole GB, and `auto` is WSL's default (50% and 25%). `docker.memory` and `docker.swap` are for all containers together, and `docker.container` for each container; a percent of memory is of the limit above it (the VM memory for all containers, and the limit of all containers for each one, or the VM memory when that is `auto`), swap takes no percent, and `auto` is no limit.
    - [`groups.yaml`](root/.chezmoidata/groups.yaml): the groups of packages, as `source:id` (Scoop, winget, Microsoft Store, Steam). A group can need other groups.
    - [`apps.yaml`](root/.chezmoidata/apps.yaml): the settings of each package. These are registrations (right-click menus, startup entries, URL handlers), mounts (junctions to other drives) and install options.
  - `.chezmoiscripts/` in each group: the [scripts](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/) that are not for one file. On Windows, they install cheznous into `E:\Apps\cheznous` and do the partitions, packages, registrations and WinGet configuration. On Linux, they install [Vite+](https://viteplus.dev/guide/) (which supplies `node`, `pnpm` and `bun`), uv, the Pulumi CLI, the Proton Pass CLI, the stable Rust toolchain, `playwright-cli` and its Claude skill, and the [asdf](https://asdf-vm.com/) plugins for Erlang, Elixir and Go. asdf itself, flyctl (`fly`) and jadx are pinned releases in [`.chezmoiexternal.toml.tmpl`](<root/~/(eq .chezmoi.os `linux`)/.chezmoiexternal.toml.tmpl>); each project's `.tool-versions` picks the versions, and `asdf install` in the project builds them. A script for one file is next to that file.
  - [`dot_config/windows/`](<root/~/(eq .chezmoi.os `windows`)/dot_config/windows>): the Windows settings.
    - [`readonly_configuration.winget.tmpl`](<root/~/(eq .chezmoi.os `windows`)/dot_config/windows/readonly_configuration.winget.tmpl>): a [WinGet configuration](https://learn.microsoft.com/en-us/windows/package-manager/configuration/) file. It sets the taskbar, the Chromium and Firefox policies, the environment variables, the startup entries to keep off and the [taskbar pin policy](https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps).
    - [`readonly_taskbar.xml.tmpl`](<root/~/(eq .chezmoi.os `windows`)/dot_config/windows/readonly_taskbar.xml.tmpl>): the taskbar pins, in order.
  - [``(eq .chezmoi.os `linux`)``](<root/(eq .chezmoi.os `linux`)>) outside `~`: the files for `/` in the WSL distribution. They set `wsl.conf`, the apt packages, GitHub's apt repository for `gh`, the [Git PPA](https://launchpad.net/~git-core/+archive/ubuntu/ppa) for a newer `git`, rootless Docker for the `dockerd` user, `/tmp` on disk instead of in memory, ports from 80 open to unprivileged processes, and the memory limits. [`.wslconfig`](<root/~/(eq .chezmoi.os `windows`)/dot_wslconfig.tmpl>) gives the WSL VM 50% of the Windows memory and 4 GB of swap on disk, so it leaves room for Windows. In the VM, zram adds 8 GB of compressed swap in memory, which is used before the swap on disk. Its service creates `/dev/zram0` again when a restart has reset it away. earlyoom stops the largest process when less than 10% of memory and less than 50% of swap are free, before the VM stalls. All Docker containers together get at most 50% of the VM memory and 2 GB of swap, and each container at most 25% of that and 1 GB of swap, unless `docker run --memory` gives it its own limit. Background reclaim starts earlier than the kernel default. A script `run_onchange_after_<file>.sh.tmpl` runs again when the file `<file>` next to it changes.
- [`windows/`](windows): the PowerShell modules for the scripts, and their [Pester](https://pester.dev/) tests.
- [`docs/goals.md`](docs/goals.md): the planned work.

## Apply

One `chezmoi apply` on Windows does these steps, in this order:

1. The scripts before the files: partitions, volumes and the pagefile, cheznous (only when its version in `system.yaml` changes), Scoop, the packages.
2. The files from `root/~/` go into `~`. This includes `.wslconfig`.
3. The scripts after the files: read-only attributes, registrations, `user.reg`, `winget configure`, the taskbar pins (only when the pins change).
4. The WSL script ([`run_after_wsl.ps1.tmpl`](<root/~/(eq .chezmoi.os `windows`)/run_after_wsl.ps1.tmpl>)) runs on each apply:
   1. It finds this checkout in the distribution with `wslpath`, under WSL's mount of its drive, such as `/mnt/c`.
   2. It installs cheznous in the distribution, at the same version as on Windows, if that version is not there.
   3. As `aries`, `chezmoi init` writes the configuration for Linux. This configuration has no questions, and it reads 1Password through `op.exe` on the Windows `PATH`.
   4. As root, with `HOME` set to `/home/aries`, it applies the whole tree to `/`, from the same checkout. This apply has its own state and cache. It gives `aries` everything it writes in `~`, and runs the scripts from `root/~/` as `aries`.
   5. If `wsl.conf` changed, it stops WSL. The change starts on the next start of the distribution.

The apply in the distribution does these steps, in this order:

1. The scripts before the files, as root: the apt packages, and the `dockerd` user with its group, lingering and access to `~/repos`.
2. The files: into `/`, `wsl.conf`, the apt sources for `gh` and `git`, the service and socket of `dockerd`, the memory limits of its containers, the zram swap service, the earlyoom thresholds, and the sysctl settings for unprivileged ports and memory reclaim; into `~`, the files from `root/~/`.
3. The scripts after the files. As root, each one only when its file changed: install `gh`, install `git` from the PPA, ask Windows to stop WSL, start the Docker service of `dockerd` again, reload the systemd of `dockerd` for the container limits, start the zram swap again, start earlyoom again, load each sysctl setting. As `aries`, on each apply: the tools for `~`.

In the distribution, WSL mounts the Windows drives at `/mnt/<letter>` and appends the Windows `PATH`, so `xdg-open` opens links in the Windows default browser, and the Windows tools run by name: `ssh.exe`, `op.exe`, `op-ssh-sign-wsl.exe`, `code`. In an interactive bash, a name that is not found runs as the Windows tool `<name>.exe` when there is one, so `op` runs `op.exe`. Otherwise Ubuntu's command-not-found answers. `playwright-cli` drives Playwright's own Chromium, headless, inside the distribution. After that apply, the Windows apply runs Playwright's installer as root, which installs that Chromium in `/opt/ms-playwright` and the Linux packages it needs. The user `dockerd` runs Docker without root. `aries` uses it through the socket `/run/dockerd/docker.sock`. Containers can use `~/repos`, but not the other files in `~`.

## Rules

- Keep on C: only the data that you cannot move.
- To see the changes before you apply them, type `chezmoi diff`.
- To see all the files that chezmoi makes, type `pwsh windows/archive.ps1`. The files for `~` go into `root/.archive`, and the files for the WSL distribution go into `root/.archive/wsl`, with `~` in `root/.archive/wsl/home/aries`. The WSL ones are made by cheznous in WSL, because `--override-data '{"chezmoi":{"os":"linux"}}'` switches the groups but keeps the Windows home directory and other `.chezmoi` values. Symbolic links are not in the preview, because Windows cannot make them without administrator rights.
- To do the tests, type `Invoke-Pester windows`.
