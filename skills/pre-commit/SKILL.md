---
# Spec (required)
name: pre-commit
description: >-
  Draft a copy-pasteable `git commit` command from staged (or unstaged)
  changes. Use when the user asks to create a commit, write a commit message,
  `/pre-commit`, commit preparation, or commit-message drafting. Does NOT
  execute git commit — only drafts it for user review.

# Spec (optional)
license: MIT
compatibility: Cross-tool (Cursor, Claude Code, Codex). Requires git repo. Readonly semantics — drafts the command only, never executes `git commit`.
metadata:
  author: georgel
  version: "0.1"

# Spec (experimental)
# allowed-tools: Bash(git add *) Bash(git commit *) Read  # support claude only
# disable-model-invocation: true                          # support cursor + claude

# Spec (claude-only)
when_to_use: >-
  Use ONLY when the user explicitly asks to draft a git commit message or
  run a pre-commit flow. Do NOT auto-use for unrelated git operations
  (status, push, branch, log, etc.).
# argument-hint: "[issue-number] [branch]"
# arguments: [issue, branch]
# user-invocable: true
# model: sonnet        # sonnet / opus / haiku / id / inherit
# effort: medium       # low / medium / high / xhigh / max
# context: fork        # When forking, run the body in an independent subagent context
# agent: general-purpose
# hooks:
#   PreToolUse: ./hooks/<pre.sh>
#   PostToolUse: ./hooks/<post.sh>
#   Stop: ./hooks/<stop.sh>
# paths:
#   - "src/**/*.ts"
# shell: bash          # bash / powershell
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

Write the commit message to a file under `/tmp/`, then `pushd` into
the target repo, run `git commit -F`, and `popd` back. Two
hard-and-fast rules apply to the form of the output:

1. Do **NOT** use the `git commit -m "$(cat <<'EOF' ... EOF)"`
   nested-heredoc form. Terminals frequently mis-parse nested command
   substitution, multi-line heredocs, and special characters (arrows,
   em-dashes, backticks, angle-bracket placeholders). Writing the
   message to a file first sidesteps the entire quoting problem and
   makes the message inspectable / retry-able after a failed commit.

2. Do **NOT** use `git -C <repo> commit ...` to operate on a repo
   from outside its worktree. Always `pushd <repo>` first so the
   operating directory is explicit in the command stream — easier to
   audit, more predictable under hooks that read `$PWD` or
   `core.worktree`, and on failure leaves the shell inside the repo
   so the user can fix-and-retry without another `pushd`.

Output the message-write, commit, and cleanup steps as separate
fenced blocks so the user runs them one by one and can inspect the
message between steps:

**1. Write message file** (single heredoc that only feeds `cat`, not
nested inside another command substitution):

```bash
cat > /tmp/commit-msg-<topic>.txt <<'EOF'
<title>

<body>

[Co-authored-by: ...]
EOF
```

**2a. Commit when changes were already staged:**

```bash
pushd <repo> > /dev/null && git commit -F /tmp/commit-msg-<topic>.txt && popd > /dev/null
```

**2b. Commit when nothing was staged (fallback to unstaged changes):**

```bash
pushd <repo> > /dev/null && git add <files> && git commit -F /tmp/commit-msg-<topic>.txt && popd > /dev/null
```

The `git add` portion should list the specific files from the
unstaged diff, or use `git add -A` if all changes should be included.

The `&&` chain is intentional: if `add` or `commit` fails, the user
stays inside `<repo>` (because `popd` never runs) and can fix-and-
retry without re-pushing. The user runs `popd` manually after
resolving the failure. Suppress `pushd` / `popd` chatter with
`> /dev/null` (otherwise zsh / bash echo the directory stack on
every push/pop).

**3. Clean up the temp file** (output as a separate command so the
message survives a failed commit and stays inspectable for retry):

```bash
rm /tmp/commit-msg-<topic>.txt
```

Filename convention: `/tmp/commit-msg-<short-topic>.txt` (e.g.
`commit-msg-install-sh.txt`) so multiple parallel commits don't
collide on the same temp file.

Do NOT run any of these commands. The user will review and execute
them.
