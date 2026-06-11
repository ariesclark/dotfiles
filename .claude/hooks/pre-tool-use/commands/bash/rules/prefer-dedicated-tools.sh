#!/usr/bin/env bash

source "$HOOKS_DIRECTORY/lib.sh"

printf '%s' "$1" | grep -Eq '(^|;|&&|\|\|)[[:space:]]*(grep|sed|find|cat|head|tail)[[:space:]]' || exit 0

warn 'This command shells out where a dedicated tool fits: Grep to search, Glob to find files, Read to view one, Edit to change one. Keep the shell version only when it genuinely needs a shell, like a multi-stage pipeline; in that case, ignore this.'
