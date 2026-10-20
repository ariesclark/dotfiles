# dotfiles (`next`)

This repository contains the configuration of a Windows computer. [chezmoi](https://www.chezmoi.io/) applies it.

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
    - [`system.yaml`](home/.chezmoidata/system.yaml): the volumes by drive letter, with label, size and pagefile. The install folders for Scoop and winget.
    - [`groups.yaml`](home/.chezmoidata/groups.yaml): the groups of packages, as `source:id` (Scoop, winget, Microsoft Store, Steam). A group can need other groups.
    - [`apps.yaml`](home/.chezmoidata/apps.yaml): the settings of each package. These are registrations (right-click menus, startup entries, URL handlers), mounts (junctions to other drives) and install options.
  - [`.chezmoiscripts/`](home/.chezmoiscripts): the [scripts](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/) that chezmoi runs. They do the partitions, packages, registrations and WinGet configuration.
  - [`dot_config/windows/`](home/dot_config/windows): the Windows settings.
    - [`readonly_configuration.winget.tmpl`](home/dot_config/windows/readonly_configuration.winget.tmpl): a [WinGet configuration](https://learn.microsoft.com/en-us/windows/package-manager/configuration/) file. It sets the taskbar, the environment variables, the startup entries to keep off and the [taskbar pin policy](https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps).
    - [`readonly_taskbar.xml.tmpl`](home/dot_config/windows/readonly_taskbar.xml.tmpl): the taskbar pins, in order.
- [`windows/`](windows): the PowerShell modules for the scripts, and their [Pester](https://pester.dev/) tests.
- [`docs/goals.md`](docs/goals.md): the planned work.

## Rules

- Keep on C: only the data that you cannot move.
- To see the changes before you apply them, type `chezmoi diff`.
- To do the tests, type `Invoke-Pester windows`.
