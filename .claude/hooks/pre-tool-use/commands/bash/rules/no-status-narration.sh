#!/usr/bin/env bash

source "$HOOKS_DIRECTORY/lib.sh"

printf '%s' "$1" | grep -Eiq 'echo[[:space:]]+["'\'']?(done|ok|okay|success|succeeded|completed?|finished|all good|fully identical)["'\'' .!]*$' || exit 0

warn 'This command echoes a status word like done or ok. Success is implied by a clean exit and failure prints its own error, so drop it. Echo only a short label when output would otherwise be ambiguous, like a silent diff that exits clean.'
