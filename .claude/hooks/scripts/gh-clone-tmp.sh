#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == --gist ]]; then
  gist=$2
  destination="${TMPDIR:-/tmp}/github/gist/$gist"
  command=(gh gist clone "$gist" "$destination")
else
  repository=$1
  destination="${TMPDIR:-/tmp}/github/$repository"
  command=(gh repo clone "$repository" "$destination")
fi

if [[ ! -d "$destination/.git" ]]; then
  "${command[@]}" -- --depth 1 -q
fi

git -C "$destination" reset --hard -q
sha=$(git -C "$destination" rev-parse --short HEAD)

printf '%s %s\n' "$destination" "$sha"
