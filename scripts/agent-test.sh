#!/usr/bin/env bash
# agent-test.sh — E2E tests for the agent-sync + agent-check pipeline
# Usage: agent-test.sh [-h|--help]
#
# Validates the full sync/check/mode-switching/cleanup lifecycle
# in temporary project directories. Cleans up on exit.
#
# Exit code: 0 = all passed, 1 = at least one failure.

set -uo pipefail

case "${1:-}" in
    -h|--help)
        cat <<'EOF'
agent-test — E2E tests for agent-sync + agent-check pipeline

USAGE
    agent-test [-h|--help]

ENVIRONMENT
    AGENT_RULES_HOME   Override rules repo path (default: auto-detected)

Tests run in temporary directories and clean up on exit.
EOF
        exit 0
        ;;
esac

# --- Setup ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
export AGENT_RULES_HOME="$RULES_HOME"

AGENT_SYNC="$SCRIPT_DIR/agent-sync.sh"
AGENT_CHECK="$SCRIPT_DIR/agent-check.sh"

if [ ! -f "$AGENT_SYNC" ] || [ ! -f "$AGENT_CHECK" ]; then
    printf 'ERROR: agent-sync.sh or agent-check.sh not found in %s\n' "$SCRIPT_DIR" >&2
    exit 1
fi
if [ ! -d "$RULES_HOME/core" ] || [ ! -d "$RULES_HOME/packs" ]; then
    printf 'ERROR: Rules repo missing core/ or packs/ at %s\n' "$RULES_HOME" >&2
    exit 1
fi

PASS=0 FAIL=0

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

assert() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

assert_output_match() {
    local desc="$1" pattern="$2" output="$3"
    if printf '%s' "$output" | grep -qE "$pattern"; then
        pass "$desc"
    else
        fail "$desc (expected pattern: $pattern)"
    fi
}

CLEANUP_DIRS=()
cleanup() {
    local d
    for d in ${CLEANUP_DIRS[@]+"${CLEANUP_DIRS[@]}"}; do
        [ -n "${d:-}" ] && rm -rf "$d" 2>/dev/null || true
    done
}
trap cleanup EXIT

new_project() {
    local dir
    dir="$(mktemp -d)" || { echo "ERROR: mktemp failed" >&2; exit 1; }
    CLEANUP_DIRS+=("$dir")
    printf '%s' "$dir"
}

write_overlay() {
    local dir="$1" cc_mode="${2:-dual}" codex_mode="${3:-native}"
    cat > "$dir/.agent-local.md" <<EOF
# Project Overlay

## Project Overview

**Project**: test-project — E2E test fixture
**Boundary**: General-purpose

**Tech Stack**: Python, Shell
**Build System**: N/A
**Target Platform**: Linux
**Packs**: python, shell, markdown

**CC Mode**: $cc_mode
**Codex Mode**: $codex_mode

## Build & Test Commands

\`\`\`bash
echo "test"
\`\`\`
EOF
}

echo "agent-test — E2E tests for agent-sync + agent-check"
echo "Rules repo: $RULES_HOME"
echo "================================================"

# ===== T1: Full sync with defaults (CC=dual, Codex=native) =====

echo ""
echo "=== T1: Full sync (CC=dual, Codex=native) ==="
P1="$(new_project)"
write_overlay "$P1"
"$AGENT_SYNC" "$P1" >/dev/null 2>&1 || true

assert ".cursor/rules/ exists"         test -d "$P1/.cursor/rules"
assert ".cursor/rules/ has .mdc"       test -n "$(ls "$P1/.cursor/rules/"*.mdc 2>/dev/null)"
assert ".claude/rules/ exists"         test -d "$P1/.claude/rules"
assert ".claude/rules/ has .md"        test -n "$(ls "$P1/.claude/rules/"*.md 2>/dev/null)"
assert ".claude/skills/ exists"        test -d "$P1/.claude/skills"
assert ".claude/commands/ exists"      test -d "$P1/.claude/commands"
assert "CLAUDE.md exists"              test -f "$P1/.agent-rules/CLAUDE.md"
assert "AGENTS.md exists"              test -f "$P1/.agent-rules/AGENTS.md"
assert ".codex/config.toml exists"     test -f "$P1/.codex/config.toml"
assert ".agents/skills/ exists"        test -d "$P1/.agents/skills"
assert ".cursor/skills/ exists"        test -d "$P1/.cursor/skills"
assert "No root CLAUDE.md"             test ! -f "$P1/CLAUDE.md"
assert "No root AGENTS.md"             test ! -f "$P1/AGENTS.md"
assert ".agent-sync-hash exists"       test -f "$P1/.agent-sync-hash"

# ===== T2: Staleness skip (re-run should be instant) =====

echo ""
echo "=== T2: Staleness skip ==="
# First re-sync stabilizes the hash (reviewer-models.conf is deployed after
# the initial hash computation, causing a one-time hash mismatch on re-run).
"$AGENT_SYNC" "$P1" >/dev/null 2>&1 || true
T2_OUT=$("$AGENT_SYNC" "$P1" 2>&1 || true)
assert_output_match "Reports up to date" "[Uu]p to date" "$T2_OUT"

# ===== T3: agent-check passes on default sync =====

echo ""
echo "=== T3: agent-check passes ==="
assert "agent-check exit 0" "$AGENT_CHECK" "$P1"

# ===== T4: CC Mode=off → .claude/ cleaned =====

echo ""
echo "=== T4: CC Mode=off (reconcile removes .claude/) ==="
write_overlay "$P1" "off" "native"
"$AGENT_SYNC" "$P1" >/dev/null 2>&1 || true

assert ".claude/rules/ gone"            test ! -d "$P1/.claude/rules"
assert ".codex/config.toml preserved"   test -f "$P1/.codex/config.toml"
assert "AGENTS.md preserved"            test -f "$P1/.agent-rules/AGENTS.md"
assert "agent-check passes"             "$AGENT_CHECK" "$P1"

# ===== T5: Codex Mode=off → .codex/ + AGENTS.md cleaned =====

echo ""
echo "=== T5: Codex Mode=off (reconcile removes .codex/) ==="
write_overlay "$P1" "dual" "off"
"$AGENT_SYNC" "$P1" >/dev/null 2>&1 || true

assert ".codex/config.toml gone" test ! -f "$P1/.codex/config.toml"
assert ".agents/ gone"           test ! -d "$P1/.agents/skills"
assert "AGENTS.md gone"          test ! -f "$P1/.agent-rules/AGENTS.md"
assert "CLAUDE.md preserved"     test -f "$P1/.agent-rules/CLAUDE.md"
assert ".claude/rules/ restored" test -d "$P1/.claude/rules"
assert "agent-check passes"      "$AGENT_CHECK" "$P1"

# ===== T6: Codex Mode=legacy → AGENTS.md but no native files =====

echo ""
echo "=== T6: Codex Mode=legacy ==="
write_overlay "$P1" "dual" "legacy"
"$AGENT_SYNC" "$P1" >/dev/null 2>&1 || true

assert "No .codex/config.toml" test ! -f "$P1/.codex/config.toml"
assert "No .agents/skills/"    test ! -d "$P1/.agents/skills"
assert "AGENTS.md exists"      test -f "$P1/.agent-rules/AGENTS.md"
assert "CLAUDE.md exists"      test -f "$P1/.agent-rules/CLAUDE.md"
assert "agent-check passes"    "$AGENT_CHECK" "$P1"

# ===== T7: CC=native + Codex=off → no legacy files at all =====

echo ""
echo "=== T7: CC=native + Codex=off (no legacy) ==="
P7="$(new_project)"
write_overlay "$P7" "native" "off"
"$AGENT_SYNC" "$P7" >/dev/null 2>&1 || true

assert ".claude/rules/ exists"  test -d "$P7/.claude/rules"
assert "No CLAUDE.md"           test ! -f "$P7/.agent-rules/CLAUDE.md"
assert "No AGENTS.md"           test ! -f "$P7/.agent-rules/AGENTS.md"
assert "No .codex/"             test ! -d "$P7/.codex"
assert "agent-check passes"     "$AGENT_CHECK" "$P7"

# ===== T8: Sub-repo overlay =====

echo ""
echo "=== T8: Sub-repo overlay ==="
P8="$(new_project)"
write_overlay "$P8" "dual" "native"
mkdir -p "$P8/libs/core"
printf '# Sub-repo overlay for libs/core\n' > "$P8/libs/core/.agent-local.md"
"$AGENT_SYNC" "$P8" >/dev/null 2>&1 || true

assert "Sub-repo CLAUDE.md"        test -f "$P8/libs/core/CLAUDE.md"
assert "Sub-repo AGENTS.md"        test -f "$P8/libs/core/AGENTS.md"
assert "Sub-repo Cursor .mdc"      test -f "$P8/.cursor/rules/libs-core-overlay.mdc"
assert "Sub-repo CC overlay .md"   test -f "$P8/.claude/rules/libs-core-overlay.md"
assert "agent-check passes"        "$AGENT_CHECK" "$P8"

# T8b: Ghost cleanup after removing sub-repo overlay
echo ""
echo "=== T8b: Sub-repo ghost cleanup ==="
rm "$P8/libs/core/.agent-local.md"
rm -f "$P8/.agent-sync-hash"
"$AGENT_SYNC" "$P8" >/dev/null 2>&1 || true

assert "Ghost CLAUDE.md removed"      test ! -f "$P8/libs/core/CLAUDE.md"
assert "Ghost .mdc removed"           test ! -f "$P8/.cursor/rules/libs-core-overlay.mdc"
assert "Ghost CC overlay removed"     test ! -f "$P8/.claude/rules/libs-core-overlay.md"

# ===== T9: Clean removes everything =====

echo ""
echo "=== T9: agent-sync clean ==="
P9="$(new_project)"
write_overlay "$P9" "dual" "native"
"$AGENT_SYNC" "$P9" >/dev/null 2>&1 || true
"$AGENT_SYNC" clean "$P9" >/dev/null 2>&1 || true

assert ".cursor/rules/ gone"     test ! -d "$P9/.cursor/rules"
assert ".claude/ gone"           test ! -d "$P9/.claude"
assert ".codex/ gone"            test ! -d "$P9/.codex"
assert ".agent-rules/ gone"      test ! -d "$P9/.agent-rules"
assert ".agent-sync-hash gone"   test ! -f "$P9/.agent-sync-hash"

# ===== T10: 32KiB warning =====

echo ""
echo "=== T10: AGENTS.md 32KiB warning ==="
P10="$(new_project)"
write_overlay "$P10" "off" "native"
# Pad overlay to push assembled AGENTS.md past 32KiB
python3 -c "print('x' * 25000)" >> "$P10/.agent-local.md"
T10_OUT=$("$AGENT_SYNC" "$P10" 2>&1 || true)
assert_output_match "32KiB warning triggered" "WARNING.*32KiB" "$T10_OUT"

# ===== Summary =====

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf 'Results: %d passed, %d failed (%d total)\n' "$PASS" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
    echo "STATUS: FAILED"
    exit 1
else
    echo "STATUS: ALL PASSED"
    exit 0
fi
