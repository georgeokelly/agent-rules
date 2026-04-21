# MEMORY-INDEX Template (LLM-Compact)

Agent **MUST** follow this template when creating or updating `.agent-memory/MEMORY-INDEX.md`.

## Format

```markdown
# Memory Index

## sessions
<!-- file | status | one-line summary (≤20 tokens) -->
2026-03-17T08-30Z_kernel-6-perf.md | paused | kernel_6 瓶颈分析完成, 待 padding 优化
2026-03-16T06-20Z_rule-refactor.md | completed | agent-rules 模块化重构

## knowledge
<!-- file | one-line description -->
kernel-6-perf-insights.md | kernel_6 性能瓶颈根因与优化策略
project-architecture.md | 项目模块划分与数据流
```

## Rules

- One line per entry, pipe-separated: `filename | status | summary`
- Summary ≤ 20 tokens, no period at end
- Newest entries at top (reverse chronological)
- `## knowledge` entries omit `status` (knowledge is always active)
- When a session transitions to `completed` or `superseded`, update its status in-place (do not create new line)
- `superseded` means a newer checkpoint exists for the same task chain — excluded from passive discovery
- When session count exceeds 30, archive `completed` and `superseded` entries older than 90 days by moving them to a `## archived` section at the bottom
- **MUST NOT** include full paths — filenames only (relative to `sessions/` or `knowledge/`)
