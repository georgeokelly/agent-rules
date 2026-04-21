# Knowledge Note Template (Human-Readable)

Agent generates knowledge notes when the user requests it (e.g. "沉淀一下", "写个总结"),
or when the agent recommends persisting insights that have long-term value beyond the current task.

Knowledge notes are the **only** human-facing output of the memory system.

## Format

```markdown
# <Title>

> Created: <date> | Source: <session filename or "manual">

## Background

<Why this knowledge matters. 1-2 paragraphs providing context.>

## Key Insights

### <Insight 1 Title>

<Detailed explanation with supporting evidence, code snippets, metrics.
Use standard markdown formatting — headers, code blocks, bold, lists.
Optimize for human readability, not token efficiency.>

### <Insight 2 Title>

...

## Recommendations

<Actionable takeaways. What to do, what to avoid, and why.>

## References

- <Related files, docs, links>
```

## Rules

- **Language**: follow the project's primary language (matching `.agent-local.md` or user preference)
- **No token constraints** — write as much detail as needed for human comprehension
- **Code examples welcome** — use fenced code blocks with language tags
- **Link to source session** — include the session filename in the `Source` field for traceability
- Filename convention: `<descriptive-slug>.md` (no timestamp prefix — knowledge is timeless)
- Stored in `.agent-memory/knowledge/` (git tracked by default)
