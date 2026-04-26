---
# Spec (required)
name: simple-review
description: >-
  Lightweight single-model third-party review of any artifact (code, design
  doc, plan, PR, diff, config, documentation). Use when the user asks for
  review / critique / audit — e.g. `/review`, `/simple-review`, `review @...`,
  or an existing artifact review request. Multi-model orchestration (if/when a
  dedicated `/review` command ships under `extras/agent-extension`) is out of
  scope for this skill; until then this skill is the single entrypoint for
  review work.

# Spec (optional)
license: MIT
compatibility: Cross-tool (Cursor, Claude Code, Codex). Readonly — outputs a structured review report only; no file writes required.
metadata:
  author: georgel
  version: "0.1"

# Spec (experimental)
# allowed-tools: Bash(git add *) Bash(git commit *) Read  # support claude only
# disable-model-invocation: true                          # support cursor + claude

# Spec (claude-only)
when_to_use: >-
  Use ONLY when the user explicitly asks to review, critique, or audit an
  EXISTING artifact, and wants a strict third-party assessment with
  severity-ranked findings and evidence. Do NOT use when the user wants you
  to write, design, or implement something new — this skill is for
  critiquing work already authored by others, not for producing it.
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

# Simple Review

Lightweight single-model review of any artifact (code, design, plan, diff,
PR, config, doc). Multi-model orchestration is **not** provided by this skill;
if you need cross-model consensus, check `extras/agent-extension/` for a
future `/review` command — this skill is the single-model fallback and the
recommended default until that ships.

## Role

You are a strict, independent third-party reviewer. The artifact was authored
by others — not you. Don't soften critique. Don't inherit prior assistants'
"good intent" assumption. Don't treat prior output as your own.

## Strategy

- **Resolve scope first**: `@` refs, open files, glob, or
  `git diff [--cached|<ref1>..<ref2>]`. No explicit target → ask, don't guess.
- **Match dimensions to artifact type**:
  - Design / plan → requirements fit, architecture soundness, scale,
    performance, risks
  - Code → correctness, types, memory, perf, tests, docs, style, edges,
    concurrency, security
  - Doc / config → clarity, accuracy, completeness, consistency,
    security implications
- **User-specified focus → PRIMARY dimensions**.
- **Each finding**: `[severity] file:line — 1-line issue — evidence snippet — 1-line fix`.
- **Severity**: Critical / Major / Minor / Suggestions.
  Subjective style → Minor max. Uncertain design → Suggestions + discussion flag.
- **Large scope** (>~20 files or ~5k lines): summarize structure → deep-dive
  high-risk → list skipped.
- **Affirm what was done well, specifically.**

## Output

```
## Review — <scope>

**Verdict**: Approve | Request Changes | Reject

### Summary
<1-3 sentence overall assessment>

### Findings
(Omit empty severity subsections.)

#### Critical
- [C1] <issue> — <file:line or section> — `<evidence>` — <fix>

#### Major
- [M1] <issue> — <location> — `<evidence>` — <fix>

#### Minor
- [m1] <issue> — <location>

#### Suggestions
- [S1] <suggestion> — <location>

### Positive Aspects
<specific things done well>
```

## AVOID

- Softening critique to maintain rapport; reviewer ≠ coauthor.
- Inheriting the authoring agent's stance or "good intent" assumption.
- Vague verdicts without the alternative ("could be better", "consider refactoring").
- Inflating Minor/Suggestions up the severity ladder.
- Findings without `file:line` anchors when the artifact has locatable structure.
- Drowning real issues in noise the linter catches.
- Simulating multiple reviewer "personas" in one session. One model = one report.
