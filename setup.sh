#!/usr/bin/env bash
#
# setup.sh: provision a fresh machine from zero to managed dotfiles.
#   curl -fsSL https://raw.githubusercontent.com/ariesclark/dotfiles/main/setup.sh | bash
#
# Single entry point: there is no lnk bootstrap.sh hook; re-run to re-restore host config.
set -euo pipefail

REPO="https://github.com/ariesclark/dotfiles.git"
LNK_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/lnk"

BOLD="$(tput bold 2> /dev/null || printf '')"
GREY="$(tput setaf 8 2> /dev/null || printf '')"
RED="$(tput setaf 1 2> /dev/null || printf '')"
GREEN="$(tput setaf 2 2> /dev/null || printf '')"
DIM="$(tput dim 2> /dev/null || printf '')"
CLEAR_LINE="$(tput el 2> /dev/null || printf '')"
NO_COLOR="$(tput sgr0 2> /dev/null || printf '')"

# A step holds its line (on a TTY) so completed() or error() can overwrite it in place, giving
# one self-resolving line per action. Off a TTY the result just lands on the next line.
_step_active=""

step() {
	if [ -t 1 ]; then
		printf '%s %s' "${BOLD}${GREY}>${NO_COLOR}" "$*"
		_step_active=1
	else
		printf '%s %s\n' "${BOLD}${GREY}>${NO_COLOR}" "$*"
	fi
}

# A standalone note that always keeps its own line (headers, skipped steps).
info() { printf '%s %s\n' "${BOLD}${GREY}>${NO_COLOR}" "$*"; }

end_step() {
	if [ -n "$_step_active" ]; then
		printf '\r%s' "$CLEAR_LINE"
		_step_active=""
	fi
}

completed() {
	end_step
	printf '%s %s\n' "${GREEN}✓${NO_COLOR}" "$*"
}

error() {
	if [ -n "$_step_active" ]; then
		printf '\n'
		_step_active=""
	fi
	printf '%s\n' "${RED}x $*${NO_COLOR}" >&2
}

fail() {
	error "$@"
	exit 1
}

has() { command -v "$1" 1> /dev/null 2>&1; }

# First MAJOR.MINOR.PATCH token from a tool's --version, which each one formats differently.
version() { "$1" --version 2> /dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true; }

# dpkg check, not `has`: packages like ca-certificates are installed but not on PATH.
pkg_present() { dpkg-query -W -f='${Status}' "$1" 2> /dev/null | grep -q "install ok installed"; }

# Run a command quietly, buffering its merged output. Show that output only if the command
# fails, dimmed and with the child's own color codes stripped (they would cancel the dim),
# then propagate the exit code.
run() {
	local output rc
	set +e
	output="$("$@" 2>&1)"
	rc=$?
	set -e
	if [ "$rc" -ne 0 ]; then
		if [ -n "$_step_active" ]; then
			printf '\n'
			_step_active=""
		fi
		printf '%s' "$DIM" >&2
		printf '%s\n' "$output" | sed $'s/\e\\[[0-9;]*m//g' >&2
		printf '%s' "$NO_COLOR" >&2
	fi
	return "$rc"
}

# Pipe a remote installer into a shell under pipefail, so a broken download fails instead of
# feeding a truncated script to the interpreter. Args: URL, then the interpreter to pipe into
# (default bash), e.g. "sh" or "VP_NODE_MANAGER=yes bash". The URL is passed as a positional
# so it is never reparsed by the inner shell.
run_remote() {
	local url=$1 interpreter=${2:-bash}
	run bash -c "set -o pipefail; curl -fsSL \"\$1\" | $interpreter" _ "$url"
}

# Run a tool's installer as a step, reporting the version delta around it: "installed: <name>
# <version>" on first install, "updated: <name> <old> → <new>" when it changed, else
# "up to date". Args: display name, the binary/path to probe for --version, then the install
# command and its arguments.
install_step() {
	local name=$1 probe=$2
	shift 2

	local before after
	before="$(version "$probe")"
	step "installing: $name${before:+ $before}"
	"$@"
	after="$(version "$probe")"

	if [ -z "$before" ]; then
		completed "installed: $name $after"
	elif [ "$before" != "$after" ]; then
		completed "updated: $name $before → $after"
	else
		completed "up to date: $name $after"
	fi
}

SUDO=""
_sudo_ready=""

elevate_priv() {
	if [ "$(id -u)" -eq 0 ]; then
		SUDO=""
		return
	fi

	has sudo || fail "sudo not found, needed to install packages. run as root or install sudo"
	sudo -v || fail "sudo access denied, stopping"
	SUDO="sudo"
}

# Elevate at most once, and only when an apt step actually needs it.
ensure_sudo() {
	[ -n "$_sudo_ready" ] && return
	elevate_priv
	_sudo_ready=1
}

install_base_packages() {
	local missing=() pkg
	for pkg in git curl ca-certificates; do pkg_present "$pkg" || missing+=("$pkg"); done
	[ "${#missing[@]}" -eq 0 ] && return

	ensure_sudo
	step "installing: base packages (${missing[*]})"
	run $SUDO apt-get update
	run $SUDO apt-get install -y "${missing[@]}"
	completed "installed: base packages (${missing[*]})"
}

install_github_cli() {
	if has gh; then
		completed "up to date: gh $(version gh)"
		return
	fi

	ensure_sudo
	step "installing: gh"

	# gh is the GitHub credential helper in the common ~/.gitconfig, but isn't in
	# Ubuntu's default repos, so add GitHub's apt source (their documented method).
	$SUDO install -m 0755 -d /usr/share/keyrings
	curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
		| $SUDO tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null
	$SUDO chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
	printf 'deb [arch=%s signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
		"$(dpkg --print-architecture)" | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null

	run $SUDO apt-get update
	run $SUDO apt-get install -y gh
	completed "installed: gh $(version gh)"
}

install_lnk() {
	install_step lnk lnk \
		run_remote https://raw.githubusercontent.com/yarlson/lnk/main/install.sh
}

# Vite+ is the unified web toolchain (node + version management + package manager).
# VP_NODE_MANAGER=yes skips its interactive prompt and lets it manage node, as on this host.
install_vite_plus() {
	install_step vite+ "$HOME/.vite-plus/bin/vp" \
		run_remote https://vite.plus "VP_NODE_MANAGER=yes bash"
}

clone_dotfiles() {
	if [ -d "$LNK_DIR/.git" ]; then
		step "updating dotfiles"
		run git -C "$LNK_DIR" pull --ff-only
		completed "dotfiles updated"
	else
		step "cloning dotfiles"
		run lnk init -r "$REPO" --no-bootstrap --no-emoji
		completed "dotfiles cloned"
	fi
}

restore_host_config() {
	if ! has wslinfo; then
		info "no host config for this platform, common files only"
		return
	fi

	step "restoring 'wsl' host config"
	run lnk pull --host wsl --no-emoji

	# Bare names, resolved via the WSL-interop PATH (no hardcoded Windows user). The
	# common gitconfig signs commits through op-ssh-sign, so a missing signer is fatal.
	has ssh.exe || fail "ssh.exe not on PATH. enable wsl interop so windows System32 is reachable"
	has op-ssh-sign-wsl.exe || fail "op-ssh-sign-wsl.exe not on PATH. install 1Password for windows, enable the ssh agent, and turn on commit signing"
	completed "wsl host config restored"
}

# In WSL, run the Windows-side setup.ps1 (1Password CLI) through interop.
provision_windows() {
	has wslinfo || return 0

	if ! has powershell.exe; then
		info "wsl interop off, skipping windows tooling"
		return
	fi

	step "provisioning windows tooling"
	run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$LNK_DIR/setup.ps1")"
	completed "windows tooling ready"
}

source_dropin_directory() {
	local owner=$1 name=$2

	grep -qF "$name/*.sh" "$owner" 2> /dev/null && return

	info "sourcing ~/$name from ~/${owner##*/}"
	cat >> "$owner" << EOF

for file in "\$HOME"/$name/*.sh; do
	[ -f "\$file" ] && . "\$file"
done
unset file
EOF
}

has apt-get || fail "apt-get not found. this setup targets Debian/Ubuntu"

info "provisioning dotfiles from ${BOLD}${REPO}${NO_COLOR}"

install_base_packages
install_github_cli
install_lnk
install_vite_plus
clone_dotfiles
source_dropin_directory "$HOME/.profile" .profile.d
source_dropin_directory "$HOME/.bashrc" .bashrc.d
provision_windows
restore_host_config

completed "all done, dotfiles restored ♡"
