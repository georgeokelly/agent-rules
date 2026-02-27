#!/bin/bash
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
#   7. .vscode/settings.json validity (if exists)

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

# --- 1. Codex AGENTS.md size ---

echo ""
echo "[1/7] Codex AGENTS.md size limit"

if [ -f "$PROJECT_DIR/AGENTS.md" ]; then
    SIZE=$(wc -c < "$PROJECT_DIR/AGENTS.md" | tr -d ' ')
    if [ "$SIZE" -gt 32768 ]; then
        fail "AGENTS.md is $SIZE bytes (> 32KiB). Codex will silently truncate!"
    else
        PERCENT=$((SIZE * 100 / 32768))
        pass "AGENTS.md is $SIZE bytes (${PERCENT}% of 32KiB limit)"
    fi
else
    fail "AGENTS.md not found"
fi

# --- 2. Cursor frontmatter lint ---

echo ""
echo "[2/7] Cursor .mdc frontmatter validation"

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
echo "[3/7] Cursor dual-write conflict check"

if [ -f "$PROJECT_DIR/.cursorrules" ] && [ -d "$PROJECT_DIR/.cursor/rules" ]; then
    warn ".cursorrules AND .cursor/rules/ both exist. .mdc files may silently override .cursorrules. Remove one."
else
    pass "No dual-write conflict detected"
fi

# --- 4. Staleness check ---

echo ""
echo "[4/7] Staleness detection"

if [ -f "$HASH_FILE" ]; then
    STORED_HASH="$(cat "$HASH_FILE" 2>/dev/null || echo "none")"
    STORED_RULES_HASH="${STORED_HASH%%:*}"

    if [ -d "$RULES_HOME/.git" ]; then
        CURRENT_RULES_HASH="$(git -C "$RULES_HOME" rev-parse HEAD 2>/dev/null || echo "unknown")"
    else
        HASH_CMD="shasum"
        command -v shasum &>/dev/null || HASH_CMD="sha1sum"
        command -v $HASH_CMD &>/dev/null || HASH_CMD="md5sum"
        CURRENT_RULES_HASH="$(find "$RULES_HOME" \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.css' -o -name '*.sh' \) -type f -exec $HASH_CMD {} + 2>/dev/null | $HASH_CMD | awk '{print $1}')"
    fi

    if [ "$CURRENT_RULES_HASH" = "$STORED_RULES_HASH" ]; then
        pass "Rules repo is up to date with last sync"
    else
        warn "Rules repo has been updated since last sync. Run agent-sync."
    fi
else
    warn "No sync hash found. Has agent-sync been run?"
fi

# --- 5. File existence ---

echo ""
echo "[5/7] Generated file existence"

EXPECTED_FILES=("CLAUDE.md" "AGENTS.md")
for f in "${EXPECTED_FILES[@]}"; do
    if [ -f "$PROJECT_DIR/$f" ]; then
        pass "$f exists"
    else
        fail "$f not found"
    fi
done

if [ -d "$PROJECT_DIR/.cursor/rules" ] && [ "$(ls "$PROJECT_DIR/.cursor/rules/"*.mdc 2>/dev/null | wc -l)" -gt 0 ]; then
    pass ".cursor/rules/ contains .mdc files"
else
    fail ".cursor/rules/ is empty or missing"
fi

# --- 6. Core .mdc semantic validation ---

echo ""
echo "[6/7] Core .mdc alwaysApply validation"

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

# --- 7. .vscode/settings.json validity ---

echo ""
echo "[7/7] .vscode/settings.json validation"

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
