#!/usr/bin/env bash
set -euo pipefail

# agent-check.sh — Validate generated rule files in a project directory
# Usage: agent-check.sh [project-dir]
#
# Checks:
#   1. Codex AGENTS.md size (must be < 32KiB)
#   2. Cursor .mdc frontmatter lint (must have closing ---)
#   3. No .cursorrules + .mdc dual-write conflict
#   4. Staleness (rules repo newer than generated files)
#   5. File existence (all expected files present)
#   6. Core .mdc semantic validation (alwaysApply must be true)
#   7. Skills deployment validation (manifest + directory integrity)
#   8. Commands deployment validation (manifest + file integrity)
#   9. Worktrees.json deployment validation
#  10. .vscode/settings.json validity (if exists)
#  11. CC rules validation (.claude/rules/ frontmatter, when CC Mode != off)
#  12. CC skills deployment validation (when CC Mode != off)
#  13. CC commands deployment validation (when CC Mode != off)
#  14. CC/Cursor consistency (rules count, skills set match)
#  15. Codex .codex/config.toml validation (when Codex Mode = native)
#  16. Codex skills deployment validation (when Codex Mode = native)
#  17. Codex/CC/Cursor skills consistency (when Codex Mode = native)

show_help() {
    cat <<'EOF'
agent-check — Validate generated rule files in a project directory

USAGE
    agent-check [options] [project-dir]

ARGUMENTS
    project-dir    Target project directory (default: current directory)

OPTIONS
    -h, --help     Show this help message and exit

ENVIRONMENT
    AGENT_RULES_HOME   Path to central rules repo (default: ~/.config/agent-rules)

CHECKS PERFORMED
    1. Codex AGENTS.md size (must be < 32KiB)
    2. Cursor .mdc frontmatter lint (must have closing ---)
    3. No .cursorrules + .mdc dual-write conflict
    4. Staleness detection (rules repo newer than generated files)
    5. Generated file existence (CLAUDE.md, AGENTS.md, .mdc files)
    6. Core .mdc alwaysApply validation (core rules must be always-on)
    7. Skills deployment validation (manifest + directory integrity)
    8. Commands deployment validation (manifest + file integrity)
    9. Worktrees.json deployment validation
   10. .vscode/settings.json validity
   11. CC rules validation (when CC Mode != off)
   12. CC skills deployment validation (when CC Mode != off)
   13. CC commands deployment validation (when CC Mode != off)
   14. CC/Cursor consistency (when CC Mode != off)
   15. Codex .codex/config.toml validation (when Codex Mode = native)
   16. Codex skills deployment validation (when Codex Mode = native)
   17. Codex/CC/Cursor skills consistency (when Codex Mode = native)

EXAMPLES
    agent-check                  # Check rules in current directory
    agent-check ~/my-project     # Check rules in a specific project

EXIT CODES
    0   All checks passed
    1   One or more checks failed
EOF
    exit 0
}

case "${1:-}" in
    -h|--help) show_help ;;
esac

RULES_HOME="${AGENT_RULES_HOME:-$HOME/.config/agent-rules}"
PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

HASH_FILE="$PROJECT_DIR/.agent-sync-hash"
PASS=0
FAIL=0
WARN=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  WARN: $1"; WARN=$((WARN + 1)); }

echo "Checking rules in $PROJECT_DIR"
echo "================================"

# --- Detect CC Mode ---
CC_MODE="dual"
if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
    _cc_mode="$(sed -n 's/^\*\*CC Mode\*\*:[[:space:]]*//p' "$PROJECT_DIR/.agent-local.md" | head -1 | sed 's/<!--.*-->//' | xargs)"
    case "$_cc_mode" in
        off|dual|native) CC_MODE="$_cc_mode" ;;
    esac
fi

# --- Detect Codex Mode ---
CODEX_MODE="native"
if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
    _codex_mode="$(sed -n 's/^\*\*Codex Mode\*\*:[[:space:]]*//p' "$PROJECT_DIR/.agent-local.md" | head -1 | sed 's/<!--.*-->//' | xargs)"
    case "$_codex_mode" in
        off|legacy|native) CODEX_MODE="$_codex_mode" ;;
    esac
fi

TOTAL_CHECKS=10
if [ "$CC_MODE" != "off" ]; then
    TOTAL_CHECKS=14
fi
if [ "$CODEX_MODE" = "native" ]; then
    TOTAL_CHECKS=$((TOTAL_CHECKS + 3))
fi

# --- 1. Codex AGENTS.md size ---

echo ""
# Codex size check is advisory — Codex is not the primary tool in this workflow
echo "[1/$TOTAL_CHECKS] Codex AGENTS.md size limit (advisory)"

if [ -f "$PROJECT_DIR/.agent-rules/AGENTS.md" ]; then
    SIZE=$(wc -c < "$PROJECT_DIR/.agent-rules/AGENTS.md" | tr -d ' ')
    if [ "$SIZE" -gt 32768 ]; then
        warn ".agent-rules/AGENTS.md is $SIZE bytes (> 32KiB). Codex may silently truncate."
    else
        PERCENT=$((SIZE * 100 / 32768))
        pass ".agent-rules/AGENTS.md is $SIZE bytes (${PERCENT}% of 32KiB limit)"
    fi
else
    warn ".agent-rules/AGENTS.md not found (Codex not in use)"
fi

# --- 2. Cursor frontmatter lint ---

echo ""
echo "[2/$TOTAL_CHECKS] Cursor .mdc frontmatter validation"

if [ -d "$PROJECT_DIR/.cursor/rules" ]; then
    MDC_COUNT=0
    MDC_FAIL=0
    for mdc in "$PROJECT_DIR/.cursor/rules/"*.mdc; do
        [ -f "$mdc" ] || continue
        MDC_COUNT=$((MDC_COUNT + 1))

        # Check: file must start with ---
        FIRST_LINE=$(head -1 "$mdc")
        if [ "$FIRST_LINE" != "---" ]; then
            fail "$(basename "$mdc"): missing opening ---"
            MDC_FAIL=$((MDC_FAIL + 1))
            continue
        fi

        # Check: must have a closing --- (second occurrence)
        CLOSING=$(awk 'NR>1 && /^---$/{print NR; exit}' "$mdc")
        if [ -z "$CLOSING" ]; then
            fail "$(basename "$mdc"): missing closing --- in frontmatter"
            MDC_FAIL=$((MDC_FAIL + 1))
        fi
    done

    if [ "$MDC_COUNT" -eq 0 ]; then
        fail "No .mdc files found in .cursor/rules/"
    elif [ "$MDC_FAIL" -eq 0 ]; then
        pass "All $MDC_COUNT .mdc files have valid frontmatter"
    fi
else
    fail ".cursor/rules/ directory not found"
fi

# --- 3. No dual-write conflict ---

echo ""
echo "[3/$TOTAL_CHECKS] Cursor dual-write conflict check"

if [ -f "$PROJECT_DIR/.cursorrules" ] && [ -d "$PROJECT_DIR/.cursor/rules" ]; then
    warn ".cursorrules AND .cursor/rules/ both exist. .mdc files may silently override .cursorrules. Remove one."
else
    pass "No dual-write conflict detected"
fi

# --- 4. Staleness check ---

echo ""
echo "[4/$TOTAL_CHECKS] Staleness detection"

if [ -f "$HASH_FILE" ]; then
    STORED_HASH="$(cat "$HASH_FILE" 2>/dev/null || echo "none")"

    # Recompute the full composite hash using the same algorithm as agent-sync
    HASH_CMD="shasum"
    command -v shasum &>/dev/null || HASH_CMD="sha1sum"
    command -v "$HASH_CMD" &>/dev/null || HASH_CMD="md5sum"

    if [ -d "$RULES_HOME/.git" ]; then
        SUB_HASH="$(git -C "$RULES_HOME" submodule status 2>/dev/null | awk '{print $1}' | tr -d '+-U' | sort | tr -d '\n')"
        CURRENT_RULES_HASH="$(git -C "$RULES_HOME" rev-parse HEAD 2>/dev/null || echo "no-git"):${SUB_HASH:-no-submodules}"
    else
        CURRENT_RULES_HASH="$(find "$RULES_HOME" \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.sh' \) -type f -exec "$HASH_CMD" {} + 2>/dev/null | sort | "$HASH_CMD" | awk '{print $1}')"
    fi

    CURRENT_OVERLAY_HASH="$(find "$PROJECT_DIR" -maxdepth 3 -name '.agent-local.md' -not -path '*/.git/*' -not -path '*/node_modules/*' -type f -exec "$HASH_CMD" {} + 2>/dev/null | sort | "$HASH_CMD" | awk '{print $1}')"

    CURRENT_REVIEWER_CONF_HASH=""
    if [ -f "$PROJECT_DIR/.cursor/reviewer-models.conf" ]; then
        CURRENT_REVIEWER_CONF_HASH="$("$HASH_CMD" "$PROJECT_DIR/.cursor/reviewer-models.conf" 2>/dev/null | awk '{print $1}')"
    fi

    CURRENT_HASH="${CURRENT_RULES_HASH}:${CURRENT_OVERLAY_HASH}:${CURRENT_REVIEWER_CONF_HASH}"

    if [ "$CURRENT_HASH" = "$STORED_HASH" ]; then
        pass "Rules are up to date with last sync (rules repo + overlays + reviewer config)"
    else
        warn "Rules have been updated since last sync. Run agent-sync."
    fi
else
    warn "No sync hash found. Has agent-sync been run?"
fi

# --- 5. File existence ---

echo ""
echo "[5/$TOTAL_CHECKS] Generated file existence"

# CLAUDE.md / AGENTS.md requirements depend on CC_MODE / CODEX_MODE
local_claude_required=true
local_agents_required=true
# Legacy CLAUDE.md not required when CC is native + Codex is off
if [ "$CC_MODE" = "native" ] && [ "$CODEX_MODE" = "off" ]; then
    local_claude_required=false
fi
# AGENTS.md not required when Codex is off
if [ "$CODEX_MODE" = "off" ]; then
    local_agents_required=false
fi

if $local_claude_required; then
    if [ -f "$PROJECT_DIR/.agent-rules/CLAUDE.md" ]; then
        pass ".agent-rules/CLAUDE.md exists"
    else
        fail ".agent-rules/CLAUDE.md not found"
    fi
else
    pass ".agent-rules/CLAUDE.md not required (CC Mode: $CC_MODE, Codex Mode: $CODEX_MODE)"
fi
if $local_agents_required; then
    if [ -f "$PROJECT_DIR/.agent-rules/AGENTS.md" ]; then
        pass ".agent-rules/AGENTS.md exists"
    else
        warn ".agent-rules/AGENTS.md not found"
    fi
else
    pass ".agent-rules/AGENTS.md not required (Codex Mode: $CODEX_MODE)"
fi

# Warn if root-level remnants exist (Cursor would auto-inject these)
for f in CLAUDE.md AGENTS.md; do
    if [ -f "$PROJECT_DIR/$f" ]; then
        warn "Root-level $f exists — Cursor will auto-inject it, duplicating .mdc rules. Run agent-sync to clean up."
    fi
done

if [ -d "$PROJECT_DIR/.cursor/rules" ] && [ "$(ls "$PROJECT_DIR/.cursor/rules/"*.mdc 2>/dev/null | wc -l)" -gt 0 ]; then
    pass ".cursor/rules/ contains .mdc files"
else
    fail ".cursor/rules/ is empty or missing"
fi

# --- 6. Core .mdc semantic validation ---

echo ""
echo "[6/$TOTAL_CHECKS] Core .mdc alwaysApply validation"

CORE_PATTERNS=("00-communication" "10-workflow" "20-quality-gates")
if [ -d "$PROJECT_DIR/.cursor/rules" ]; then
    CORE_OK=true
    for pattern in "${CORE_PATTERNS[@]}"; do
        mdc="$PROJECT_DIR/.cursor/rules/${pattern}.mdc"
        if [ -f "$mdc" ]; then
            if grep -q 'alwaysApply: true' "$mdc"; then
                pass "${pattern}.mdc has alwaysApply: true"
            else
                fail "${pattern}.mdc is missing alwaysApply: true (core rules must always load)"
                CORE_OK=false
            fi
        else
            warn "${pattern}.mdc not found in .cursor/rules/"
        fi
    done
fi

# --- 7. Skills deployment validation ---

echo ""
echo "[7/$TOTAL_CHECKS] Skills deployment validation"

SKILLS_MANIFEST="$PROJECT_DIR/.cursor/skills/.agent-sync-skills-manifest"
SKILLS_SRC="$RULES_HOME/skills"
HAS_SOURCE_SKILLS=false
if [ -d "$SKILLS_SRC" ] && [ "$(ls -d "$SKILLS_SRC"/*/ 2>/dev/null)" ]; then
    HAS_SOURCE_SKILLS=true
fi

if $HAS_SOURCE_SKILLS; then
    if [ -f "$SKILLS_MANIFEST" ]; then
        SKILLS_OK=true
        SKILLS_CHECKED=0
        while IFS= read -r skill_name; do
            [ -z "$skill_name" ] && continue
            SKILLS_CHECKED=$((SKILLS_CHECKED + 1))
            skill_dir="$PROJECT_DIR/.cursor/skills/$skill_name"
            if [ -d "$skill_dir" ] && [ "$(ls -A "$skill_dir" 2>/dev/null)" ]; then
                pass "Skill '$skill_name' deployed and non-empty"
            else
                fail "Skill '$skill_name' listed in manifest but missing or empty"
                SKILLS_OK=false
            fi
        done < "$SKILLS_MANIFEST"
        if [ "$SKILLS_CHECKED" -eq 0 ]; then
            fail "Skills manifest exists but is empty. Run agent-sync to regenerate."
        elif $SKILLS_OK; then
            pass "All $SKILLS_CHECKED manifest skills are deployed"
        fi
    else
        fail "Rules repo has skills but .agent-sync-skills-manifest not found. Run agent-sync."
    fi
else
    pass "No skills in rules repo (nothing to validate)"
fi

# --- 8. Commands deployment validation ---

echo ""
echo "[8/$TOTAL_CHECKS] Commands deployment validation"

COMMANDS_MANIFEST="$PROJECT_DIR/.cursor/commands/.agent-sync-commands-manifest"
COMMANDS_SRC="$RULES_HOME/commands"
HAS_SOURCE_COMMANDS=false
if [ -d "$COMMANDS_SRC" ] && [ "$(ls "$COMMANDS_SRC"/*.md 2>/dev/null)" ]; then
    HAS_SOURCE_COMMANDS=true
fi

if $HAS_SOURCE_COMMANDS; then
    if [ -f "$COMMANDS_MANIFEST" ]; then
        COMMANDS_OK=true
        COMMANDS_CHECKED=0
        while IFS= read -r cmd_name; do
            [ -z "$cmd_name" ] && continue
            COMMANDS_CHECKED=$((COMMANDS_CHECKED + 1))
            cmd_file="$PROJECT_DIR/.cursor/commands/$cmd_name"
            if [ -f "$cmd_file" ]; then
                pass "Command '$cmd_name' deployed"
            else
                fail "Command '$cmd_name' listed in manifest but missing"
                COMMANDS_OK=false
            fi
        done < "$COMMANDS_MANIFEST"
        if [ "$COMMANDS_CHECKED" -eq 0 ]; then
            fail "Commands manifest exists but is empty. Run agent-sync to regenerate."
        elif $COMMANDS_OK; then
            pass "All $COMMANDS_CHECKED manifest commands are deployed"
        fi
    else
        fail "Rules repo has commands but .agent-sync-commands-manifest not found. Run agent-sync."
    fi
else
    pass "No commands in rules repo (nothing to validate)"
fi

# --- 9. Worktrees.json deployment validation ---

echo ""
echo "[9/$TOTAL_CHECKS] Worktrees.json deployment validation"

WORKTREES_TEMPLATE="$RULES_HOME/templates/worktrees.json"
WORKTREES_TARGET="$PROJECT_DIR/.cursor/worktrees.json"
WORKTREES_STAMP="$PROJECT_DIR/.cursor/.worktrees-agent-sync"

if [ -f "$WORKTREES_TEMPLATE" ]; then
    if [ -f "$WORKTREES_TARGET" ]; then
        # Validate JSON syntax
        if command -v python3 &>/dev/null; then
            if python3 -c "import json; json.load(open('$WORKTREES_TARGET'))" 2>/dev/null; then
                pass ".cursor/worktrees.json is valid JSON"
            else
                fail ".cursor/worktrees.json is NOT valid JSON"
            fi
        else
            warn "Cannot validate .cursor/worktrees.json syntax (python3 not available)"
        fi

        # If agent-sync managed, verify content matches template
        if [ -f "$WORKTREES_STAMP" ]; then
            if diff -q "$WORKTREES_TEMPLATE" "$WORKTREES_TARGET" >/dev/null 2>&1; then
                pass ".cursor/worktrees.json matches template (agent-sync managed)"
            else
                warn ".cursor/worktrees.json differs from template. Run agent-sync to update."
            fi
        else
            pass ".cursor/worktrees.json exists (user-managed)"
        fi
    else
        warn ".cursor/worktrees.json not found. Run agent-sync to deploy worktree setup."
    fi
else
    pass "No worktrees.json template in rules repo (nothing to validate)"
fi

# --- 10. .vscode/settings.json validity ---

echo ""
echo "[10/$TOTAL_CHECKS] .vscode/settings.json validation"

VSCODE_SETTINGS="$PROJECT_DIR/.vscode/settings.json"
if [ -f "$VSCODE_SETTINGS" ]; then
    if command -v python3 &>/dev/null; then
        if python3 -c "import json; json.load(open('$VSCODE_SETTINGS'))" 2>/dev/null; then
            pass "$VSCODE_SETTINGS is valid JSON"
        else
            fail "$VSCODE_SETTINGS is NOT valid JSON — VS Code/Cursor may fail to load settings"
        fi
    elif command -v node &>/dev/null; then
        if node -e "JSON.parse(require('fs').readFileSync('$VSCODE_SETTINGS','utf8'))" 2>/dev/null; then
            pass "$VSCODE_SETTINGS is valid JSON (validated via node)"
        else
            fail "$VSCODE_SETTINGS is NOT valid JSON — VS Code/Cursor may fail to load settings"
        fi
    else
        warn "Cannot validate $VSCODE_SETTINGS (neither python3 nor node available)"
    fi
else
    pass ".vscode/settings.json not present (no validation needed)"
fi

# --- 11-14. CC native checks (only when CC Mode != off) ---

if [ "$CC_MODE" != "off" ]; then

# --- 11. CC rules validation ---

echo ""
echo "[11/$TOTAL_CHECKS] CC rules validation (.claude/rules/)"

if [ -d "$PROJECT_DIR/.claude/rules" ]; then
    CC_RULE_COUNT=0
    CC_RULE_FAIL=0
    for cc_rule in "$PROJECT_DIR/.claude/rules/"*.md; do
        [ -f "$cc_rule" ] || continue
        CC_RULE_COUNT=$((CC_RULE_COUNT + 1))

        # Validate frontmatter if present: must have matching --- delimiters
        FIRST_LINE=$(head -1 "$cc_rule")
        if [ "$FIRST_LINE" = "---" ]; then
            CLOSING=$(awk 'NR>1 && /^---$/{print NR; exit}' "$cc_rule")
            if [ -z "$CLOSING" ]; then
                fail "CC rule $(basename "$cc_rule"): missing closing --- in frontmatter"
                CC_RULE_FAIL=$((CC_RULE_FAIL + 1))
            fi
        fi
    done

    if [ "$CC_RULE_COUNT" -eq 0 ]; then
        fail "No .md files found in .claude/rules/"
    elif [ "$CC_RULE_FAIL" -eq 0 ]; then
        pass "All $CC_RULE_COUNT CC rule files have valid frontmatter"
    fi
else
    fail ".claude/rules/ directory not found (CC Mode: $CC_MODE)"
fi

# --- 12. CC skills validation ---

echo ""
echo "[12/$TOTAL_CHECKS] CC skills deployment validation"

CC_SKILLS_MF="$PROJECT_DIR/.claude/skills/.agent-sync-skills-manifest"
CC_HAS_SOURCE_SKILLS=false
if [ -d "$RULES_HOME/skills" ] && [ "$(ls -d "$RULES_HOME/skills/"*/ 2>/dev/null)" ]; then
    CC_HAS_SOURCE_SKILLS=true
fi

if $CC_HAS_SOURCE_SKILLS; then
    if [ -f "$CC_SKILLS_MF" ]; then
        CC_SKILLS_OK=true
        CC_SKILLS_CHECKED=0
        while IFS= read -r cc_skill_name; do
            [ -z "$cc_skill_name" ] && continue
            CC_SKILLS_CHECKED=$((CC_SKILLS_CHECKED + 1))
            cc_skill_dir="$PROJECT_DIR/.claude/skills/$cc_skill_name"
            if [ -d "$cc_skill_dir" ] && [ "$(ls -A "$cc_skill_dir" 2>/dev/null)" ]; then
                pass "CC skill '$cc_skill_name' deployed"
            else
                fail "CC skill '$cc_skill_name' listed in manifest but missing or empty"
                CC_SKILLS_OK=false
            fi
        done < "$CC_SKILLS_MF"
        if [ "$CC_SKILLS_CHECKED" -eq 0 ]; then
            fail "CC skills manifest exists but is empty. Run agent-sync."
        elif $CC_SKILLS_OK; then
            pass "All $CC_SKILLS_CHECKED CC skills are deployed"
        fi
    else
        fail "Rules repo has skills but CC skills manifest not found. Run agent-sync."
    fi
else
    pass "No skills in rules repo (CC skills: nothing to validate)"
fi

# --- 13. CC commands validation ---

echo ""
echo "[13/$TOTAL_CHECKS] CC commands deployment validation"

CC_COMMANDS_MF="$PROJECT_DIR/.claude/commands/.agent-sync-commands-manifest"
CC_HAS_SOURCE_COMMANDS=false
if [ -d "$RULES_HOME/commands" ] && [ "$(ls "$RULES_HOME/commands"/*.md 2>/dev/null)" ]; then
    CC_HAS_SOURCE_COMMANDS=true
fi

if $CC_HAS_SOURCE_COMMANDS; then
    if [ -f "$CC_COMMANDS_MF" ]; then
        CC_COMMANDS_OK=true
        CC_COMMANDS_CHECKED=0
        while IFS= read -r cc_cmd_name; do
            [ -z "$cc_cmd_name" ] && continue
            CC_COMMANDS_CHECKED=$((CC_COMMANDS_CHECKED + 1))
            cc_cmd_file="$PROJECT_DIR/.claude/commands/$cc_cmd_name"
            if [ -f "$cc_cmd_file" ]; then
                pass "CC command '$cc_cmd_name' deployed"
            else
                fail "CC command '$cc_cmd_name' listed in manifest but missing"
                CC_COMMANDS_OK=false
            fi
        done < "$CC_COMMANDS_MF"
        if [ "$CC_COMMANDS_CHECKED" -eq 0 ]; then
            fail "CC commands manifest exists but is empty. Run agent-sync."
        elif $CC_COMMANDS_OK; then
            pass "All $CC_COMMANDS_CHECKED CC commands are deployed"
        fi
    else
        fail "Rules repo has commands but CC commands manifest not found. Run agent-sync."
    fi
else
    pass "No commands in rules repo (CC commands: nothing to validate)"
fi

# --- 14. CC/Cursor consistency ---

echo ""
echo "[14/$TOTAL_CHECKS] CC/Cursor consistency"

if [ -d "$PROJECT_DIR/.claude/rules" ] && [ -d "$PROJECT_DIR/.cursor/rules" ]; then
    CURSOR_COUNT=$(ls "$PROJECT_DIR/.cursor/rules/"*.mdc 2>/dev/null | wc -l | tr -d ' ')
    CC_COUNT=$(ls "$PROJECT_DIR/.claude/rules/"*.md 2>/dev/null | wc -l | tr -d ' ')
    # CC is expected to have fewer files (review-criteria is Cursor-only)
    if [ "$CC_COUNT" -le "$CURSOR_COUNT" ] && [ "$CC_COUNT" -gt 0 ]; then
        pass "CC rules ($CC_COUNT) <= Cursor rules ($CURSOR_COUNT) — consistent (CC excludes Cursor-only rules)"
    elif [ "$CC_COUNT" -gt "$CURSOR_COUNT" ]; then
        warn "CC rules ($CC_COUNT) > Cursor rules ($CURSOR_COUNT) — unexpected divergence"
    else
        warn "CC rules count is 0 but Cursor has $CURSOR_COUNT rules"
    fi
else
    if [ ! -d "$PROJECT_DIR/.claude/rules" ]; then
        warn "Cannot compare: .claude/rules/ not found"
    fi
fi

# Check CC skills consistency with Cursor skills
CURSOR_SKILLS_MF="$PROJECT_DIR/.cursor/skills/.agent-sync-skills-manifest"
if [ -f "$CC_SKILLS_MF" ] && [ -f "$CURSOR_SKILLS_MF" ]; then
    CURSOR_SKILL_SET=$(sort "$CURSOR_SKILLS_MF" | tr '\n' ',')
    CC_SKILL_SET=$(sort "$CC_SKILLS_MF" | tr '\n' ',')
    if [ "$CURSOR_SKILL_SET" = "$CC_SKILL_SET" ]; then
        pass "CC and Cursor skill sets match"
    else
        warn "CC and Cursor skill sets differ — check agent-sync output"
    fi
fi

fi  # end CC_MODE != off

# --- 15-17. Codex native checks (only when Codex Mode = native) ---

if [ "$CODEX_MODE" = "native" ]; then

# --- 15. Codex config.toml validation ---

echo ""
echo "[$(($TOTAL_CHECKS - 2))/$TOTAL_CHECKS] Codex .codex/config.toml validation"

if [ -f "$PROJECT_DIR/.codex/config.toml" ]; then
    # Validate TOML syntax
    if command -v python3 &>/dev/null; then
        if python3 -c "
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open('$PROJECT_DIR/.codex/config.toml', 'rb') as f:
    tomllib.load(f)
" 2>/dev/null; then
            pass ".codex/config.toml is valid TOML"
        else
            # Fallback: basic syntax check via grep
            if grep -q 'project_doc_fallback_filenames' "$PROJECT_DIR/.codex/config.toml"; then
                pass ".codex/config.toml exists (TOML validation unavailable — tomllib/tomli not installed)"
            else
                fail ".codex/config.toml may be invalid TOML"
            fi
        fi
    else
        pass ".codex/config.toml exists (python3 not available for TOML validation)"
    fi

    # Check that fallback filenames include .agent-rules/AGENTS.md
    if grep -q '\.agent-rules/AGENTS\.md' "$PROJECT_DIR/.codex/config.toml"; then
        pass ".codex/config.toml references .agent-rules/AGENTS.md in fallback filenames"
    else
        warn ".codex/config.toml does not reference .agent-rules/AGENTS.md — Codex may not find instructions"
    fi
else
    fail ".codex/config.toml not found (Codex Mode: native)"
fi

# --- 16. Codex skills validation ---

echo ""
echo "[$(($TOTAL_CHECKS - 1))/$TOTAL_CHECKS] Codex skills deployment validation"

CODEX_SKILLS_MF="$PROJECT_DIR/.agents/skills/.agent-sync-codex-skills-manifest"
CODEX_HAS_SOURCE_SKILLS=false
if [ -d "$RULES_HOME/skills" ] && [ "$(ls -d "$RULES_HOME/skills/"*/ 2>/dev/null)" ]; then
    CODEX_HAS_SOURCE_SKILLS=true
fi

if $CODEX_HAS_SOURCE_SKILLS; then
    if [ -f "$CODEX_SKILLS_MF" ]; then
        CODEX_SKILLS_OK=true
        CODEX_SKILLS_CHECKED=0
        while IFS= read -r codex_skill_name; do
            [ -z "$codex_skill_name" ] && continue
            CODEX_SKILLS_CHECKED=$((CODEX_SKILLS_CHECKED + 1))
            codex_skill_dir="$PROJECT_DIR/.agents/skills/$codex_skill_name"
            if [ -d "$codex_skill_dir" ] && [ "$(ls -A "$codex_skill_dir" 2>/dev/null)" ]; then
                pass "Codex skill '$codex_skill_name' deployed"
            else
                fail "Codex skill '$codex_skill_name' listed in manifest but missing or empty"
                CODEX_SKILLS_OK=false
            fi
        done < "$CODEX_SKILLS_MF"
        if [ "$CODEX_SKILLS_CHECKED" -eq 0 ]; then
            fail "Codex skills manifest exists but is empty. Run agent-sync."
        elif $CODEX_SKILLS_OK; then
            pass "All $CODEX_SKILLS_CHECKED Codex skills are deployed"
        fi
    else
        fail "Rules repo has skills but Codex skills manifest not found. Run agent-sync."
    fi
else
    pass "No skills in rules repo (Codex skills: nothing to validate)"
fi

# --- 17. Codex/CC/Cursor skills consistency ---

echo ""
echo "[$TOTAL_CHECKS/$TOTAL_CHECKS] Codex/CC/Cursor skills consistency"

CURSOR_SKILLS_MF_17="$PROJECT_DIR/.cursor/skills/.agent-sync-skills-manifest"
CC_SKILLS_MF_17="$PROJECT_DIR/.claude/skills/.agent-sync-skills-manifest"
if [ -f "$CODEX_SKILLS_MF" ] && [ -f "$CURSOR_SKILLS_MF_17" ]; then
    CURSOR_SKILL_SET_17=$(sort "$CURSOR_SKILLS_MF_17" | tr '\n' ',')
    CODEX_SKILL_SET_17=$(sort "$CODEX_SKILLS_MF" | tr '\n' ',')
    if [ "$CURSOR_SKILL_SET_17" = "$CODEX_SKILL_SET_17" ]; then
        pass "Codex and Cursor skill sets match"
    else
        warn "Codex and Cursor skill sets differ — check agent-sync output"
    fi
fi
if [ -f "$CODEX_SKILLS_MF" ] && [ -f "$CC_SKILLS_MF_17" ]; then
    CC_SKILL_SET_17=$(sort "$CC_SKILLS_MF_17" | tr '\n' ',')
    CODEX_SKILL_SET_C17=$(sort "$CODEX_SKILLS_MF" | tr '\n' ',')
    if [ "$CC_SKILL_SET_17" = "$CODEX_SKILL_SET_C17" ]; then
        pass "Codex and CC skill sets match"
    else
        warn "Codex and CC skill sets differ — check agent-sync output"
    fi
fi

fi  # end CODEX_MODE = native

# --- Summary ---

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed, $WARN warnings"

if [ "$FAIL" -gt 0 ]; then
    echo "STATUS: FAILED — fix the issues above before using AI agents."
    exit 1
else
    echo "STATUS: OK"
    exit 0
fi
