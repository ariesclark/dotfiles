# lnk dotfiles

This repo is my dotfiles, managed with [lnk](https://github.com/yarlson/lnk). It lives at `~/.config/lnk`, and the files it tracks are symlinked from here into their real locations. For example, `~/.claude/CLAUDE.md` is a symlink back to `.claude/CLAUDE.md` here, and the same holds for `~/.claude/settings.json`, `~/.gitconfig`, and the rest.

To change any tracked config, edit it here in the repo and commit, not at the symlink target. The edit is live on this machine immediately through the symlink, but it reaches the others only once committed and pushed, since each one restores by pulling.

`.lnk` lists the files tracked on every host. Host-specific files live under `<host>.lnk/` and are listed in `.lnk.<host>`. For example, `wsl.lnk/.wsl.gitconfig` is listed in `.lnk.wsl` and pulled with `lnk pull --host wsl`. `setup.sh` provisions a fresh machine from zero: install dependencies, `lnk init` to clone and link, then restore the host config.
