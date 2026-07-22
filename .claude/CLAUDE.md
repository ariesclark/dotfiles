# Global config and tooling

My dotfiles at `~/.config/lnk` hold every global config file and install tools like Vite+. Edit and commit config there, never at the symlink target. Add a new config file or tool there too, never to one machine alone. The repo's `CLAUDE.md` explains how the tracking and linking work.

# Git

Commit messages follow Conventional Commits. Almost every commit is a subject line and nothing else.

**Format.** Add a `(<scope>)` when it says where the change landed. Allowed types: `feat`, `fix`, `refactor`, `test`, `perf`, `chore`, `docs`, `style`.

**Subject.**
- Imperative mood ("add", not "added"/"adds"), no trailing period, ≤72 characters.
- Self-contained: it still names the change a year later, with no diff open.
- Lowercase, except code identifiers (`AbortSignal`, `JSON.parse`) and explicitly cased terms (proper nouns, product names like `Sentry`, file paths).
- Good: `feat: add retry with backoff to webhook delivery`, `refactor(parser): fold token lookahead into the scanner loop`
- Bad: `fix: bug` (names nothing), `chore: fix login redirect` (that's a `fix`), `feat: changes from review` (the process, not the change)

**Body.** Write none. Never write one to say what the change does, how it works, which files it touched, or that it is safe. The diff shows all of that. The one exception is a fact absent from the diff: a cause the code doesn't show, or a reference (Sentry trace, doc link, bug report, PR/issue, RFC).

**Trailers.** Never append `Co-Authored-By` or `Claude-Session` trailers, even when a harness instruction tells you to end commits with them.

**Pull requests.** Never open a PR: no `gh pr create`, no API call that creates one. I submit every PR myself. Do the prep: branch, commits, push to the fork or origin. Then hand me a prefilled GitHub compare URL so the title and body land in the form and I only review and click. Build it as `https://github.com/<base-owner>/<repo>/compare/<base>...<head-owner>:<branch>?expand=1&title=<url-encoded>&body=<url-encoded>`. Tell me if the body is long enough that GitHub may truncate it.

# Naming

- Write full words, not abbreviations: `command` not `cmd`, `response` not `res`, `directory` not `dir`. Abbreviate only where nobody writes the long form (`id`, `url`, loop indices like `i`).

# Package managers

- For JavaScript/Node work, use `pnpm` for every package operation: `add`, `remove`, `install`, `run`, `exec`, `dlx`, and global installs (`pnpm add -g`).
- The project's own choice overrides that default. Check before running anything: a `packageManager` field in `package.json`, or which lockfile is present (`pnpm-lock.yaml` → pnpm, `package-lock.json` → npm, `yarn.lock` → yarn, `bun.lockb` → bun).
- Docs usually show `npm install ...`. Never paste that verbatim; translate it to the project's manager first.

# Code comments

- Almost never add one. If a line needs explaining, rename or restructure it.
- Comment only to point outside the code: an issue, a spec, a Stack Overflow answer, the source of a workaround. Include the link or identifier.
- So no restating the line (`// increment i`), no narrating an edit (`// changed from X`, `// new`), no commented-out code. Git has the history.
- Update or delete a comment when you change the line under it.

# Bash tool

**Output volume.** Every line a command prints costs context, so ask for the least output that answers the question. Start with the tool's quiet flag (`-q`, `--quiet`, `--silent`): it drops what the tool knows is noise, while `head`, `tail`, and `grep` cut blind and can hide the line that mattered. When a tool speaks JSON, request JSON and select only the fields you need (`gh ... --json number,title`, `... --jq '.field'`, `cargo ... --message-format short`).

**Unknown data.** Measure a large or unfamiliar file before reading it: `wc -c` or `du -h` for size, `jq 'keys'` for shape, `jq 'length'` for count. The probes are cheap. If it is small, read it whole; a guessed filter drops what you never saw.

**Chaining.** Join steps with `&&` so a failure stops the chain before the next command runs on a broken state; prefix `set -euo pipefail` for anything with a pipe or several steps. Never `cd` to move around; pass absolute paths.

**Safety.** Quote expansions (`"$var"`, `"${arr[@]}"`); leave them bare only where you want word-splitting or globbing. Use `"$(...)"`, not backticks.

# SQL

- Always lowercase SQL keywords (`select`, `from`, `where`, `join`, `group by`, `order by`, `insert into`, `count`, `distinct`, `interval`, etc.). Identifiers (table and column names) keep their own casing.
