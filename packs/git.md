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

## Co-authorship (MUST evaluate correctly)

- **MUST** add a `Co-authored-by` trailer if the AI agent wrote, modified, or refactored any programming code being committed in the current session — even if the commit also contains non-code files.
- **MUST** use the trailer that matches the actual AI tool that wrote, modified, or refactored the programming code. **MUST NOT** claim a different tool's identity.
- **MUST NOT** add the trailer when AI contributions are limited to commit-message drafting, review comments, planning, or Q&A.
- **MUST NOT** add the trailer when a commit contains only non-programming content (e.g., Markdown, HTML, plain text docs, config files) even if the AI edited them.
- "Programming code" means source code in languages such as Python, TypeScript, C/C++, Rust, CUDA, shell scripts, etc. It excludes markup (Markdown, HTML), data formats (JSON, YAML, TOML), and plain text.

Use the matching trailer:

| AI tool | Trailer |
|---|---|
| Cursor / Cursor Agent | `Co-authored-by: Cursor <cursoragent@cursor.com>` |
| OpenAI Codex / Codex | `Co-authored-by: OpenAI Codex <codex@openai.com>` |
| Claude Code | `Co-authored-by: Claude <noreply@anthropic.com>` |
| OpenCode | `Co-authored-by: opencode <noreply@opencode.ai>` |

```
Co-authored-by: OpenAI Codex <codex@openai.com>
```

## Commit Execution Policy (MUST)

- **MUST NOT** run `git commit` unless the user explicitly instructs to commit (e.g., "commit", "提交", "帮我commit")
- When the user asks for a commit command (e.g., "给我个commit命令"), **MUST** output the command for the user to review and run manually — **MUST NOT** execute it directly
- `git add`, `git status`, `git diff` and other non-committing git commands are fine to run proactively

## What NOT to include (MUST NOT)

- **MUST NOT** include secrets, API keys, or tokens in commit messages
- **MUST NOT** write vague titles like "fix stuff", "update code", "WIP"
- **MUST NOT** use file-centric descriptions as primary structure

## README Sync Check (MUST)

When the user requests a git commit **or** asks to generate a commit command, **MUST** run a README sync check with a blocking confirmation flow.

### Procedure

1. Determine commit scope from staged files only (e.g., `git diff --cached --name-only`), and **MUST NOT** use unstaged/untracked workspace changes. **Exception**: when invoked via `/pre-commit` unstaged fallback (nothing staged), use the files that `/pre-commit` will `git add` as the effective commit scope
2. For each staged file, determine its directory ancestry (leaf → root)
3. Collect candidate READMEs: the root `README.md` plus any `README.md` in directories on the ancestry paths of staged files
4. For each candidate README, check whether it references content affected by the staged changes (e.g., API descriptions, file/module lists, usage examples, architecture diagrams)
5. If any README needs updating, **MUST** list affected READMEs and suggested edits, then pause and ask the user how to proceed:
   - (a) Update and stage READMEs now
   - (b) Skip README updates for this commit
6. **MUST NOT** generate commit commands or execute `git commit` until the user explicitly:
   - Confirms skipping the README updates, **OR**
   - Updates the affected READMEs and stages those changes
7. If the user chooses to skip README updates, **MUST** record an explicit skip confirmation in the chat (e.g., "Confirmed: skip README updates for this commit")
8. If no README needs updating initially, proceed normally

### Scope Rules

- **MUST** check the root `README.md` if it mentions content related to the staged code changes
- **MUST** check `README.md` files in directories where staged files reside (and their parent directories up to root)
- **MUST NOT** check `README.md` files in unrelated sibling directories — staged changes in `src/moduleA/` do not require checking `src/moduleB/README.md`
- A README "needs updating" means it describes functionality, APIs, file structures, or behaviors that the staged code changes have altered

### Example

```
Staged files:
  src/auth/login.py
  src/auth/token.py

Ignored for README check (not staged):
  tmp/debug.log
  .cache/index.json

Check these READMEs:
  ✅ README.md          (root — may describe auth module)
  ✅ src/auth/README.md  (direct parent of staged files)
  ❌ src/api/README.md   (unrelated sibling directory)
  ❌ docs/README.md      (no staged files under docs/)
```
