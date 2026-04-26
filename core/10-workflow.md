# Workflow

## Default: 3-Stage Workflow

For non-trivial tasks, follow this three-stage process.

### Stage 1: Analyze the Problem

**MUST** perform before proposing any solution.

- Deeply understand the core requirement
- Search all related code
- Identify root cause (for bugs) or architectural implications (for features)
- Propose 1–3 solution options with pros/cons
- If a solution contradicts the user's goal, mention it as a note but do not include it as a primary option

**Underlying principles:**

- Systems thinking: consider changes in the context of the entire system
- First-principles: focus on fundamental functionality, not just current implementation
- DRY: point out duplicated code when found
- Long-term: assess technical debt and maintenance cost

**MUST NOT:**

- Make code changes without explanation
- Rush to a solution before understanding the problem
- Skip searching and reading related code
- Ignore information the user provided earlier in the conversation

### Stage 2: Refine the Solution

**Prerequisite**: user has explicitly selected a solution.

- **MUST** list all files to be added, modified, or deleted, with a brief description of changes in each

### Stage 3: Execute the Solution

- **MUST** implement strictly according to the user-chosen solution
- **SHOULD** run type checks / linters after completing modifications

### Stage Transitions

- **MUST** begin with Stage 1 when receiving a new task
- **MAY** prompt the user to advance to the next stage, but **MUST NOT** advance without explicit user confirmation
- **MUST NOT** perform actions from two stages in the same response

---

## Fast Track (exception to 3-stage)

The following situations **MAY** skip Stages 1-2 and proceed directly to execution:

- Single-line modifications (typo, import, formatting)
- User has provided a complete, unambiguous solution
- Pure information queries (no code changes involved)
- Simple rename / find-and-replace tasks
- User explicitly opts in via a trigger token (see below)

When using Fast Track, briefly state what you are doing and why the full workflow is unnecessary.

### Explicit Fast Track triggers

If the user's prompt contains one of these tokens, treat it as a binding override of the 3-stage default regardless of task complexity — the user has signaled the analysis is already done:

- `FT` — uppercase only, standalone token (must NOT be a substring of words like `LIFT` or `DFT`; lowercase `ft` does NOT trigger to avoid false matches like `aircraft` or `lift`)
- `fast track`, `fast-track`, `Fast Track` — case-insensitive

Honor the trigger whether it appears in the initial task prompt or in any follow-up message; act on it immediately, do not re-prompt for confirmation. Still emit the brief "what / why" line above so the override is auditable in transcript.

---

## Tool Adaptation Matrix

Different AI tools have different autonomy levels. The same core rules apply, but execution constraints differ:

### Cursor (GUI, pair-programming model)

- **MUST NOT** commit code changes independently
- **MUST NOT** start development servers
- **SHOULD NOT** use Shell `mkdir` solely to create directories before writing files — the Write tool creates parent directories automatically. Prefer Write over `mkdir` + Shell to avoid unnecessary permission prompts.
- Workflow: strict 3-stage with explicit user confirmation at each transition

### OpenAI Codex (CLI, autonomous agent)

- **MAY** execute code, run tests, and commit changes autonomously
- **MUST** clearly state what actions were taken and their results
- **SHOULD** run tests after making changes to verify correctness
- **SHOULD** respect hierarchical `AGENTS.md` scoping — deeper files override higher-level instructions for their subtree
- **MUST NOT** modify `.codex/config.toml` without explicit user confirmation
- Workflow: goal-oriented — state the acceptance criteria, then execute

### Claude Code (CLI, guided autonomy)

- **MAY** execute code and run tests after confirming intent with the user
- **SHOULD** present a brief plan before executing multi-file changes
- **MUST** ask before destructive operations (deleting files, force-pushing)
- **SHOULD** use `/compact` proactively when conversation approaches context limit
- **SHOULD** leverage hooks for repeatable checks (lint, test, format) instead of relying on manual instruction
- **MUST NOT** modify `.claude/settings.json` without explicit user confirmation
- **SHOULD** use `CLAUDE.local.md` for session-specific overrides rather than modifying shared `CLAUDE.md`
- Workflow: exploratory — confirm at key decision points, execute between them
