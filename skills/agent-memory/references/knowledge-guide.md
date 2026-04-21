# Knowledge Flow (`/agent-memory knowledge`)

Execute this flow when the user says `/agent-memory knowledge`. This flow is **independent**
of dump — it can run at any time without a preceding `/agent-memory dump`.

## Prerequisites

Check if `.agent-memory/MEMORY-INDEX.md` exists in the project root.
If not, initialize it by writing the file directly using the agent's file-write capability
(most agent file-write tools create parent directories automatically):

1. Write `.agent-memory/MEMORY-INDEX.md` from [index-template.md](index-template.md)
2. Subdirectories are created automatically when the first file is written to them

## When to Use

- User wants to persist insights with long-term value beyond the current task
- User says "沉淀一下" / "写个总结" / `/knowledge`
- Agent has accumulated findings that would benefit future sessions across the team

## Step 1: Identify Knowledge to Persist

Determine the source material:

- **From current conversation**: extract findings, patterns, insights discussed so far
- **From a session file**: if user specifies (e.g. `/knowledge from kernel-6-perf`),
  read the referenced session from `.agent-memory/sessions/`
- **From multiple sources**: user may ask to synthesize multiple sessions or conversations

## Step 2: Generate Knowledge Note

1. Read [knowledge-template.md](knowledge-template.md)
2. Generate filename: `<descriptive-slug>.md` (no timestamp — knowledge is timeless)
3. Write a **human-readable** document following the template:
   - Background section with context
   - Key insights with full explanations, code examples, metrics
   - Actionable recommendations
   - References to source sessions or files
4. **No token limit** — write as much detail as needed for human comprehension

## Step 3: Write File

Write to `.agent-memory/knowledge/<filename>` (filename already includes `.md`)

## Step 4: Update INDEX

1. Read `.agent-memory/MEMORY-INDEX.md`
2. Add entry to `## knowledge` section: `filename | one-line description`
3. Write back the updated INDEX

## Step 5: Report

```
✓ Knowledge note saved: .agent-memory/knowledge/<filename>
✓ INDEX updated
```

## Differences from `/dump`

| | `/dump` | `/knowledge` |
|---|---------|-------------|
| **Consumer** | LLM agent | Human |
| **Format** | LLM-compact, ≤200 tokens | Full markdown, no token limit |
| **Content** | Task state snapshot (progress, next steps) | Refined insights and recommendations |
| **Lifecycle** | Ephemeral (may expire) | Long-term (timeless) |
| **Git** | .gitignore | tracked |
| **Trigger** | Manual `/dump` or auto | Manual `/knowledge` only |
