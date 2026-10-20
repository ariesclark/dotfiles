# dotfiles (`next`)

The whole machine, declared. Edit a file, run `chezmoi apply`, and the machine matches it.
This branch replaces the lnk setup on `main` and gets merged once it's proven by a Windows reset.

## Drives

Each drive is a lifecycle. Volumes are found by label, so they can be partitions or separate disks.

| Drive | Label | Holds | Rule |
|---|---|---|---|
| C: | Windows | Windows, and only what can't be moved to E: | Wiped by a reset; every exception is recorded with its reason |
| D: | Data | your files (`D:\Users`), package state (`D:\Machine`) | Backed up |
| E: | Apps & Cache | Scoop apps and their state (`E:\Scoop`), games | Replaceable |

## Layout

```
home/                               chezmoi source (.chezmoiroot) — mirrors ~
  .chezmoi.yaml.tmpl                per-machine config; asks once for groups and partition opt-in
  .chezmoidata/layout.yaml          volumes, labels, Scoop root, winget folder, placements, state file
  .chezmoidata/groups.yaml          groups → apps, and what each group needs
  .chezmoidata/apps.yaml            per-app config: what it registers with Windows, where it installs
  .chezmoidata/desktop.yaml         taskbar settings and pins, startup entries to keep off
  .chezmoitemplates/                only templates several files share: merge-json, glob-hash, generated
  .chezmoiremove                    targets to delete (configs that moved)
  dot_claude/, dot_config/, AppData/   the configs, each next to whatever it's rendered from (see Configs)
  .archive/                         what chezmoi renders on this machine, as it lands under ~ (git-ignored)
  .chezmoiscripts/
    run_before_00-partition         creates missing volumes (opt-in, elevates only this step)
    run_onchange_before_10-layout   volume labels, Scoop itself, placements
    run_onchange_before_20-packages groups → install / uninstall
    run_after_30-registrations      vendor .reg/.ps1 files, stale packages, shims (every apply)
    run_onchange_after_35-user-registry   imports the rendered user.reg, sets the taskbar policy
    run_after_40-desktop            keeps desktop.yaml's startup entries off (every apply)
    run_after_99-archive            rebuilds .archive/ from one chezmoi archive (every apply)
docs/goals.md                       what's planned
windows/                            one module per job, each with its Pester tests
  volumes.psm1                      volume checks, labels, partitioning
  environment.psm1                  user environment variables (TEMP on E:)
  placements.psm1                   junctions from app folders to their targets
  packages.psm1                     groups → desired apps → what to install and uninstall
  scoop.psm1, winget.psm1, steam.psm1   installing and uninstalling from each source
  registrations.psm1                what apps register with Windows (from apps.yaml)
  startup.psm1, taskbar.psm1        startup entries to keep off; the taskbar layout policy
  archive.psm1                      unpacks that archive into .archive/
  data.tests.ps1                    checks on the YAML itself
  templates.tests.ps1               checks on what the templates render
```

All configuration is YAML, parsed only by chezmoi: each script receives just the parts it uses, rendered
as JSON, so the modules need no YAML library. A `run_onchange_` script reruns when that data changes or when
any module in `windows/` does: it embeds one hash of `windows/*.psm1` (`.chezmoitemplates/glob-hash`), so it
doesn't need to know which modules its functions use.
The modules work in PowerShell 7 and in Windows PowerShell 5.1, which chezmoi runs scripts with. The scripts
render to nothing outside Windows.

**Partitioning** runs on every apply but only acts when a declared volume is missing. Then it prints the plan
and, if this machine opted in (`machine.partition: true`), runs just that step as admin: it shrinks C: and
creates the missing volumes in the freed space, never deleting or formatting an existing one. Without the
opt-in it stops the apply with the plan and how to opt in.

## Everyday use

| To | Do |
|---|---|
| add or remove an app | edit `groups.yaml`, then `chezmoi apply` |
| register an app with Windows | add it to `apps.yaml`, then `chezmoi apply` |
| opt this machine in or out of a group | `chezmoi edit-config` → `machine.groups`, then `chezmoi apply` |
| allow or forbid partitioning | `chezmoi edit-config` → `machine.partition` |
| change a config | edit it under `home/` (or `chezmoi edit <file>`), then `chezmoi apply` |
| see what will land | `chezmoi diff`, or look in `home/.archive/` after an apply |
| run the tests | `Invoke-Pester windows` |

Removal only touches apps this repo installed: the last applied set is kept in `D:\Machine\packages.json` (JSON — the module's own state, never hand-edited),
and anything you installed by hand is never uninstalled.

## Apps and groups

A group in `groups.yaml` lists its `apps` as `source:id` (`scoop:extras/discord`, `winget:Cloudflare.Warp`,
`msstore:9P8LTPGCBZXD`, `steam:431960`) and the groups it `needs`. A machine installs the apps of the groups it selects,
plus everything those groups need. Each app sits in one group. This machine: `personal, tools, security, hardware, games, vrchat-dev`.

| Group | Needs | Apps |
|---|---|---|
| base | — | 7-Zip, git, gh, chezmoi, restic, jq, pwsh, 1Password + CLI, PowerToys, Firefox, VLC, ImageGlass, Claude, Wintoys |
| personal | base | Discord (winget), ShareX, Proton Mail Bridge, Cloudflare WARP |
| tools | base | HWiNFO, CrystalDiskMark, WinDirStat |
| games-base | base | Steam, Minecraft launcher, CurseForge |
| games | games-base | League of Legends, VALORANT, Wallpaper Engine, Baldur's Gate 3, PUBG |
| dev | base | VS Code, uv, Pester, .NET SDK, ffmpeg, WinSCP, MongoDB Compass |
| unity | dev | — |
| security | dev | — |
| hardware | dev | — |
| vrchat | games-base | VRChat (Steam), VRCX |
| vrchat-dev | vrchat, unity | — |

**Registrations** are what an app registers with Windows outside its own folder: right-click menus, file
associations, startup entries, URL handlers. Scoop installs apps into their own folder and never touches the
registry; apps that need these ship a `.reg` or `.ps1` and leave running it to you. `apps.yaml` declares them,
keyed by the same `source:id`, pointing at the app's `current` folder so updates keep them working. Startup
entries and URL handlers are rendered into `user.reg`; the rest (vendor files, stale packages, shims) needs the
registrations script:

```yaml
scoop:extras/powertoys:
  removeAppx:                                    # stale packages: other versions than the ones the app ships
    - Microsoft.PowerToys.*ContextMenu
  scripts:                                       # files inside the app's current folder
    - path: install-context.ps1
      skipWhenRegistered:                        # skipped while these .msix are registered at their version
        - WinUI3Apps\ImageResizerContextMenuPackage.msix
        - WinUI3Apps\PowerRenameContextMenuPackage.msix
  startup:                                       # HKCU Run entries
    - name: PowerToys
      path: PowerToys.exe
  # also: registry (.reg files in the app folder), shims (copy a Scoop shim into another folder),
  # protocols (url handlers like steam://)
```

Only Scoop apps take registrations; vendor installers register themselves. To set keys in any app's own settings
file, use a `modify_` template (see Configs).

**Scoop by default.** winget and the Store only for apps that need a vendor installer: 1Password (SSH agent,
browser integration), WARP (network driver), League (Vanguard driver),
CurseForge (no Scoop manifest), Claude (self-updating MSIX), Wintoys (Store only).

**Installs stay off C:** where the installer allows it. Each winget app installs to its own folder under
`layout.winget` (`E:\Apps\<id>`, passed as winget `--location`). `apps.yaml` only lists the exceptions:

| Key | Use for | Apps |
|---|---|---|
| `location` | a folder other than `E:\Apps\<id>` | League, VALORANT (`E:\Games\Riot`) |
| `installerType: msix` | picking the MSIX package over the app's other installers | 1Password, Claude |
| `fixedLocation: true` | installers with no folder option: winget passes no `--location`, and it stays on C: | Discord |

MSIX packages and Store apps (Claude, 1Password, Wintoys) stay on C:, in `C:\Program Files\WindowsApps`.
Windows can put them on another drive, but only by turning it into an app volume: three locked folders at its
root (`WindowsApps`, `WpSystem`, `Program Files`), and some packages, like Wintoys, refuse to leave C: anyway.
1Password's MSI can't leave C: either (its app folder is fixed to Program Files); the MSIX keeps itself updated.

**Steam games** (`steam:<appid>`, the number in the store URL) go through the Steam client: apply opens
Steam's install or uninstall dialog for each change and you confirm it there; the download then runs in
Steam. A game counts as installed once its `appmanifest_<appid>.acf` is in a Steam library. They need
`scoop:games/steam` in a selected group, and you signed in to Steam.

Discord is the regular install from winget, on C: in `%LocalAppData%\Discord` (its Squirrel installer has no
folder option). Scoop's portable build was tried and dropped: Discord's Electron rewrites a Start shortcut to
its own exe on every launch, which bypasses the portable launcher.

## Desktop

`desktop.yaml` declares the taskbar and what starts at sign-in.

- **Taskbar settings** (alignment, search, Task View, Widgets, Copilot) render into `~\.config\windows\user.reg`,
  with the Scoop apps' startup entries and URL handlers; `run_onchange_after_35-user-registry` imports it
  whenever it changes and restarts Explorer.
- **Pins** render into `~\.config\windows\taskbar.xml`, which the Start layout policy points at; Windows applies
  it at sign-in, replacing whatever was pinned. Setting the policy takes one admin prompt, once.
- **Startup entries to keep off** stay a script (`run_after_40-desktop`, every apply), because names can be
  wildcards (Edge's carries a per-install id) and some live machine-wide: they get Settings > Startup's "off"
  flag, so an app re-adding its entry stays off, and logon tasks are disabled.

## Configs

Configs are chezmoi files under `home/`, mirroring `~`:

| Config | Source | How |
|---|---|---|
| git | `dot_config/git/config.tmpl`, `ignore.tmpl`, `allowed_signers.tmpl` | one file; the signing key comes from 1Password (`op://personal/rczscaa2ex5o5gqxuoo5aa6xmu/public key`) at apply time; the Windows block (signing through 1Password's `op-ssh-sign`, Windows' OpenSSH) and the WSL block are inline conditionals; `allowed_signers` trusts that key for git signatures |
| gh | `dot_config/gh/config.yml.tmpl` | on Windows, `AppData/Roaming/GitHub CLI/config.yml.tmpl` renders it again |
| Claude Code | `dot_claude/CLAUDE.md.tmpl`, `dot_claude/settings.yaml` + `modify_settings.json` | `modify_`: `settings.yaml` (never written to `~`) wins over the live file, keys Claude Code adds are kept; its Linux-only extras only on Linux |
| Windows Terminal | `AppData/Local/Packages/…/modify_settings.json` | `modify_`: default profile PowerShell 7, inline |
| Discord | `AppData/Roaming/discord/modify_settings.json` | `modify_`: starts minimized, closes to tray, inline; only once Discord is installed |
| editorconfig | `dot_editorconfig.tmpl` | as is |
| bash, WSL | `dot_bashrc.d/`, `dot_profile.d/`, `dot_claude/executable_*` | kept for Linux and WSL, ignored on Windows (`.chezmoiignore`) |

Every config opens with two lines naming its source and when that source last changed (`.chezmoitemplates/generated`, in the file's own comment syntax),
except JSON, which has no comments. A `modify_` template reads the app's current file and changes only what it declares (`.chezmoitemplates/merge-json`),
so the app can keep writing its own state. `.chezmoidata` holds only what several files and scripts read:
`layout`, `groups`, `apps`, `desktop`. chezmoi writes only under one destination (`~` here); configs elsewhere, like Scoop's
persist folders on E:, are a goal (a second source with its own destination).

## Placements

A placement makes an app folder a junction to a target, creating the target first. It never replaces a folder
that has contents.

| Placement | Link | Target |
|---|---|---|
| ShareX | `E:\Scoop\persist\sharex\ShareX` | `D:\Users\Documents\ShareX` |
| Steam library | `E:\Scoop\persist\steam\steamapps` | `E:\Games\Steam` |
| Steam web cache | `%LOCALAPPDATA%\Steam` | `E:\Cache\Steam` |
| PUBG settings, logs and replays | `%LOCALAPPDATA%\TslGame` | `E:\Games\PUBG` |

`layout.yaml` also sets user environment variables (`environment`): `TEMP` and `TMP` point at `E:\Temp`,
and `DO_NOT_TRACK=1`.
New processes pick them up; Windows' own temp folder stays in `C:\Windows\Temp`.

Scoop's persist stays on E: next to the apps: it hardlinks files, and hardlinks can't cross drives.

## Setting up a machine

The same steps work for a brand-new machine and after a Windows reset.

1. **Before Windows** (new machine only): BIOS → Settings → Peripherals → *APP Center Download & Install
   Configuration* → Disabled, otherwise Gigabyte reinstalls its tools through WPBT.
2. **Sign in to Windows** and open Windows PowerShell (no admin needed).
3. **Get chezmoi and apply this repo:**

   ```powershell
   iex "&{$(irm 'https://get.chezmoi.io/ps1')} -b '$env:TEMP'"
   & "$env:TEMP\chezmoi.exe" init --apply --branch next ariesclark/dotfiles
   ```

   chezmoi clones the repo to `~\.local\share\chezmoi` (it has git built in) and applies it.
4. **Answer the two questions.** They are asked once and kept in `~\.config\chezmoi\chezmoi.yaml`:
   - *Groups for this machine*, comma-separated, e.g. `personal,tools,security,hardware,vrchat-dev`.
   - *Let apply partition this machine's disk*: yes on a new machine (D: and E: don't exist yet). After a
     reset the volumes are still there, so the answer doesn't matter.
5. **Approve the admin prompt** if one appears. It only appears when volumes are missing, and it covers just
   the partitioning: shrinking C: and creating D: and E:.
6. **Wait for the rest of the apply:**
   - **labels:** the volumes get their labels. Relabelling C: needs admin; without it the apply only warns.
   - **Scoop:** installed to `E:\Scoop`. After a reset it's already there and only its PATH entry comes back.
   - **apps:** every app of your groups is installed.
   - **registrations:** right-click menus, startup entries and URL handlers for the installed apps.
7. **Do what only you can do:**
   - 1Password: sign in, then Settings → Developer → *Use the SSH agent* (needs Windows Hello).
   - Steam: sign in, then `chezmoi apply` again so it can ask Steam for the games; confirm each dialog.
   - Firefox: in `about:profiles`, make the Scoop profile the default.
   - Sign in to Discord, Riot and the rest as you open them.

After that, `chezmoi apply` is all it takes. On a reset, what lived on D: and E: (your files, Scoop and every
app's settings, games) is still there, so step 6 mostly reconnects things rather than downloading them.

## Not done yet

See [docs/goals.md](docs/goals.md).
