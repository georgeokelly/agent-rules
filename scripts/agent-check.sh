#!/usr/bin/env bash
set -euo pipefail

# agent-check.sh — Validate generated rule files in a project directory
# Usage: agent-check.sh [project-dir]
#
# Checks:
#   1. Codex AGENTS.override.md size (must be < 32KiB) — HIST-007
#   2. Cursor .mdc frontmatter lint (must have closing ---)
#   3. No .cursorrules + .mdc dual-write conflict
#   4. Staleness (rules repo newer than generated files)
#   5. File existence (root AGENTS.override.md present, legacy paths absent)
#   6. Core .mdc semantic validation (alwaysApply must be true)
#   7. Skills deployment validation (manifest + directory integrity)
#   8. Worktrees.json deployment validation
#   9. .vscode/settings.json validity (if exists)
#  10. CC rules validation (.claude/rules/ frontmatter, when CC Mode != off)
#  11. CC skills deployment validation (when CC Mode != off)
#  12. CC/Cursor consistency (rules count, skills set match)
#  13. Codex .codex/config.toml validation (child_agents_md, no fallback) — HIST-007
#  14. Codex skills deployment validation (when Codex Mode = native)
#  15. Codex/CC/Cursor skills consistency (when Codex Mode = native)
#  16. OpenCode opencode.json validation (when OpenCode Mode = native) — HIST-006
#  17. OpenCode skills deployment validation (when OpenCode Mode = native)
#  18. OpenCode/CC/Cursor skills consistency (when OpenCode Mode = native)

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
    AGENT_TOOLKIT_HOME   Path to central rules repo (default: ~/.config/agent-toolkit)

CHECKS PERFORMED
    1. Codex AGENTS.override.md size (must be < 32KiB)
    2. Cursor .mdc frontmatter lint (must have closing ---)
    3. No .cursorrules + .mdc dual-write conflict
    4. Staleness detection (rules repo newer than generated files)
    5. Generated file existence (root AGENTS.override.md, legacy paths absent)
    6. Core .mdc alwaysApply validation (core rules must be always-on)
    7. Skills deployment validation (manifest + directory integrity)
    8. Worktrees.json deployment validation
    9. .vscode/settings.json validity
   10. CC rules validation (when CC Mode != off)
   11. CC skills deployment validation (when CC Mode != off)
   12. CC/Cursor consistency (when CC Mode != off)
   13. Codex .codex/config.toml validation (when Codex Mode = native)
   14. Codex skills deployment validation (when Codex Mode = native)
   15. Codex/CC/Cursor skills consistency (when Codex Mode = native)
   16. OpenCode opencode.json validation (when OpenCode Mode = native)
   17. OpenCode skills deployment validation (when OpenCode Mode = native)
   18. OpenCode/CC/Cursor skills consistency (when OpenCode Mode = native)

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

RULES_HOME="${AGENT_TOOLKIT_HOME:-$HOME/.config/agent-toolkit}"
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
# HIST-004: 'dual' was removed; it silently folds to 'native' here so an old
# overlay doesn't falsely trigger "Unknown CC Mode" warnings. resolve_cc_mode
# in agent-sync emits the deprecation warning on the sync side.
CC_MODE="native"
if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
    _cc_mode="$(sed -n 's/^\*\*CC Mode\*\*:[[:space:]]*//p' "$PROJECT_DIR/.agent-local.md" | head -1 | sed 's/<!--.*-->//' | xargs)"
    case "$_cc_mode" in
        off|native) CC_MODE="$_cc_mode" ;;
        dual) CC_MODE="native" ;;
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

# --- Detect OpenCode Mode (HIST-006) ---
# Two valid values: 'native' (default) and 'off'. Anything else falls back
# to 'native' silently, mirroring the CC Mode behaviour.
OPENCODE_MODE="native"
if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
    _opencode_mode="$(sed -n 's/^\*\*OpenCode Mode\*\*:[[:space:]]*//p' "$PROJECT_DIR/.agent-local.md" | head -1 | sed 's/<!--.*-->//' | xargs)"
    case "$_opencode_mode" in
        off|native) OPENCODE_MODE="$_opencode_mode" ;;
    esac
fi

TOTAL_CHECKS=9
# Base offset for each optional block. Keeps per-check indices stable
# regardless of which optional blocks run below (formerly the Codex block
# assumed it was the last block and used $TOTAL_CHECKS-2 arithmetic; that
# breaks once OpenCode checks sit after it).
CODEX_BASE=9
OPENCODE_BASE=9
if [ "$CC_MODE" != "off" ]; then
    TOTAL_CHECKS=$((TOTAL_CHECKS + 3))
    CODEX_BASE=$((CODEX_BASE + 3))
    OPENCODE_BASE=$((OPENCODE_BASE + 3))
fi
if [ "$CODEX_MODE" = "native" ]; then
    TOTAL_CHECKS=$((TOTAL_CHECKS + 3))
    OPENCODE_BASE=$((OPENCODE_BASE + 3))
fi
if [ "$OPENCODE_MODE" = "native" ]; then
    TOTAL_CHECKS=$((TOTAL_CHECKS + 3))
fi

# --- 1. Codex AGENTS.override.md size ---

echo ""
# Codex size check is advisory — Codex is not the primary tool in this workflow.
# HIST-007: file moved from .agent-rules/AGENTS.md to root AGENTS.override.md
# so it is discovered natively without the project_doc_fallback_filenames
# indirection.
echo "[1/$TOTAL_CHECKS] Codex AGENTS.override.md size limit (advisory)"

if [ -f "$PROJECT_DIR/AGENTS.override.md" ]; then
    SIZE=$(wc -c < "$PROJECT_DIR/AGENTS.override.md" | tr -d ' ')
    if [ "$SIZE" -gt 32768 ]; then
        warn "AGENTS.override.md is $SIZE bytes (> 32KiB). Codex may silently truncate."
    else
        PERCENT=$((SIZE * 100 / 32768))
        pass "AGENTS.override.md is $SIZE bytes (${PERCENT}% of 32KiB limit)"
    fi
else
    warn "AGENTS.override.md not found (Codex not in use)"
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

    CURRENT_HASH="${CURRENT_RULES_HASH}:${CURRENT_OVERLAY_HASH}"

    if [ "$CURRENT_HASH" = "$STORED_HASH" ]; then
        pass "Rules are up to date with last sync (rules repo + overlays)"
    else
        warn "Rules have been updated since last sync. Run agent-sync."
    fi
else
    warn "No sync hash found. Has agent-sync been run?"
fi

# --- 5. File existence ---

echo ""
echo "[5/$TOTAL_CHECKS] Generated file existence"

# HIST-004: CLAUDE.md is no longer generated — we assert its absence so
# upgrading projects that didn't run `agent-sync` yet get a clear fail
# signal pointing at the decommission.
# HIST-007: same treatment for the legacy .agent-rules/AGENTS.md path —
# it should have been swept by `cleanup_remnants()` on the next sync.
if [ -f "$PROJECT_DIR/.agent-rules/CLAUDE.md" ]; then
    fail ".agent-rules/CLAUDE.md present — run 'agent-sync' to purge (HIST-004 decommissioned CLAUDE.md)"
else
    pass ".agent-rules/CLAUDE.md absent (HIST-004 — CLAUDE.md decommissioned)"
fi

if [ -f "$PROJECT_DIR/.agent-rules/AGENTS.md" ]; then
    fail ".agent-rules/AGENTS.md present — run 'agent-sync' to purge (HIST-007 — moved to root AGENTS.override.md)"
else
    pass ".agent-rules/AGENTS.md absent (HIST-007 — relocated to root AGENTS.override.md)"
fi

# AGENTS.override.md required only when Codex mode is non-off.
local_agents_required=true
[ "$CODEX_MODE" = "off" ] && local_agents_required=false

if $local_agents_required; then
    if [ -f "$PROJECT_DIR/AGENTS.override.md" ]; then
        pass "AGENTS.override.md exists"
    else
        warn "AGENTS.override.md not found"
    fi
else
    pass "AGENTS.override.md not required (Codex Mode: $CODEX_MODE)"
fi

# Warn if root-level remnants exist (Cursor would auto-inject these).
# AGENTS.override.md is exempt: Cursor's auto-injection list only matches
# AGENTS.md / CLAUDE.md by exact filename (verified 2026-04-25 against
# Cursor docs at cursor.com/docs/context/rules — only AGENTS.md is listed
# in the "AGENTS.md" / "Nested AGENTS.md support" sections).
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

# --- 8. Worktrees.json deployment validation ---

echo ""
echo "[8/$TOTAL_CHECKS] Worktrees.json deployment validation"

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

# --- 9. .vscode/settings.json validity ---

echo ""
echo "[9/$TOTAL_CHECKS] .vscode/settings.json validation"

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

# --- 10-12. CC native checks (only when CC Mode != off) ---

if [ "$CC_MODE" != "off" ]; then

# --- 10. CC rules validation ---

echo ""
echo "[10/$TOTAL_CHECKS] CC rules validation (.claude/rules/)"

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

# --- 11. CC skills validation ---

echo ""
echo "[11/$TOTAL_CHECKS] CC skills deployment validation"

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

# --- 12. CC/Cursor consistency ---

echo ""
echo "[12/$TOTAL_CHECKS] CC/Cursor consistency"

if [ -d "$PROJECT_DIR/.claude/rules" ] && [ -d "$PROJECT_DIR/.cursor/rules" ]; then
    CURSOR_COUNT=$(ls "$PROJECT_DIR/.cursor/rules/"*.mdc 2>/dev/null | wc -l | tr -d ' ')
    CC_COUNT=$(ls "$PROJECT_DIR/.claude/rules/"*.md 2>/dev/null | wc -l | tr -d ' ')
    # CC_COUNT <= CURSOR_COUNT is the expected steady state: gen-cursor.sh deploys
    # ALL packs unconditionally, while gen-claude.sh filters by pack_is_active().
    # Any overlay that activates fewer than all packs (the common case) will
    # legitimately produce a smaller CC rule set. Divergence is only suspicious
    # when CC > Cursor (which means Cursor dropped something it should not have).
    if [ "$CC_COUNT" -gt 0 ] && [ "$CURSOR_COUNT" -gt 0 ] && [ "$CC_COUNT" -le "$CURSOR_COUNT" ]; then
        if [ "$CC_COUNT" -eq "$CURSOR_COUNT" ]; then
            pass "CC rules ($CC_COUNT) = Cursor rules ($CURSOR_COUNT) — consistent"
        else
            pass "CC rules ($CC_COUNT) <= Cursor rules ($CURSOR_COUNT) — consistent (CC filters inactive packs)"
        fi
    elif [ "$CC_COUNT" -gt "$CURSOR_COUNT" ]; then
        warn "CC rules ($CC_COUNT) > Cursor rules ($CURSOR_COUNT) — unexpected divergence"
    elif [ "$CC_COUNT" -eq 0 ] && [ "$CURSOR_COUNT" -gt 0 ]; then
        # CC_MODE != off but .claude/rules is empty while .cursor/rules is populated —
        # indicates a failed or partial CC sync, not an empty-repo state.
        warn "CC rules (0) while Cursor rules ($CURSOR_COUNT) populated — CC deployment may have failed"
    else
        warn "Both CC and Cursor rule dirs are empty"
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

# --- 13-15. Codex native checks (only when Codex Mode = native) ---

if [ "$CODEX_MODE" = "native" ]; then

# --- 13. Codex config.toml validation ---

echo ""
echo "[$((CODEX_BASE + 1))/$TOTAL_CHECKS] Codex .codex/config.toml validation"

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
            # Fallback: basic syntax check via grep — child_agents_md is the
            # only flag agent-sync still writes post-HIST-007.
            if grep -q 'child_agents_md' "$PROJECT_DIR/.codex/config.toml"; then
                pass ".codex/config.toml exists (TOML validation unavailable — tomllib/tomli not installed)"
            else
                fail ".codex/config.toml may be invalid TOML"
            fi
        fi
    else
        pass ".codex/config.toml exists (python3 not available for TOML validation)"
    fi

    # HIST-007: project_doc_fallback_filenames is no longer written. The
    # only flag agent-sync now manages is `child_agents_md`. A stray
    # fallback line typically means an old config survived a partial
    # upgrade — surface it as a warn so the user re-runs `agent-sync`.
    if grep -q 'child_agents_md' "$PROJECT_DIR/.codex/config.toml"; then
        pass ".codex/config.toml has child_agents_md = true (sub-repo overlays enabled)"
    else
        warn ".codex/config.toml missing child_agents_md = true — sub-repo AGENTS.override.md will not load"
    fi

    if grep -q 'project_doc_fallback_filenames' "$PROJECT_DIR/.codex/config.toml"; then
        warn "Stale 'project_doc_fallback_filenames' in .codex/config.toml (HIST-007 removed it). Re-run agent-sync."
    fi
else
    fail ".codex/config.toml not found (Codex Mode: native)"
fi

# --- 14. Codex skills validation ---

echo ""
echo "[$((CODEX_BASE + 2))/$TOTAL_CHECKS] Codex skills deployment validation"

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

# --- 15. Codex/CC/Cursor skills consistency ---

echo ""
echo "[$((CODEX_BASE + 3))/$TOTAL_CHECKS] Codex/CC/Cursor skills consistency"

# Re-declare the peer manifest paths locally — CC_SKILLS_MF / CURSOR_SKILLS_MF
# are only set inside the CC_MODE != off block above, but this Codex block can
# run independently (e.g. CC_MODE=off + Codex=native), so we need our own copy
# to avoid unbound-variable failures under set -u.
CODEX_CHECK_CURSOR_SKILLS_MF="$PROJECT_DIR/.cursor/skills/.agent-sync-skills-manifest"
CODEX_CHECK_CC_SKILLS_MF="$PROJECT_DIR/.claude/skills/.agent-sync-skills-manifest"
if [ -f "$CODEX_SKILLS_MF" ] && [ -f "$CODEX_CHECK_CURSOR_SKILLS_MF" ]; then
    CODEX_CHECK_CURSOR_SET=$(sort "$CODEX_CHECK_CURSOR_SKILLS_MF" | tr '\n' ',')
    CODEX_CHECK_CODEX_SET=$(sort "$CODEX_SKILLS_MF" | tr '\n' ',')
    if [ "$CODEX_CHECK_CURSOR_SET" = "$CODEX_CHECK_CODEX_SET" ]; then
        pass "Codex and Cursor skill sets match"
    else
        warn "Codex and Cursor skill sets differ — check agent-sync output"
    fi
fi
if [ -f "$CODEX_SKILLS_MF" ] && [ -f "$CODEX_CHECK_CC_SKILLS_MF" ]; then
    CODEX_CHECK_CC_SET=$(sort "$CODEX_CHECK_CC_SKILLS_MF" | tr '\n' ',')
    CODEX_CHECK_CODEX_SET_FOR_CC=$(sort "$CODEX_SKILLS_MF" | tr '\n' ',')
    if [ "$CODEX_CHECK_CC_SET" = "$CODEX_CHECK_CODEX_SET_FOR_CC" ]; then
        pass "Codex and CC skill sets match"
    else
        warn "Codex and CC skill sets differ — check agent-sync output"
    fi
fi

fi  # end CODEX_MODE = native

# --- 16-18. OpenCode native checks (only when OpenCode Mode = native) ---
# HIST-006: OpenCode parity with Cursor/CC/Codex. opencode.json is marker-
# gated (see gen-opencode.sh) — absent marker = user-authored, which is
# allowed; we only require the file to be valid JSON in that case.

if [ "$OPENCODE_MODE" = "native" ]; then

# --- 16. OpenCode opencode.json validation ---

echo ""
echo "[$((OPENCODE_BASE + 1))/$TOTAL_CHECKS] OpenCode opencode.json validation"

OPENCODE_CONFIG="$PROJECT_DIR/opencode.json"
if [ -f "$OPENCODE_CONFIG" ]; then
    # Step 1: JSON syntax must parse regardless of ownership. A broken
    # opencode.json silently disables OpenCode, so we always flag it.
    if command -v python3 &>/dev/null; then
        if python3 -c "import json; json.load(open('$OPENCODE_CONFIG'))" 2>/dev/null; then
            pass "opencode.json is valid JSON"
        else
            fail "opencode.json is NOT valid JSON"
        fi
    elif command -v node &>/dev/null; then
        if node -e "JSON.parse(require('fs').readFileSync('$OPENCODE_CONFIG','utf8'))" 2>/dev/null; then
            pass "opencode.json is valid JSON (validated via node)"
        else
            fail "opencode.json is NOT valid JSON"
        fi
    else
        warn "Cannot validate opencode.json syntax (neither python3 nor node available)"
    fi

    # Step 2: only agent-sync-owned files (carrying the sentinel marker)
    # are expected to match the instructions globs we emit. User-authored
    # files pass as-is.
    if grep -q '"_generated_by": "agent-sync"' "$OPENCODE_CONFIG" 2>/dev/null; then
        # instructions must at minimum reference .cursor/rules/*.mdc —
        # that is the unconditional emitter (see generate_opencode_config).
        if grep -q '\.cursor/rules/\*\.mdc' "$OPENCODE_CONFIG"; then
            pass "opencode.json (agent-sync managed) references .cursor/rules/*.mdc"
        else
            fail "opencode.json (agent-sync managed) is missing .cursor/rules/*.mdc glob"
        fi
    else
        pass "opencode.json exists (user-managed — not checked for agent-sync conventions)"
    fi
else
    fail "opencode.json not found (OpenCode Mode: native)"
fi

# --- 17. OpenCode skills validation ---

echo ""
echo "[$((OPENCODE_BASE + 2))/$TOTAL_CHECKS] OpenCode skills deployment validation"

OPENCODE_SKILLS_MF="$PROJECT_DIR/.opencode/skills/.agent-sync-skills-manifest"
OPENCODE_HAS_SOURCE_SKILLS=false
if [ -d "$RULES_HOME/skills" ] && [ "$(ls -d "$RULES_HOME/skills/"*/ 2>/dev/null)" ]; then
    OPENCODE_HAS_SOURCE_SKILLS=true
fi

if $OPENCODE_HAS_SOURCE_SKILLS; then
    if [ -f "$OPENCODE_SKILLS_MF" ]; then
        OPENCODE_SKILLS_OK=true
        OPENCODE_SKILLS_CHECKED=0
        while IFS= read -r opencode_skill_name; do
            [ -z "$opencode_skill_name" ] && continue
            OPENCODE_SKILLS_CHECKED=$((OPENCODE_SKILLS_CHECKED + 1))
            opencode_skill_dir="$PROJECT_DIR/.opencode/skills/$opencode_skill_name"
            if [ -d "$opencode_skill_dir" ] && [ "$(ls -A "$opencode_skill_dir" 2>/dev/null)" ]; then
                pass "OpenCode skill '$opencode_skill_name' deployed"
            else
                fail "OpenCode skill '$opencode_skill_name' listed in manifest but missing or empty"
                OPENCODE_SKILLS_OK=false
            fi
        done < "$OPENCODE_SKILLS_MF"
        if [ "$OPENCODE_SKILLS_CHECKED" -eq 0 ]; then
            fail "OpenCode skills manifest exists but is empty. Run agent-sync."
        elif $OPENCODE_SKILLS_OK; then
            pass "All $OPENCODE_SKILLS_CHECKED OpenCode skills are deployed"
        fi
    else
        fail "Rules repo has skills but OpenCode skills manifest not found. Run agent-sync."
    fi
else
    pass "No skills in rules repo (OpenCode skills: nothing to validate)"
fi

# --- 18. OpenCode / CC / Cursor skills consistency ---

echo ""
echo "[$((OPENCODE_BASE + 3))/$TOTAL_CHECKS] OpenCode/CC/Cursor skills consistency"

# Same defensive re-declaration pattern used in the Codex block: this
# sub-block can run with CC_MODE=off + OpenCode=native, so CURSOR_SKILLS_MF
# / CC_SKILLS_MF may be unset under set -u.
OPENCODE_CHECK_CURSOR_SKILLS_MF="$PROJECT_DIR/.cursor/skills/.agent-sync-skills-manifest"
OPENCODE_CHECK_CC_SKILLS_MF="$PROJECT_DIR/.claude/skills/.agent-sync-skills-manifest"
if [ -f "$OPENCODE_SKILLS_MF" ] && [ -f "$OPENCODE_CHECK_CURSOR_SKILLS_MF" ]; then
    OPENCODE_CHECK_CURSOR_SET=$(sort "$OPENCODE_CHECK_CURSOR_SKILLS_MF" | tr '\n' ',')
    OPENCODE_CHECK_OPENCODE_SET=$(sort "$OPENCODE_SKILLS_MF" | tr '\n' ',')
    if [ "$OPENCODE_CHECK_CURSOR_SET" = "$OPENCODE_CHECK_OPENCODE_SET" ]; then
        pass "OpenCode and Cursor skill sets match"
    else
        warn "OpenCode and Cursor skill sets differ — check agent-sync output"
    fi
fi
if [ -f "$OPENCODE_SKILLS_MF" ] && [ -f "$OPENCODE_CHECK_CC_SKILLS_MF" ]; then
    OPENCODE_CHECK_CC_SET=$(sort "$OPENCODE_CHECK_CC_SKILLS_MF" | tr '\n' ',')
    OPENCODE_CHECK_OPENCODE_SET_FOR_CC=$(sort "$OPENCODE_SKILLS_MF" | tr '\n' ',')
    if [ "$OPENCODE_CHECK_CC_SET" = "$OPENCODE_CHECK_OPENCODE_SET_FOR_CC" ]; then
        pass "OpenCode and CC skill sets match"
    else
        warn "OpenCode and CC skill sets differ — check agent-sync output"
    fi
fi

fi  # end OPENCODE_MODE = native

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
