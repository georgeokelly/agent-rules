# Session Dump Template (LLM-Compact)

Agent **MUST** follow this template exactly when generating session dump files.
Target: **≤200 tokens** for the body (excluding frontmatter).

## Format

```markdown
---
task: <one-line task description>
status: paused | completed | failed
agent: <model-tag>
tags: [<tag1>, <tag2>]
files: [<path1>, <path2>]
parent: <optional, filename of predecessor session>
---
## summary
<2-3 sentences: what was the goal, what was accomplished, what remains>

## findings
- <finding 1: concise, include key data points>
- <finding 2>

## next
<1-2 sentences: immediate next action if status=paused>

## decisions
- <decision>: <rationale> (vs. <rejected alternatives>)

## open
- <unresolved question 1>
```

## Rules

- **No tables** — use `- key: value` bullets for everything
- **No UUIDs** — the filename is the unique identifier
- **No redundant dates** — the filename contains the timestamp
- **Inline data** — numbers, percentages, metric names go directly in findings, not separate sections
- **English for technical terms** — keep domain terms (e.g. kernel, occupancy, bank conflict) in English even if conversation is in Chinese
- Section `## next` is omitted when `status: completed`
- Section `## open` is omitted when no open questions remain
- Each `## findings` bullet ≤ 30 tokens
- Each `## decisions` bullet ≤ 40 tokens
