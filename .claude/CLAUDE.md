# Global config and tooling

Global config and tooling come from my dotfiles setup at `~/.config/lnk`: config files plus installed tools like Vite+. Edit config there and commit instead of in place, and route anything new through it too rather than leaving a one-off on one machine. The repo's CLAUDE.md has the mechanics.


# Maintaining these instructions

These are requirements, not suggestions. Ignoring one costs real time: hooks block the tool call, the session gets wiped, and the work is redone from scratch. A promise to do better doesn't survive that, so fix the instruction instead.

- When you break a rule, change the text, not just your intent: rephrase what was easy to miss, add the example you got wrong, or write a new rule so the slip is harder to repeat.
- Put the fix where it belongs. Cross-project rules go here under the section that fits (a commit slip under Git, a shell slip under Bash); a project-only rule goes in that project's own CLAUDE.md; anything that must run automatically goes in settings.json as a hook, since the harness enforces those and prose only nudges.


# Skills

- Load the `humanizer` skill into context at the start of every session and keep it loaded. Don't wait to be asked.
- Apply its patterns to everything you write before sending it: chat replies, docs, code comments, commit messages, READMEs, PR descriptions, any copy at all. Run the text through the rules as you write, not as a cleanup pass afterward.
- Prove the pass on chat replies: end each one with the line "I explicitly went through every humanizer rule" so it's visible, not just claimed. Don't append it to committed text (commit messages, code, READMEs, PR descriptions); there it would just be noise in the history.


# Git

Commit messages follow Conventional Commits. Aim for a subject that describes the change on its own, and add a body only when it says something the diff can't.

**Format.** `<type>: <subject>`, or `<type>(<scope>): <subject>` when a scope clarifies. Allowed types: `feat`, `fix`, `refactor`, `test`, `perf`, `chore`, `docs`, `style`.

**Subject.**
- Imperative mood ("add", not "added"/"adds"), no trailing period, ≤72 characters.
- Self-explanatory: it stands alone and conveys the change without the body.
- Lowercase, except code identifiers (`AbortSignal`, `JSON.parse`) and explicitly-cased terms (proper nouns, product names like `Sentry`, file paths).
- Good: `fix(auth): drop stale session cookie on logout`, `feat: add retry with backoff to webhook delivery`
- Bad: `fix: bug`, `chore: updates`, `fix(auth): cookie`, `feat: changes from review`

**Body.** Default to none. Add one only to carry what the subject and diff cannot: a non-obvious why, or a reference (Sentry trace, doc link, bug report, PR/issue, RFC). Never restate the mechanism the diff already shows.

```
fix(auth): drop stale session cookie on logout

Cookie outlived the session and let revoked tokens pass.
Sentry: https://sentry.io/issues/12345
```


# Naming

- Prefer full words over abbreviations: `command` not `cmd`, `response` not `res`, `directory` not `dir`. Abbreviate only when the long form is the unusual choice (`id`, `url`, established loop indices like `i`).


# Code comments

- Almost never add comments. Write code clear enough to read on its own; if a line needs explaining, rename or restructure it instead of annotating it.
- The only good reason to add one: pointing to an external resource the code can't reference itself, like an issue, a doc or spec, a Stack Overflow answer, or the source of a workaround. Include the link or identifier.
- Never restate the code, narrate the obvious (`// increment i`), or describe a change (`// changed from X`, `// new`). Version control already records that.
- No commented-out code.
- When you edit code that already has a comment, update or remove it so it never contradicts the code.


# Bash tool

**Tool choice.** Reach for the dedicated tools before shelling out: Read instead of `cat`/`head`/`tail`, Edit instead of `sed`. Keep Bash for the things only a shell does.

**Output. These are hard bans, not preferences. Re-read them before every Bash call.**
- Never print a decorative separator or banner: no `echo "---"`, no `echo "--- repo root ---"`, no `echo "=== step 1 ==="`, no divider line of any kind between commands.
- Never narrate status: no `echo "done"`, no `echo "ok"`, no `echo "FULLY IDENTICAL"`, no line announcing what just ran or what comes next. A command that fails says so on its own.
- Never stack unrelated operations into one `;`-joined line to save a round-trip (`ls; echo; readlink; echo; pwd`). Run them as separate steps; join with `&&` only when one genuinely depends on the previous succeeding.
- The one allowed `echo` is a plain short label, and only when a command's output would otherwise be ambiguous (for example, a silent `diff` that exits clean).
- Keep each command simple and legible. The permission evaluator and the user read every one, so a dense one-liner is harder to approve and harder to follow than a couple of plain steps.

**Output volume.** Every line a command prints lands back in the context as tokens, and tokens are slow and costly, so ask for the least output that still answers the question. Prefer quiet flags (`-q`, `--quiet`, `--silent`) and reach for machine-readable output you can narrow rather than dumping the human-readable default: when a tool speaks JSON, request JSON and select only the fields you need (`gh ... --json number,title`, `... --jq '.field'`, `cargo ... --message-format short`). Pipe long output through a filter so only the relevant part comes back, and lean on the flag that already trims noise (`git -q`, `npm --silent`, `pip -q`) before piping.

**Chaining.** Join steps with `&&` so a failure stops the chain instead of running the next command against a broken state; prefix `set -euo pipefail` for anything with a pipe or several steps. Don't `cd` to move around: pass absolute paths, since the working directory already persists between calls and a bare `cd` in a compound command can trip a permission prompt.

**Safety.** Quote expansions (`"$var"`, `"${arr[@]}"`), leaving them bare only when you actually want word-splitting or globbing. Use `"$(...)"` for command substitution, not backticks. Before `rm`, `mv`, or overwriting a file, look at the target first and spell out the path rather than trusting the current directory.


# WebFetch tool

WebFetch does not hand back the page. It fetches the URL, converts HTML to Markdown, runs your prompt against that content through a small fast model, and returns the model's answer. What you get is a summary shaped by your prompt, never the raw page. See the [tool behavior docs](https://code.claude.com/docs/en/tools-reference#webfetch-tool-behavior).

This makes it lossy by design. A result saying the page does not mention something may only mean your prompt did not ask for it, and large pages are truncated to a fixed size before the model ever sees them. Don't try to defeat this by prompting for the whole page ("return the full text verbatim", "dump everything"); the model behind WebFetch will refuse or summarize anyway, so you burn a call and still don't get the raw page. When you need the actual content rather than an answer about it (exact wording, a full code sample, markup you intend to parse, or anything where a missed detail would bite), `curl` the URL through Bash and read it yourself. Use WebFetch when a focused question against a page is enough; use `curl` when you need the page whole.

# SQL

- Always lowercase SQL keywords (`select`, `from`, `where`, `join`, `group by`, `order by`, `insert into`, `count`, `distinct`, `interval`, etc.). Identifiers (table/column names) keep their actual casing.
