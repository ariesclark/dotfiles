#!/usr/bin/env bash
#
# lnk bootstrap — runs automatically after `lnk init -r <repo>` (and manually via
# `lnk bootstrap`). `lnk init` restores only *common* files; host-specific configs
# must be pulled per host. This maps the detected platform to its lnk host and
# restores those symlinks.
#
# Why this matters here: the common ~/.gitconfig sets `commit.gpgsign = true` and
# `[include] path = ~/.wsl.gitconfig`. On WSL that include carries the signer
# (op-ssh-sign-wsl.exe); until the `wsl` host is pulled, the include target is
# missing and git signing fails. Pulling it here closes that gap on first run.
set -euo pipefail

if ! command -v lnk >/dev/null 2>&1; then
  echo "bootstrap: 'lnk' not on PATH — skipping host restore." >&2
  exit 0
fi

# Detect platform → lnk host, then restore that host's symlinks.
if grep -qi microsoft /proc/version 2>/dev/null; then
  echo "bootstrap: WSL detected — restoring 'wsl' host config…"
  lnk pull --host wsl
else
  echo "bootstrap: no host-specific config for this platform — common files only."
fi

echo "bootstrap: done."
