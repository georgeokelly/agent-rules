# Dump Flow (`/agent-memory dump`)

Execute this flow when the user says `/agent-memory dump`, or when auto dump is triggered.

## Prerequisites

Check if `.agent-memory/MEMORY-INDEX.md` exists in the project root.
If not, initialize it by writing the file directly using the agent's file-write capability
(most agent file-write tools create parent directories automatically):

1. Write `.agent-memory/MEMORY-INDEX.md` from [index-template.md](index-template.md)
2. Subdirectories are created automatically when the first file is written to them

## Step 1: Analyze Current Context

Identify and extract from the current conversation:

- **Task goal**: what the user asked to accomplish
- **Findings**: key discoveries, data points, metrics
- **Current state**: what has been done, what remains
- **Decisions**: choices made and their rationale
- **Open questions**: unresolved issues
- **Files touched**: paths the agent read or modified

## Step 2: Generate Session File

1. Read [session-template.md](session-template.md)
2. Generate the filename: `<YYYY-MM-DD>T<HH-MM>Z_<slug>.md`
   - Use **UTC** time, `Z` suffix mandatory
   - slug: lowercase, hyphen-separated, max 50 chars, derived from task
3. Fill each section following template rules
4. **Budget: ≤200 tokens** for the body — be concise, prioritize information density

## Step 3: Security Self-Review

Before writing the file, scan the generated content for:

- API keys, tokens, passwords, credentials → replace with `<REDACTED>`
- Full environment variable values → keep variable name only (e.g. `$DB_HOST` not `192.168.1.100`)
- Internal IPs, hostnames, port numbers that are sensitive
- PII (emails, employee IDs, etc.)

If any found, replace with `<REDACTED>` and add a note in `## open`:
`- <REDACTED> items present — ask user to verify before sharing`

## Step 4: Write Session File

Write to `.agent-memory/sessions/<filename>` (filename already includes `.md`)

## Step 5: Update INDEX

1. Read `.agent-memory/MEMORY-INDEX.md`
2. Add new entry at the **top** of `## sessions` section (reverse chronological)
3. Format: `filename | status | summary (≤20 tokens)`
4. **If this session has a `parent` field**: find the parent entry in INDEX and update its status:
   - If the parent task is fully done → change parent status to `completed`
   - If the parent is being continued (same task, new checkpoint) → change parent status to `superseded`
   - `superseded` means "a newer checkpoint exists for this task chain" — it is excluded from passive discovery
5. Write back the updated INDEX

## Step 6: Update Passive Discovery Hint

Write or update `.cursor/rules/agent-memory-hint.mdc` with:

```yaml
---
description: Agent memory passive discovery hint
globs: "*"
alwaysApply: true
---
```

Body content (replace entirely each time):

```
Active memory sessions in .agent-memory/:
<list each session with status=paused (NOT superseded/completed) as: "- <slug> (<date>): <summary>">

If the user's task relates to a paused session, suggest resuming.
Read .agent-memory/MEMORY-INDEX.md for full index.
```

If no paused sessions remain, **delete** the hint file.

## Output to User

After dump completes, report:

```
✓ Session saved: .agent-memory/sessions/<filename>
✓ INDEX updated
✓ Hint file updated
Status: <paused|completed|failed>
Summary: <one-line summary>
```

---

## Auto Dump

Agent **SHOULD** automatically trigger a dump when it detects that:

1. **Context window approaching limit** — the platform is about to trigger summarization
2. **Long-running task completing** — a multi-step task reaches a natural milestone

### Auto dump behavior

- Execute Steps 1–6 above with `status: paused`
- **MUST NOT** interrupt user flow — perform silently, then report at the end:
  `💾 Auto-saved session: <filename> (context window approaching limit)`
- If a manual dump was already performed in this session, skip auto dump

### When NOT to auto dump

- Simple Q&A with no significant state to preserve
- Session with fewer than ~5 tool calls (not enough context to justify a dump)
- User has explicitly said they don't want auto dump
