---
# Spec (required)
name: agent-memory
description: >-
  Dump and resume agent working context across sessions via structured files.
  Use when the user asks to save context, dump memory, resume a previous session,
  continue a prior task, or when a paused session is detected that matches the
  current task. Commands: /agent-memory dump, /agent-memory resume,
  /agent-memory knowledge.

# Spec (optional)
license: MIT
compatibility: Cross-tool (Cursor, Claude Code, Codex). Requires filesystem access.
metadata:
  author: georgel
  version: "1.2"

# Spec (experimental)
# allowed-tools: Bash(git add *) Bash(git commit *) Read  # support claude only
# disable-model-invocation: true                          # support cursor + claude

# Spec (claude-only)
when_to_use: >-
  Use when the user explicitly asks to save / dump / checkpoint the current
  working context, resume a previous session, or distill a knowledge note —
  OR when the context window is approaching its limit and a summarization
  is about to happen (auto-dump). Also use passively when a paused session
  hint in .cursor/rules/agent-memory-hint.mdc is clearly related to the
  user's current task. Do NOT use just to take notes during a live task.
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

# Agent Memory

Persist agent working context so work can resume across sessions and agents.

## Two-Track Design

| Type | Directory | Consumer | Format | Git |
|------|------|--------|------|-----|
| **Session dump** | `.agent-memory/sessions/` | LLM agent | LLM-compact (≤200 tokens) | ignored |
| **Memory index** | `.agent-memory/MEMORY-INDEX.md` | LLM agent | LLM-compact (one-line/entry) | ignored |
| **Knowledge note** | `.agent-memory/knowledge/` | Humans | Human-readable markdown | tracked |

## Command Routing

In Cursor, invoke the skill with `/agent-memory <subcommand>`. Natural-language
requests are also supported:

| Subcommand | Natural-language triggers | Flow |
|--------|------------|------|
| `dump` | "dump memory" / "save context" / "checkpoint this" | Dump Flow |
| `resume [keyword]` | "resume" / "continue the previous session" / "pick up from where we left off" | Resume Flow |
| `knowledge` | "distill this" / "write a summary" | Knowledge Flow |

### Dump Flow

1. Read [dump-guide.md](references/dump-guide.md)
2. Read [session-template.md](references/session-template.md)
3. Follow the seven-step procedure in dump-guide: context analysis -> session
   generation -> safety review -> file write -> INDEX update -> hint update

**Auto trigger**: When the context window is near its limit and summarization is
about to happen, the agent **SHOULD** run Dump Flow first to preserve the current
context, then proceed with summarization. See the "Auto Dump" section in
dump-guide.md.

### Resume Flow

1. Read [resume-guide.md](references/resume-guide.md)
2. Follow resume-guide to scan INDEX -> load the session -> continue work

### Knowledge Flow

1. Read [knowledge-guide.md](references/knowledge-guide.md)
2. Read [knowledge-template.md](references/knowledge-template.md)
3. Follow knowledge-guide to generate a human-readable knowledge note

Knowledge Flow is independent from Dump Flow. It can run at any time and does
not require a prior dump. Use it when the current conversation contains findings
with long-term value, or when the user wants to organize knowledge about a topic.

## Passive Discovery

If `.cursor/rules/agent-memory-hint.mdc` exists, it is maintained automatically
by Dump Flow, and the agent will see a paused-session summary in the system
prompt.

When the user's current task is clearly related to a paused session, proactively
suggest:

> I found a related previous session: <slug> (<date>). Should I resume from that progress?

**MUST NOT** mention paused sessions when the user's task is unrelated.

## Safety Baseline

During dumps, the agent **MUST NOT** write the following content:

- API keys, tokens, passwords, credentials
- Full environment variable values; variable names such as `$VAR` may be recorded,
  but values must not be recorded
- PII, including email addresses and employee IDs
- Sensitive internal IP addresses or hostnames

Replace violations with `<REDACTED>`. See Step 3 in dump-guide.md.

## Key Files

| File | Purpose |
|------|------|
| [dump-guide.md](references/dump-guide.md) | `/dump` workflow |
| [resume-guide.md](references/resume-guide.md) | `/resume` workflow |
| [knowledge-guide.md](references/knowledge-guide.md) | `/knowledge` workflow |
| [session-template.md](references/session-template.md) | LLM-compact session template |
| [index-template.md](references/index-template.md) | LLM-compact INDEX template |
| [knowledge-template.md](references/knowledge-template.md) | Human-readable knowledge-note template |

## Language Constraints

- **Conversation language**: Follow the user.
- **Session / INDEX output**: Keep technical terms in English; descriptive text
  may use the user's language.
- **Knowledge note output**: Follow the project's primary language or the user's
  preference.
