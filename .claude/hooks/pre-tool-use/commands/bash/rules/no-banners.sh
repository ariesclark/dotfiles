#!/usr/bin/env bash

source "$HOOKS_DIRECTORY/lib.sh"

printf '%s' "$1" | grep -Eq 'echo[[:space:]]+["'\'' ]*[-=*#_]{2,}' || exit 0

deny 'This command prints a decorative divider (echo "---", echo "=== step ==="). Dividers add noise without information; re-run the command without it.'
