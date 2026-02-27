# Git Commit Message Guidelines

## Commit Message Format (MUST)

```
<title line: imperative verb + what changed>

<grouped changes by feature/fix, not by file>
```

- **MUST** use imperative mood in title: "Add", "Fix", "Update", "Remove" (not "Added", "Fixes", "Updated")
- **MUST** keep title line under 72 characters
- **MUST** separate title from body with a blank line
- **MUST** group body by feature/fix/concern, not by file path
- **SHOULD** explain *why* the change was made, not just *what* changed
- **MUST NOT** list individual file paths as top-level items — files are implementation details

## Body Structure (SHOULD)

Organize by logical change, each with a short heading:

```
Add user authentication and session management

Authentication:
- JWT-based token flow with refresh token rotation
- Rate limiting on login endpoint (10 req/min)

Session management:
- Redis-backed session store with 24h TTL
- Auto-cleanup of expired sessions via cron

Migration:
- Add users table with email/password_hash columns
- Add sessions table with token/user_id/expires_at
```

**NOT** like this:

```
- Modified src/auth.py
- Modified src/session.py
- Added migrations/001_users.sql
- Updated README.md
```

## Title Verb Reference (SHOULD)

| Verb | Use when |
|------|----------|
| Add | Wholly new feature or capability |
| Fix | Bug fix or correctness issue |
| Update | Enhancement to existing feature |
| Remove | Deleting code, feature, or dependency |
| Refactor | Restructuring without behavior change |
| Improve | Performance, UX, or readability improvement |
| Support | Adding compatibility for new platform/format |

## Co-authorship (SHOULD when applicable)

When AI tools contributed significantly:

```
Co-authored-by: Cursor <cursoragent@cursor.com>
```

## What NOT to include (MUST NOT)

- **MUST NOT** include secrets, API keys, or tokens in commit messages
- **MUST NOT** write vague titles like "fix stuff", "update code", "WIP"
- **MUST NOT** use file-centric descriptions as primary structure
