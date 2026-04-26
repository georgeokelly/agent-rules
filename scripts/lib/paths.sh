# lib/paths.sh — Per-project artifact path constants.
# Sourced by agent-sync.sh AND agent-check.sh after $PROJECT_DIR is set.
#
# Centralizing these declarations means that adding a new tool or artifact
# requires touching exactly one file rather than two parallel source-of-
# truth declarations (agent-sync used to define them inline at top, and
# agent-check used to re-declare local aliases like CC_SKILLS_MF). The
# previous arrangement was a known maintenance hazard — see review M3.
#
# Convention: `*_MANIFEST` paths point at the per-tool manifest file; each
# manifest enumerates the artifacts agent-sync owns under that subtree so
# stale-cleanup is precise. `*_STAMP` paths are sentinel touch-files used
# where in-file marker gating is impractical (e.g. .codex/config.toml).
#
# All variables are unconditional: even when a tool's mode is `off`, the
# corresponding manifest path is still defined here so set -u doesn't trip
# defensive sub-blocks that read these names. Whether a manifest *file*
# actually exists at the path is checked by callers via `[ -f ... ]`.

# --- Top-level state -------------------------------------------------------

HASH_FILE="$PROJECT_DIR/.agent-sync-hash"
MANIFEST="$PROJECT_DIR/.agent-sync-manifest"

# --- Cursor manifests ------------------------------------------------------

SKILLS_MANIFEST="$PROJECT_DIR/.cursor/skills/.agent-sync-skills-manifest"
# HIST-006: Cursor subagents live in .cursor/agents/ (Cursor's native
# per-project subagent convention).
CURSOR_SUBAGENTS_MANIFEST="$PROJECT_DIR/.cursor/agents/.agent-sync-subagents-manifest"

# --- Claude Code (CC) manifests --------------------------------------------

CC_RULES_MANIFEST="$PROJECT_DIR/.claude/rules/.agent-sync-rules-manifest"
CC_SKILLS_MANIFEST="$PROJECT_DIR/.claude/skills/.agent-sync-skills-manifest"
# HIST-006: Claude Code's subagent path is .claude/agents/ (one *.md per agent).
CC_SUBAGENTS_MANIFEST="$PROJECT_DIR/.claude/agents/.agent-sync-subagents-manifest"

# --- Codex manifests + stamps ----------------------------------------------

CODEX_SKILLS_MANIFEST="$PROJECT_DIR/.agents/skills/.agent-sync-codex-skills-manifest"
CODEX_CONFIG_STAMP="$PROJECT_DIR/.codex/.config-toml-agent-sync"
# HIST-006: Codex subagents live alongside skills under .agents/; the
# dedicated .agents/agents/ subdir keeps them separate from the skill tree.
CODEX_SUBAGENTS_MANIFEST="$PROJECT_DIR/.agents/agents/.agent-sync-subagents-manifest"

# --- OpenCode manifests + stamps (HIST-006, HIST-009) -----------------------
# HIST-009 moved opencode.json ownership out of the JSON body because OpenCode's
# config schema is strict and rejects unknown top-level keys. The legacy marker
# constant remains for one-time migration/cleanup of pre-HIST-009 files.

OPENCODE_CONFIG_STAMP="$PROJECT_DIR/.opencode/.config-json-agent-sync"
OPENCODE_LEGACY_MARKER='"_generated_by": "agent-sync"'
OPENCODE_SKILLS_MANIFEST="$PROJECT_DIR/.opencode/skills/.agent-sync-skills-manifest"
OPENCODE_SUBAGENTS_MANIFEST="$PROJECT_DIR/.opencode/agent/.agent-sync-subagents-manifest"
