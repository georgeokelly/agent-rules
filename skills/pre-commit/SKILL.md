---
# Frontmatter fields follow the agentskills.io specification.
# Cross-tool: Cursor, Claude Code, and Codex all parse `name` + `description`.
name: pre-commit
description: >-
  Draft a copy-pasteable `git commit` command from staged (or unstaged)
  changes. Use when the user asks to create a commit, write a commit message,
  `/pre-commit`, 提交, 起草 commit. Does NOT execute git commit — only drafts
  it for user review.
when_to_use: >-
  Use ONLY when the user explicitly asks to draft a git commit message or
  run a pre-commit flow. Do NOT auto-use for unrelated git operations
  (status, push, branch, log, etc.).
compatibility: Cross-tool (Cursor, Claude Code, Codex). Requires git repo. Readonly semantics — drafts the command only, never executes `git commit`.
metadata:
  author: georgel
  version: "0.1"
---

# Pre-Commit

Analyze staged changes and produce a copy-pasteable `git commit` command.
**Do NOT execute `git commit` directly.**

## Workflow

### Step 1 — Gather changes

Run `git diff --cached --stat` and `git diff --cached`.

- **If changes are staged**: use the staged diff as the basis for Steps 2-4.
- **If nothing is staged**: fall back to `git diff` and `git status` to find
  unstaged/untracked changes.
  - If there are no changes at all, inform the user and **stop here**.
  - Otherwise, use the unstaged diff as the basis for Steps 2-4. In Step 4,
    prepend a `git add` command before the `git commit` command so the user
    can copy and run both in sequence.

### Step 2 — README Sync Check

Follow the README Sync Check procedure defined in the project's git commit
rules (git.mdc / CLAUDE.md / AGENTS.md). This is a **blocking** check — do
not proceed to Step 3 until the user either confirms README updates or
explicitly skips them.

### Step 3 — Draft commit message

Read the project's git commit message conventions (git.mdc / CLAUDE.md /
AGENTS.md), then:

1. Analyze the diff to understand the logical changes (not file-by-file).
2. Draft a commit message following the documented format (imperative title
   + grouped body).
3. Evaluate Co-authorship: add the `Co-authored-by` trailer only when
   warranted per the rules.

### Step 4 — Output the command

Present copy-pasteable commands using HEREDOC format.

**When changes were already staged:**

```bash
git commit -m "$(cat <<'EOF'
<title>

<body>

[Co-authored-by: ...]
EOF
)"
```

**When nothing was staged (fallback to unstaged changes):**

```bash
git add <files> && git commit -m "$(cat <<'EOF'
<title>

<body>

[Co-authored-by: ...]
EOF
)"
```

The `git add` portion should list the specific files from the unstaged diff,
or use `git add -A` if all changes should be included.

Do NOT run these commands. The user will review and execute them.
