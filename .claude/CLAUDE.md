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

**Signing.** A commit failing with `error: 1Password: agent returned an error` (or another signing-agent error) usually means I denied the approval prompt, not that the setup is broken. Say the commit needs my approval and wait for me to retry it. Never disable signing, never pass `--no-gpg-sign`, and never diagnose it as a configuration problem.

**Pull requests.** Never open a PR: no `gh pr create`, no API call that creates one. I submit every PR myself. Do the prep: branch, commits, push to the fork or origin. Then hand me a plain link to open the PR, `https://github.com/<base-owner>/<repo>/compare/<base>...<head-owner>:<branch>?expand=1`, and write the title and body you recommend as readable text in the chat, so I can read them before I paste. Never URL-encode them into the link: a prefilled `&title=&body=` blob is unreadable, and I can't review what I can't see.

# Naming

- Write full words, not abbreviations: `command` not `cmd`, `response` not `res`, `directory` not `dir`. Abbreviate only where nobody writes the long form (`id`, `url`, loop indices like `i`).

# Tests

Write the test first, always — for a new feature, a bug fix, or a change to existing behaviour.

1. Write a test asserting the behaviour you want after the change.
2. Run it and watch it fail against the current code. A test that passes before the change tests nothing; work out why and fix the test rather than moving on.
3. Only then write the implementation, and run the test again to watch it pass.

Report both runs. If you skipped the failing run, say so — never present an untested change as verified.

- Never weaken a test to make it pass. When it fails after the implementation, the code is wrong until proven otherwise.
- Assert the specific value, not that something is truthy or merely defined.
- Cover the negative too: the input that must be rejected, the branch that must not be taken, the error that must be raised.
- For a mutation, read the state back and assert it changed, rather than trusting the call's own success.

# Package managers

- For JavaScript/Node work, use `pnpm` for every package operation: `add`, `remove`, `install`, `run`, `exec`, `dlx`, and global installs (`pnpm add -g`).
- The project's own choice overrides that default. Check before running anything: a `packageManager` field in `package.json`, or which lockfile is present (`pnpm-lock.yaml` → pnpm, `package-lock.json` → npm, `yarn.lock` → yarn, `bun.lockb` → bun).
- Docs usually show `npm install ...`. Never paste that verbatim; translate it to the project's manager first.

# Parsing structured input

Never parse a structured format with a regex. HTML, JSON, JS/TS, CSS, YAML, SQL, URLs, dates, CSV, and semver all have parsers; use one. A regex over any of them encodes the sample in front of you, not the grammar, so it passes on that sample and breaks on the next.

- Reach for the real tool: a language's AST (`@babel/parser`, `swc`, `tree-sitter`), an HTML parser (`HTMLRewriter`, `cheerio`, `DOMParser`), `JSON.parse`, the `URL` class, `Intl`/`Temporal`, a CSV reader, `semver`.
- Edit through the tree, not the text: query and rewrite AST nodes, then print. When formatting must survive, splice by node source range rather than regenerating.
- Symptoms that the regex is already wrong: it grows a new branch per input you meet, it needs a comment to explain it, it backtracks superlinearly, or it lookaheads to avoid matching something it shouldn't.
- The same rule holds for detection, not just parsing. Identify a thing by its structure, never by a string that merely appears near it — a mention is not an identity.
- A regex is fine on genuinely flat text: a line prefix, a log level, a known-fixed token. If the input nests or quotes, it is not flat.

Recognising a format has no parser here is a real answer; say so and pick the closest structural approach rather than defaulting to a pattern.

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
