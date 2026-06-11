#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' | tr '[:upper:]' '[:lower:]')

directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOOKS_DIRECTORY="${directory%/*}"

resolve="$directory/commands/$tool/resolve.sh"
[[ -x "$resolve" ]] || exit 0

subject=$(printf '%s' "$input" | "$resolve")

for rule in "$directory/commands/$tool/rules"/*.sh; do
	[[ -x "$rule" ]] || continue
	result=$("$rule" "$subject")
	[[ -n "$result" ]] || continue
	decision=${result%%$'\n'*}
	message=${result#*$'\n'}
	if [[ "$decision" == deny ]]; then
		jq -n --arg r "$message" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
	elif [[ "$decision" == warn ]]; then
		jq -n --arg c "$message" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
	fi
	exit 0
done
