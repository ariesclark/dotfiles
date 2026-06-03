#!/usr/bin/env bash
#
# setup.sh — provision a fresh machine from zero to managed dotfiles.
#   curl -fsSL https://raw.githubusercontent.com/ariesclark/dotfiles/main/setup.sh | bash
#
# Single entry point — there is no lnk bootstrap.sh hook; re-run to re-restore host config.
set -euo pipefail

REPO="https://github.com/ariesclark/dotfiles.git"
LNK_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/lnk"

BOLD="$(tput bold 2>/dev/null || printf '')"
GREY="$(tput setaf 8 2>/dev/null || printf '')"
RED="$(tput setaf 1 2>/dev/null || printf '')"
GREEN="$(tput setaf 2 2>/dev/null || printf '')"
DIM="$(tput dim 2>/dev/null || printf '')"
NO_COLOR="$(tput sgr0 2>/dev/null || printf '')"

info()      { printf '%s\n' "${BOLD}${GREY}>${NO_COLOR} $*"; }
error()     { printf '%s\n' "${RED}x $*${NO_COLOR}" >&2; }
completed() { printf '%s\n' "${GREEN}✓${NO_COLOR} $*"; }
fail()      { error "$@"; exit 1; }

has() { command -v "$1" 1>/dev/null 2>&1; }

# Run a command with its output dimmed. Strip the child's own color codes (they would
# cancel the dim) and merge stderr. Resets even on failure, then propagates the code.
run() {
	local rc
	printf '%s' "$DIM"
	set +e
	"$@" 2>&1 | sed $'s/\e\\[[0-9;]*m//g'
	rc=${PIPESTATUS[0]}
	set -e
	printf '%s' "$NO_COLOR"
	return "$rc"
}

SUDO=""
_sudo_ready=""

elevate_priv() {
	if [ "$(id -u)" -eq 0 ]; then SUDO=""; return; fi

	if ! has sudo; then
		error 'Could not find "sudo", needed to install packages.'
		fail "Re-run this script as root, or install sudo."
	fi
	if ! sudo -v; then
		fail "Superuser access not granted, aborting."
	fi

	SUDO="sudo"
}

# Elevate at most once, and only when an apt step actually needs it.
ensure_sudo() { [ -n "$_sudo_ready" ] && return; elevate_priv; _sudo_ready=1; }

install_base_packages() {
	info "Installing base packages: git curl ca-certificates"
	ensure_sudo

	run $SUDO apt-get update
	run $SUDO apt-get install -y git curl ca-certificates
}

install_github_cli() {
	# gh is the GitHub credential helper in the common ~/.gitconfig, but isn't in
	# Ubuntu's default repos — add GitHub's apt source (their documented method).
	info "Installing gh from the GitHub CLI apt repo"
	ensure_sudo

	$SUDO install -m 0755 -d /usr/share/keyrings
	curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
		| $SUDO tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null
	$SUDO chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
	printf 'deb [arch=%s signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
		"$(dpkg --print-architecture)" | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null

	run $SUDO apt-get update
	run $SUDO apt-get install -y gh
}

install_lnk() {
	info "Installing lnk"
	run bash -c 'curl -sSL https://raw.githubusercontent.com/yarlson/lnk/main/install.sh | bash'
	has lnk || fail "lnk installed but is not on PATH — open a new shell and re-run."
}

clone_dotfiles() {
	if [ -d "$LNK_DIR/.git" ]; then
		info "Updating dotfiles"
		run git -C "$LNK_DIR" pull --ff-only || fail "git pull failed in ${LNK_DIR}."
	else
		info "Cloning dotfiles with lnk init"
		run lnk init -r "$REPO" --no-bootstrap --no-emoji || fail "lnk init failed while cloning ${REPO}."
	fi
}

restore_host_config() {
	if ! has wslinfo; then
		info "No host-specific config for this platform — common files only"
		return
	fi

	info "WSL detected — restoring 'wsl' host config"
	run lnk pull --host wsl --no-emoji || fail "host restore failed (lnk pull --host wsl)."

	# Bare names, resolved via the WSL-interop PATH (no hardcoded Windows user). The
	# common gitconfig signs commits through op-ssh-sign, so a missing signer is fatal.
	has ssh.exe || fail "ssh.exe not on PATH — enable WSL interop so Windows System32 is reachable."
	has op-ssh-sign-wsl.exe || fail "1Password SSH signing not set up. Install 1Password for Windows, enable the SSH agent, and turn on SSH commit signing so op-ssh-sign-wsl.exe lands in %LOCALAPPDATA%\\Microsoft\\WindowsApps."
}

has apt-get || fail "this setup targets Debian/Ubuntu, but apt-get was not found."

info "Provisioning dotfiles from ${BOLD}${REPO}${NO_COLOR}"

install_base_packages
install_github_cli
install_lnk
clone_dotfiles
restore_host_config

completed "dotfiles restored and dependencies verified"
