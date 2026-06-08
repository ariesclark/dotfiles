# Skills

- Load the `humanizer` skill into context at the start of every session and keep it loaded. Don't wait to be asked.
- Apply its patterns to everything you write before sending it: chat replies, docs, code comments, commit messages, READMEs, PR descriptions, any copy at all. Think the text through the humanizer rules first, then write. Never the other way around.
- Don't cite it in the output. Confirm the pass mentally instead: while thinking, before finalizing any copy, explicitly say "I explicitly went through every humanizer rule".


# Git

Commit messages follow Conventional Commits. Aim for a subject that describes the change on its own, and add a body only when it says something the diff can't.

**Format.** `<type>: <subject>`, or `<type>(<scope>): <subject>` when a scope clarifies. Allowed types: `feat`, `fix`, `chore`, `docs`, `style`.

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


# Code comments

- Almost never add comments. Write code clear enough to read on its own; if a line needs explaining, rename or restructure it instead of annotating it.
- The only good reason to add one: pointing to an external resource the code can't reference itself, like an issue, a doc or spec, a Stack Overflow answer, or the source of a workaround. Include the link or identifier.
- Never restate the code, narrate the obvious (`// increment i`), or describe a change (`// changed from X`, `// new`). Version control already records that.
- No commented-out code.
- When you edit code that already has a comment, update or remove it so it never contradicts the code.


# Shell scripts

- Keep one-off scripts and chained commands minimal. Run the commands and let their own output speak.
- Don't print decorative banners or section headers between commands (`echo "----- BUILD -----"`, `echo "=== step 1 ==="`). They add noise and nothing else.
- Skip status narration too: no `echo "done"`, no `echo "ok"`, no "now doing X" lines. A command that fails will say so on its own.
- Add an `echo` only when the output would otherwise be ambiguous, and keep it to a plain short label.


# SQL

- Always lowercase SQL keywords (`select`, `from`, `where`, `join`, `group by`, `order by`, `insert into`, `count`, `distinct`, `interval`, etc.). Identifiers (table/column names) keep their actual casing.
