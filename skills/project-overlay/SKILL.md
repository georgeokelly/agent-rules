---
# Spec (required)
name: project-overlay
description: Create or update project-specific AI configuration (.agent-local.md) through guided conversation. Use when the user wants to create overlay, initialize project rules, set up agent rules, update overlay, refresh project configuration, or when .agent-local.md is missing or outdated.

# Spec (optional)
license: MIT
compatibility: Designed for Cursor (agent mode). Requires access to the project filesystem and $AGENT_TOOLKIT_HOME templates directory.
metadata:
  author: georgel
  version: "1.2"

# Spec (experimental)
# allowed-tools: Bash(git add *) Bash(git commit *) Read  # support claude only
disable-model-invocation: true                          # support cursor + claude

# Spec (claude-only)
when_to_use: >-
  Trigger when (a) the user explicitly asks to create/update/refresh an
  `.agent-local.md` overlay for the current project or a sub-repo, (b) the
  file is missing and the user is asking to "init" / "setup rules" for this
  repo, or (c) passive signals indicate overlay drift — new language/framework
  files that are not reflected in `Packs:`, a structural reorganization that
  contradicts the recorded `Project Structure`, or references to deleted/
  renamed directories. For the passive case, propose the Update Flow rather
  than silently editing the file.
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

# Project Overlay

Create or update a project's `.agent-local.md` configuration file through guided
conversation instead of manually filling each field.

## Flow Routing

Choose the execution path based on current project state:

**Create a new overlay?** (`.agent-local.md` does not exist in the project) -> run Init Flow
**Update an existing overlay?** (`.agent-local.md` already exists) -> run Update Flow

### Init Flow

1. Read [init-guide.md](references/init-guide.md)
2. Read the project `overlay-template.md` at
   `$AGENT_TOOLKIT_HOME/templates/overlay-template.md`; it contains `@schema`
   constraint comments
3. Follow the two-stage guided conversation in init-guide
4. Generate `.agent-local.md` with format-validation gating and atomic write

### Update Flow

1. Read [update-guide.md](references/update-guide.md)
2. Read `overlay-template.md`, including `@schema`, and the current
   `.agent-local.md`
3. Follow update-guide to perform a targeted refresh

## Passive Discovery

During normal task execution, proactively propose Update Flow when any of these
signals appear:

- New language or framework files are present but not recorded in
  `.agent-local.md`, such as `.tsx` files when `Packs:` does not include a
  frontend pack
- The directory structure clearly disagrees with the `Project Structure`
  description
- Build commands no longer match actual usage

The proposal should fit the development intent. Example:
> I noticed that the project now includes React components. Should I update Packs and the project structure?

## Key Files

| File | Location | Purpose |
|------|------|------|
| `overlay-template.md` | `$AGENT_TOOLKIT_HOME/templates/` | Template plus `@schema` constraints; the single source of truth |
| `.agent-local.md` | Project root | Project configuration file committed by the user |
| `init-guide.md` | `references/` | Initialization conversation script |
| `update-guide.md` | `references/` | Update conversation script |

## Language Constraints

- **Conversation language**: Follow the user's language.
- **File output language**: All content in `.agent-local.md` and
  `.agent-local.md.tmp` **MUST** be English, except HTML comments, and must stay
  consistent with `overlay-template.md`.
- **Reason**: `agent-sync` extracts content directly from `.agent-local.md` to
  generate downstream rule files. Non-English content would produce mixed-language
  rules.

## Cross-Tool Consumption

`.agent-local.md` is compiled by `agent-sync` into rules for multiple tools:

- **Cursor**: `.cursor/rules/project-overlay.mdc` (alwaysApply: true)
- **Claude Code**: `.claude/rules/*.md` (native per-file output since HIST-004;
  no monolithic CLAUDE.md is generated)
- **Codex**: root-level `AGENTS.override.md` (Codex-specific entrypoint since
  HIST-007; Cursor does not auto-inject it)
- **OpenCode**: `opencode.json` + `.opencode/skills/` (HIST-006)
