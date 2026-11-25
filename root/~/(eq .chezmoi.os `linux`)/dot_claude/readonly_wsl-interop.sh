# Sourced before each Bash command through CLAUDE_ENV_FILE, as `. wsl-interop.sh /proc "$$"`:
# https://code.claude.com/docs/en/hooks#persist-environment-variables

__wsl_interop_socket_of() {
	local role=$1 command_line=$2 previous="" argument plays_role=""
	local -a arguments
	socket=""
	{ mapfile -d '' arguments <"$command_line"; } 2>/dev/null || return 1
	for argument in "${arguments[@]}"; do
		[[ $argument == "$role" ]] && plays_role=1
		[[ $previous == --socket ]] && socket=$argument
		previous=$argument
	done
	[[ -n $plays_role && -n $socket ]] || socket=""
	[[ -n $socket ]]
}

__wsl_interop_of_bridge() {
	local proc=$1 pid=$2 daemon_socket socket key value
	until __wsl_interop_socket_of --serve "$proc/$pid/cmdline"; do
		value=""
		while IFS=$'\t' read -r key value; do
			[[ $key == PPid: ]] && break
			value=""
		done 2>/dev/null <"$proc/$pid/status"
		[[ $value -gt 1 ]] || return
		pid=$value
	done
	daemon_socket=$socket

	local directory bridge="" newest=-1 stat
	local -a fields
	for directory in "$proc"/[0-9]*; do
		__wsl_interop_socket_of --bridge "$directory/cmdline" && [[ $socket == "$daemon_socket" ]] || continue
		{ read -r stat <"$directory/stat"; } 2>/dev/null || continue
		read -ra fields <<<"${stat##*) }"
		if (( fields[19] > newest )); then
			newest=${fields[19]} bridge=$directory
		fi
	done
	[[ -n $bridge ]] || return

	local -a environment
	local variable interop=""
	{ mapfile -d '' environment <"$bridge/environ"; } 2>/dev/null || return
	for variable in "${environment[@]}"; do
		[[ $variable == WSL_INTEROP=* ]] && interop=${variable#WSL_INTEROP=}
	done
	[[ -S $interop ]] && export WSL_INTEROP=$interop
}

__wsl_interop_of_bridge "$@" || true
unset -f __wsl_interop_of_bridge __wsl_interop_socket_of
