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
    agent-sync claude [project-dir]       Only generate CLAUDE.md
    agent-sync skills [project-dir]       Only sync skills to .cursor/skills/
    agent-sync commands [project-dir]     Only sync commands to .cursor/commands/
    agent-sync agents [project-dir]       Only sync agents to .cursor/agents/
    agent-sync clean [project-dir]        Remove all generated files
    agent-sync -h | --help                Show this help message

ARGUMENTS
    project-dir    Target project directory (default: current directory)

ENVIRONMENT
    AGENT_TOOLKIT_HOME   Path to central rules repo (default: ~/.config/agent-toolkit)

SUBCOMMANDS
    (default)   Full sync: generates Cursor .mdc files, CLAUDE.md, AGENTS.md,
                deploys .cursor/worktrees.json (if template exists),
                applies project overlays, handles sub-repo overlays, and
                cleans up root-level remnants. Skips if already up to date.

    codex       Only generate .agent-rules/AGENTS.md for Codex (legacy).
    codex-native Only generate all Codex native files (.codex/config.toml, skills).
    claude      Only generate .agent-rules/CLAUDE.md for Claude Code (legacy).
    cc          Only generate all CC native files (.claude/rules/, skills/, commands/).
    cc-rules    Only generate .claude/rules/*.md for Claude Code.
    cc-skills   Only sync skills to .claude/skills/.
    skills      Only sync skills to .cursor/skills/.
    commands    Only sync commands to .cursor/commands/.
    agents      Only sync agents to .cursor/agents/.
    clean       Remove all generated files.

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
    codex|codex-native|claude|cc|cc-rules|cc-skills|skills|commands|agents|clean)
        SUBCOMMAND="$1"
        shift
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
COMMANDS_MANIFEST="$PROJECT_DIR/.cursor/commands/.agent-sync-commands-manifest"
CURSOR_AGENTS_MANIFEST="$PROJECT_DIR/.cursor/agents/.agent-sync-agents-manifest"

# CC (Claude Code) manifest paths
CC_RULES_MANIFEST="$PROJECT_DIR/.claude/rules/.agent-sync-rules-manifest"
CC_SKILLS_MANIFEST="$PROJECT_DIR/.claude/skills/.agent-sync-skills-manifest"
CC_COMMANDS_MANIFEST="$PROJECT_DIR/.claude/commands/.agent-sync-commands-manifest"

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
        echo "Generating Codex native files in $PROJECT_DIR/.codex/ ..."
        generate_codex
        generate_codex_config
        generate_codex_skills
        _ok "Done."
        ;;
    claude)
        validate_rules_repo
        resolve_packs
        echo "Generating CLAUDE.md for Claude Code in $PROJECT_DIR ..."
        generate_claude
        _ok "Done."
        ;;
    skills)
        validate_rules_repo
        echo "Syncing skills to $PROJECT_DIR/.cursor/skills/ ..."
        generate_skills
        _ok "Done."
        ;;
    commands)
        validate_rules_repo
        echo "Syncing commands to $PROJECT_DIR/.cursor/commands/ ..."
        generate_commands
        _ok "Done."
        ;;
    agents)
        validate_rules_repo
        echo "Syncing agents to $PROJECT_DIR/.cursor/agents/ ..."
        generate_cursor_agents
        _ok "Done."
        ;;
    cc)
        validate_rules_repo
        resolve_packs
        resolve_cc_mode
        echo "Generating all CC native files in $PROJECT_DIR/.claude/ ..."
        generate_cc_rules
        generate_cc_skills
        generate_cc_commands
        _ok "Done."
        ;;
    cc-rules)
        validate_rules_repo
        resolve_packs
        resolve_cc_mode
        echo "Generating CC rules in $PROJECT_DIR/.claude/rules/ ..."
        generate_cc_rules
        _ok "Done."
        ;;
    cc-skills)
        validate_rules_repo
        echo "Syncing skills to $PROJECT_DIR/.claude/skills/ ..."
        generate_cc_skills
        _ok "Done."
        ;;
    sync)
        validate_rules_repo
        resolve_cc_mode
        resolve_codex_mode
        check_staleness
        echo "Syncing rules from $RULES_HOME → $PROJECT_DIR"
        resolve_packs
        reconcile_mode_outputs
        generate_cursor
        generate_skills
        generate_commands
        generate_cursor_agents
        deploy_reviewer_models_conf
        generate_reviewer_variants
        generate_worktrees
        # CC native outputs
        if [ "$CC_MODE" != "off" ]; then
            generate_cc_rules
            generate_cc_skills
            generate_cc_commands
        fi
        # Legacy CLAUDE.md / AGENTS.md
        if [ "$CC_MODE" != "native" ] || [ "$CODEX_MODE" != "off" ]; then
            if [ "$CODEX_MODE" != "off" ]; then
                generate_codex
            else
                generate_claude
            fi
        else
            echo "  CC Mode: native + Codex Mode: off — skipping legacy generation"
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
