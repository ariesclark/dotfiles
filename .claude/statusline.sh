#!/usr/bin/env bash
set -uo pipefail

readonly RESET=$'\033[0m'
readonly C_DIRECTORY=$'\033[36m'
readonly C_BRANCH=$'\033[35m'
readonly C_MODEL=$'\033[90m'
readonly C_STAGED=$'\033[32m'
readonly C_MODIFIED=$'\033[33m'
readonly C_NEW=$'\033[34m'
readonly C_DELETED=$'\033[31m'

readonly OSC=$'\033]8;;'
readonly BEL=$'\007'
readonly SEPARATOR="  "
readonly CONTEXT_ICON="●"
readonly PULSE_LEVELS=(100 55)
readonly BLANK_ROW=$'​'
readonly CACHE_MAX_AGE=5
readonly CACHE_SEPARATOR=$'\037'

to_https() {
  local url=${1%.git}
  sed -E 's#^git@([^:]+):#https://\1/#; s#^ssh://git@([^/]+)/#https://\1/#' <<<"$url"
}

home_relative() { printf '%s' "${1/#"$HOME"/'~'}"; }

git_toplevel="" git_remote="" git_status=""

collect_git_state() {
  local directory=$1
  git_toplevel=$(git -C "$directory" rev-parse --show-toplevel 2>/dev/null || true)
  git_remote=""; git_status=""
  [[ -n "$git_toplevel" ]] || return

  git_remote=$(git -C "$directory" remote get-url origin 2>/dev/null || true)
  [[ -n "$git_remote" ]] && git_remote=$(to_https "$git_remote")
  git_status=$(git -C "$directory" -c core.quotePath=false status -b --porcelain 2>/dev/null || true)
}

restore_cache() {
  local directory=$1 cache=$2 cache_mtime now cached_directory
  [[ -f "$cache" ]] || return 1

  printf -v now '%(%s)T' -1
  cache_mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0)
  (( now - cache_mtime <= CACHE_MAX_AGE )) || return 1

  {
    IFS=$CACHE_SEPARATOR read -r cached_directory git_toplevel git_remote || return 1
    IFS= read -r -d '' git_status || true
  } < "$cache"
  [[ "$cached_directory" == "$directory" ]]
}

write_cache() {
  printf '%s%s%s%s%s\n%s' \
    "$1" "$CACHE_SEPARATOR" "$git_toplevel" "$CACHE_SEPARATOR" "$git_remote" "$git_status" > "$2"
}

format_dir() {
  local directory=$1
  if [[ -z "$git_toplevel" ]]; then
    home_relative "$directory"
    return
  fi

  local repo_name=${git_toplevel##*/}
  [[ -n "$git_remote" ]] && repo_name="${OSC}${git_remote}${BEL}${repo_name}${OSC}${BEL}"
  printf '%s%s%s' "$(home_relative "${git_toplevel%/*}")/" "$repo_name" "${directory#"$git_toplevel"}"
}

status_branch() {
  local header=${git_status%%$'\n'*}
  [[ $header == '## '* ]] || return
  header=${header#'## '}
  case $header in
    'HEAD (no branch)'*) ;;
    'No commits yet on '* | 'Initial commit on '*) printf '%s' "${header##* }" ;;
    *) printf '%s' "${header%%...*}" ;;
  esac
}

humanize() {
  local number=$1
  if (( number >= 1000000 )); then
    local millions=$(( number / 1000000 )) fraction=$(( (number % 1000000) / 100000 ))
    (( fraction )) && printf '%d.%dM' "$millions" "$fraction" || printf '%dM' "$millions"
  elif (( number >= 1000 )); then
    printf '%dk' $(( (number + 500) / 1000 ))
  else
    printf '%d' "$number"
  fi
}

percent_rgb() {
  local percent=$1
  if (( percent >= 90 )); then printf '230 70 70'
  elif (( percent >= 70 )); then printf '220 190 60'
  else printf '90 200 120'; fi
}

format_context() {
  local used_tokens=$1 max_tokens=$2

  local percent=0
  (( max_tokens > 0 )) && percent=$(( used_tokens * 100 / max_tokens ))

  local base_r base_g base_b
  read -r base_r base_g base_b <<<"$(percent_rgb "$percent")"

  local now level
  printf -v now '%(%s)T' -1
  level=${PULSE_LEVELS[now % ${#PULSE_LEVELS[@]}]}

  local icon_color=$'\033[38;2;'"$(( base_r * level / 100 ));$(( base_g * level / 100 ));$(( base_b * level / 100 ))m"
  local text_color=$'\033[38;2;'"${base_r};${base_g};${base_b}m"

  if (( max_tokens > 0 )); then
    printf '%s%s%s %s/%s (%d%%)%s' \
      "$icon_color" "$CONTEXT_ICON" "$text_color" \
      "$(humanize "$used_tokens")" "$(humanize "$max_tokens")" "$percent" "$RESET"
  else
    printf '%s%s%s %s%s' "$icon_color" "$CONTEXT_ICON" "$text_color" "$(humanize "$used_tokens")" "$RESET"
  fi
}

format_limit() {
  local label=$1 percent=$2
  (( percent >= 0 )) || return 0

  local base_r base_g base_b
  read -r base_r base_g base_b <<<"$(percent_rgb "$percent")"
  printf '%s%s %s%d%%%s' \
    "$C_MODEL" "$label" $'\033[38;2;'"${base_r};${base_g};${base_b}m" "$percent" "$RESET"
}

format_group() {
  local sigil=$1 color=$2; shift 2
  (( $# )) || return 0

  local columns=${COLUMNS:-80} total=$# shown=0 width=${#sigil} files="" file reserve
  for file in "$@"; do
    reserve=0
    (( shown + 1 < total )) && reserve=10
    (( shown > 0 && width + 1 + ${#file} + reserve > columns )) && break
    files+=" $file"; width=$(( width + 1 + ${#file} )); (( ++shown ))
  done

  local line="${color}${sigil}${RESET}${files}"
  (( total > shown )) && line+=" ${C_MODEL}+$(( total - shown )) more${RESET}"
  printf '%s\n' "$line"
}

render_status() {
  [[ -n "$git_status" ]] || return 0

  local line index_status worktree_status path
  local -a staged=() modified=() new=() deleted=()
  while IFS= read -r line; do
    [[ -z $line || $line == '## '* ]] && continue
    index_status=${line:0:1} worktree_status=${line:1:1} path=${line:3}
    [[ $path == *' -> '* ]] && path=${path#* -> }
    if [[ "$index_status$worktree_status" == '??' ]]; then
      new+=("$path")
    else
      [[ $index_status != ' ' ]] && staged+=("$path")
      [[ $worktree_status == 'M' ]] && modified+=("$path")
      [[ $worktree_status == 'D' ]] && deleted+=("$path")
    fi
  done <<<"$git_status"

  format_group '+' "$C_STAGED" "${staged[@]}"
  format_group '~' "$C_MODIFIED" "${modified[@]}"
  format_group '?' "$C_NEW" "${new[@]}"
  format_group '-' "$C_DELETED" "${deleted[@]}"
}

render() {
  local model=$1 current_directory=$2 used_tokens=$3 max_tokens=$4
  local five_hour_percent=$5 seven_day_percent=$6
  local branch; branch=$(status_branch)
  local summary="" segment
  for segment in \
    "${C_DIRECTORY}$(format_dir "$current_directory")${RESET}" \
    "${branch:+${C_BRANCH}${branch}${RESET}}" \
    "${C_MODEL}${model}${RESET}" \
    "$(format_context "$used_tokens" "$max_tokens")" \
    "$(format_limit '5h' "$five_hour_percent")" \
    "$(format_limit '7d' "$seven_day_percent")"
  do
    [[ -n "$segment" ]] && summary+="${summary:+$SEPARATOR}$segment"
  done
  printf '%s\n' "$summary"

  local status; status=$(render_status)
  [[ -n "$status" ]] && printf '%s\n%s\n%s\n' "$BLANK_ROW" "$status" "$BLANK_ROW"
}

main() {
  local input model current_directory used_tokens max_tokens session
  local five_hour_percent seven_day_percent
  IFS= read -r -d '' input || true
  IFS=$'\t' read -r model current_directory used_tokens max_tokens \
    five_hour_percent seven_day_percent session < <(
    jq -r '[
      .model.display_name // "?",
      (.workspace.current_dir // .cwd),
      (.context_window.total_input_tokens // 0),
      (.context_window.context_window_size // 0),
      (.rate_limits.five_hour.used_percentage // -1 | round),
      (.rate_limits.seven_day.used_percentage // -1 | round),
      (.session_id // "nosession")
    ] | @tsv' <<<"$input"
  ) || true

  local cache="/tmp/claude-statusline-${session}"
  restore_cache "$current_directory" "$cache" || {
    collect_git_state "$current_directory"
    write_cache "$current_directory" "$cache"
  }

  render "$model" "$current_directory" "$used_tokens" "$max_tokens" \
    "$five_hour_percent" "$seven_day_percent"
}

main
