# Git

- Always use Conventional Commits style: `<type>: <subject>` or `<type>(<scope>): <subject>` if a scope clarifies (e.g. `fix(auth): drop stale session cookie`).
- Allowed types: `feat`, `fix`, `chore`, `docs`, `style`.
- Subject is imperative ("add", not "added"/"adds"), no trailing period, ≤72 characters.
- The subject must always be self-explanatory — it should stand on its own and convey the change without relying on the body.
  - Good: `fix(auth): drop stale session cookie on logout`, `feat: add retry with backoff to webhook delivery`, `docs: document JSON.parse fallback in config loader`.
  - Bad: `fix: bug`, `chore: updates`, `fix(auth): cookie`, `feat: changes from review`.
- Always lowercase the subject, **except** for code identifiers / snippets (`AbortSignal`, `useEffect`, `JSON.parse`) and other explicitly-cased terms (proper nouns, product names like `Sentry`, file paths). Don't auto-lowercase those.
- Bodies are okay but must be short and concise — prefer pointing at references over re-stating what the diff already shows: Sentry traces, documentation links, bug reports, related PRs/issues, RFCs. Skip the body entirely when the subject is self-explanatory.

## Full examples

```
feat: add retry with backoff to webhook delivery
```

```
fix(auth): drop stale session cookie on logout

Cookie outlived the session and let revoked tokens pass.
Sentry: https://sentry.io/issues/12345
```

```
fix(api): clamp page size to 100 to bound query cost

Unbounded `limit` let a single request scan the whole table.
Closes #482
```


# SQL

- Always lowercase SQL keywords (`select`, `from`, `where`, `join`, `group by`, `order by`, `insert into`, `count`, `distinct`, `interval`, etc.). Identifiers (table/column names) keep their actual casing.
