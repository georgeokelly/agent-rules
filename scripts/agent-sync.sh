#!/usr/bin/env bash
set -euo pipefail

# agent-sync.sh — Sync rules from central repo to project directory
# Usage: agent-sync.sh [subcommand] [project-dir]
#
# Environment:
#   AGENT_TOOLKIT_HOME  — path to central rules repo (default: ~/.config/agent-toolkit)

show_help() {
    cat <<'EOF'
agent-sync — Sync rules from central repo to project directory

USAGE
    agent-sync [project-dir]              Full sync (default)
    agent-sync codex [project-dir]        Only generate AGENTS.md (legacy)
    agent-sync codex-native [project-dir] Only generate Codex native files (.codex/)
    agent-sync cc [project-dir]           Only generate all CC native files (.claude/)
    agent-sync cc-rules [project-dir]     Only generate .claude/rules/*.md
    agent-sync cc-skills [project-dir]    Only sync skills to .claude/skills/
    agent-sync skills [project-dir]       Only sync skills to .cursor/skills/
    agent-sync clean [project-dir]        Remove all generated files
    agent-sync -h | --help                Show this help message

ARGUMENTS
    project-dir    Target project directory (default: current directory)

ENVIRONMENT
    AGENT_TOOLKIT_HOME   Path to central rules repo (default: ~/.config/agent-toolkit)

SUBCOMMANDS
    (default)   Full sync: generates Cursor .mdc files, .claude/rules/*.md,
                .agent-rules/AGENTS.md (if Codex enabled), .codex/config.toml
                (if Codex native), skills for all tools, deploys
                .cursor/worktrees.json (if template exists), applies project
                overlays, handles sub-repo overlays, and cleans up root-level
                remnants. Skips if already up to date.

    codex       Only generate .agent-rules/AGENTS.md for Codex (legacy).
    codex-native Only generate all Codex native files (.codex/config.toml, skills).
    cc          Only generate all CC native files (.claude/rules/, skills/).
    cc-rules    Only generate .claude/rules/*.md for Claude Code.
    cc-skills   Only sync skills to .claude/skills/.
    skills      Only sync skills to .cursor/skills/.
    clean       Remove all generated files.

NOTE
    The legacy 'claude' subcommand and CC Mode 'dual' were removed in HIST-004
    (CLAUDE.md decommission). Claude Code v2.0.64+ discovers rules natively
    via .claude/rules/*.md, so the monolithic .agent-rules/CLAUDE.md is no
    longer produced. Set '**CC Mode**: native' (default) or 'off' in
    .agent-local.md; 'dual' is accepted as a deprecated alias that falls
    back to 'native' with a warning.

EXAMPLES
    agent-sync                  # Full sync to current directory
    agent-sync ~/my-project     # Full sync to a specific project
    agent-sync codex .          # Regenerate only AGENTS.md
    agent-sync cc .             # Regenerate all CC native files
    agent-sync clean            # Remove all generated files
EOF
    exit 0
}

# --- Parse arguments ---

SUBCOMMAND="sync"
case "${1:-}" in
    -h|--help) show_help ;;
    codex|codex-native|cc|cc-rules|cc-skills|skills|clean)
        SUBCOMMAND="$1"
        shift
        ;;
    claude)
        # HIST-004: explicit error so external scripts relying on this
        # subcommand get a loud signal instead of cd-ing into 'claude'.
        echo "ERROR: 'agent-sync claude' was removed in HIST-004." >&2
        echo "       CLAUDE.md is no longer generated — Claude Code v2.0.64+ reads" >&2
        echo "       .claude/rules/*.md natively. Use 'agent-sync' (full sync) or" >&2
        echo "       'agent-sync cc-rules <dir>' for targeted regeneration." >&2
        exit 2
        ;;
    '')
        ;;
    -*)
        echo "ERROR: Unknown flag '$1'. Run 'agent-sync --help' for usage." >&2
        exit 2
        ;;
    *)
        # Non-subcommand token must be a project-dir argument. Verify it
        # exists before the `cd` below so typos produce a clear error
        # instead of an opaque cd failure.
        if [ ! -e "$1" ]; then
            echo "ERROR: Unknown subcommand or non-existent path: '$1'" >&2
            echo "       Valid subcommands: codex, codex-native, cc, cc-rules," >&2
            echo "                          cc-skills, skills, clean" >&2
            echo "       Run 'agent-sync --help' for details." >&2
            exit 2
        fi
        ;;
esac

# --- Global configuration ---

RULES_HOME="${AGENT_TOOLKIT_HOME:-$HOME/.config/agent-toolkit}"

PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

HASH_FILE="$PROJECT_DIR/.agent-sync-hash"
MANIFEST="$PROJECT_DIR/.agent-sync-manifest"

# Cursor manifest paths
SKILLS_MANIFEST="$PROJECT_DIR/.cursor/skills/.agent-sync-skills-manifest"

# CC (Claude Code) manifest paths
CC_RULES_MANIFEST="$PROJECT_DIR/.claude/rules/.agent-sync-rules-manifest"
CC_SKILLS_MANIFEST="$PROJECT_DIR/.claude/skills/.agent-sync-skills-manifest"

# Codex manifest paths
CODEX_SKILLS_MANIFEST="$PROJECT_DIR/.agents/skills/.agent-sync-codex-skills-manifest"
CODEX_CONFIG_STAMP="$PROJECT_DIR/.codex/.config-toml-agent-sync"

# --- Source library modules ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/resolve.sh"
source "$SCRIPT_DIR/lib/gen-cursor.sh"
source "$SCRIPT_DIR/lib/gen-claude.sh"
source "$SCRIPT_DIR/lib/gen-codex.sh"
source "$SCRIPT_DIR/lib/sync.sh"
source "$SCRIPT_DIR/lib/clean.sh"

# --- Main dispatch ---

case "$SUBCOMMAND" in
    clean)
        do_clean
        ;;
    codex)
        validate_rules_repo
        resolve_packs
        echo "Generating AGENTS.md for Codex (legacy) in $PROJECT_DIR ..."
        generate_codex
        _ok "Done."
        ;;
    codex-native)
        validate_rules_repo
        resolve_packs
        resolve_skill_prefix
        echo "Generating Codex native files in $PROJECT_DIR/.codex/ ..."
        generate_codex
        generate_codex_config
        generate_codex_skills
        _ok "Done."
        ;;
    skills)
        validate_rules_repo
        resolve_skill_prefix
        echo "Syncing skills to $PROJECT_DIR/.cursor/skills/ ..."
        generate_skills
        _ok "Done."
        ;;
    cc)
        validate_rules_repo
        resolve_packs
        resolve_cc_mode
        resolve_skill_prefix
        # HIST-003: opportunistically clean stamp-marked legacy .claude/commands/.
        # Decommissioned subsystems never come back, so all cc* subcommands mirror
        # the full-sync behavior (see reconcile_mode_outputs in sync.sh).
        cleanup_legacy_cc_commands
        echo "Generating all CC native files in $PROJECT_DIR/.claude/ ..."
        generate_cc_rules
        generate_cc_skills
        _ok "Done."
        ;;
    cc-rules)
        validate_rules_repo
        resolve_packs
        resolve_cc_mode
        cleanup_legacy_cc_commands
        echo "Generating CC rules in $PROJECT_DIR/.claude/rules/ ..."
        generate_cc_rules
        _ok "Done."
        ;;
    cc-skills)
        validate_rules_repo
        resolve_skill_prefix
        cleanup_legacy_cc_commands
        echo "Syncing skills to $PROJECT_DIR/.claude/skills/ ..."
        generate_cc_skills
        _ok "Done."
        ;;
    sync)
        validate_rules_repo
        resolve_cc_mode
        resolve_codex_mode
        resolve_skill_prefix
        check_staleness
        echo "Syncing rules from $RULES_HOME → $PROJECT_DIR"
        resolve_packs
        reconcile_mode_outputs
        generate_cursor
        generate_skills
        generate_worktrees
        # CC native outputs
        if [ "$CC_MODE" != "off" ]; then
            generate_cc_rules
            generate_cc_skills
        fi
        # AGENTS.md — the only legacy artifact still emitted (HIST-004).
        # CLAUDE.md generation was decommissioned; .claude/rules/ (v2.0.64+)
        # is the Claude Code native path.
        if [ "$CODEX_MODE" != "off" ]; then
            generate_codex
        fi
        # Codex native outputs
        if [ "$CODEX_MODE" = "native" ]; then
            generate_codex_config
            generate_codex_skills
        fi
        cleanup_remnants
        sync_sub_repos
        store_hash
        _ok "Sync complete."
        ;;
esac
