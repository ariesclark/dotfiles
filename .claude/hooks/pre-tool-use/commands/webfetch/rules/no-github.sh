#!/usr/bin/env bash

source "$HOOKS_DIRECTORY/lib.sh"

url=$1
verdict_prefix='Blocked: fetching GitHub pages yields a lossy summary, not the underlying content.'

url_host_is "$url" github.com githubusercontent.com || exit 0

case "$(url_host "$url")" in
  github.com | www.github.com)
    owner=$(url_segment "$url" 1)
    repository=$(url_segment "$url" 2)
    repository=${repository%.git}
    section=$(url_segment "$url" 3)
    case "$section" in
      pull | issues)
        deny "Use gh pr view / gh issue view --repo $owner/$repository, with --comments or gh pr diff, for the complete data including comments, review threads, and diffs."
        ;;
    esac
    [[ -n "$owner" && -n "$repository" ]] || deny 'Clone the repository and read the files directly, or use gh (gh api, gh pr view, gh issue view) for PRs, issues, and metadata.'
    label="$owner/$repository"
    clone_arguments=("$owner/$repository")
    fallback="gh api or gh repo view $owner/$repository"
    ;;
  raw.githubusercontent.com)
    owner=$(url_segment "$url" 1)
    repository=$(url_segment "$url" 2)
    [[ -n "$owner" && -n "$repository" ]] || deny 'Clone the repository and read the files directly, or use gh (gh api, gh pr view, gh issue view) for PRs, issues, and metadata.'
    label="$owner/$repository"
    clone_arguments=("$owner/$repository")
    fallback="gh api or gh repo view $owner/$repository"
    ;;
  gist.github.com)
    gist=$(url_segment "$url" 2)
    [[ -n "$gist" ]] || gist=$(url_segment "$url" 1)
    [[ -n "$gist" ]] || deny 'Clone the gist and read the files directly, or use gh gist list / gh gist view.'
    label="gist $gist"
    clone_arguments=(--gist "$gist")
    fallback="gh gist view $gist"
    ;;
  *)
    deny 'Clone the repository and read the files directly, or use gh (gh api, gh pr view, gh issue view) for PRs, issues, and metadata.'
    ;;
esac

clone=$("$HOOKS_DIRECTORY/scripts/gh-clone-tmp.sh" "${clone_arguments[@]}" 2>/dev/null) ||
  deny "$label could not be cloned (private, nonexistent, or inaccessible). Use $fallback instead."

destination=${clone% *}
sha=${clone##* }

deny "$label was cloned for you at $destination on $sha; read the files there with Read/Grep/Glob. For PRs, issues, and metadata use gh."
