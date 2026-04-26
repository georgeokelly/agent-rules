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
    AGENT_TOOLKIT_HOME   Override rules repo path (default: auto-detected)

Tests run in temporary directories and clean up on exit.
EOF
        exit 0
        ;;
esac

# --- Setup ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
export AGENT_TOOLKIT_HOME="$RULES_HOME"

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
    local dir="$1" cc_mode="${2:-native}" codex_mode="${3:-native}" opencode_mode="${4:-native}"
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
**OpenCode Mode**: $opencode_mode

## Build & Test Commands

\`\`\`bash
echo "test"
\`\`\`
EOF
}

echo "agent-test — E2E tests for agent-sync + agent-check"
echo "Rules repo: $RULES_HOME"
echo "================================================"

# ===== T1: Full sync with defaults (CC=native, Codex=native) =====
# HIST-004: default CC Mode flipped from 'dual' to 'native'. CLAUDE.md is no
# longer generated on any sync path — only AGENTS.md remains as the legacy
# monolithic artifact (for Codex).

echo ""
echo "=== T1: Full sync (CC=native, Codex=native) ==="
P1="$(new_project)"
write_overlay "$P1"
"$AGENT_SYNC" "$P1" >/dev/null 2>&1 || true

assert ".cursor/rules/ exists"         test -d "$P1/.cursor/rules"
assert ".cursor/rules/ has .mdc"       test -n "$(ls "$P1/.cursor/rules/"*.mdc 2>/dev/null)"
assert ".claude/rules/ exists"         test -d "$P1/.claude/rules"
assert ".claude/rules/ has .md"        test -n "$(ls "$P1/.claude/rules/"*.md 2>/dev/null)"
assert ".claude/skills/ exists"        test -d "$P1/.claude/skills"
assert "No CLAUDE.md (HIST-004)"       test ! -f "$P1/.agent-rules/CLAUDE.md"
# HIST-007: root AGENTS.override.md is the new Codex entry point;
# .agent-rules/ should be wiped on every sync.
assert "AGENTS.override.md exists"     test -f "$P1/AGENTS.override.md"
assert "No legacy .agent-rules/AGENTS.md"   test ! -f "$P1/.agent-rules/AGENTS.md"
assert "No legacy .agent-rules/ dir"        test ! -d "$P1/.agent-rules"
assert ".codex/config.toml exists"     test -f "$P1/.codex/config.toml"
assert ".codex/config.toml has child_agents_md"   grep -q 'child_agents_md = true' "$P1/.codex/config.toml"
assert ".codex/config.toml no fallback_filenames" bash -c "! grep -q 'project_doc_fallback_filenames' '$P1/.codex/config.toml'"
assert ".agents/skills/ exists"        test -d "$P1/.agents/skills"
assert ".cursor/skills/ exists"        test -d "$P1/.cursor/skills"
assert "No root CLAUDE.md"             test ! -f "$P1/CLAUDE.md"
assert "No root AGENTS.md"             test ! -f "$P1/AGENTS.md"
assert ".agent-sync-hash exists"       test -f "$P1/.agent-sync-hash"

# Per-skill deployment (guards against silent exclusion regressions — HIST-003).
# simple-review and pre-commit are cross-tool replacements for the decommissioned
# commands/ subsystem; if either goes missing on default sync the refactor is broken.
# HIST-005: default prefix 'gla-' — bare names must not appear, prefixed names must.
assert "Cursor skill gla-simple-review"    test -d "$P1/.cursor/skills/gla-simple-review"
assert "Cursor skill gla-pre-commit"       test -d "$P1/.cursor/skills/gla-pre-commit"
assert "CC skill gla-simple-review"        test -d "$P1/.claude/skills/gla-simple-review"
assert "CC skill gla-pre-commit"           test -d "$P1/.claude/skills/gla-pre-commit"
assert "Codex skill gla-simple-review"     test -d "$P1/.agents/skills/gla-simple-review"
assert "Codex skill gla-pre-commit"        test -d "$P1/.agents/skills/gla-pre-commit"
assert "No bare Cursor skill pre-commit"   test ! -d "$P1/.cursor/skills/pre-commit"
assert "No bare CC skill pre-commit"       test ! -d "$P1/.claude/skills/pre-commit"
assert "No bare Codex skill pre-commit"    test ! -d "$P1/.agents/skills/pre-commit"

# Orphan regression guard (HIST-003): pre-refactor 30-review-criteria.mdc must
# not be generated on a fresh sync.
assert "No 30-review-criteria.mdc"     test ! -f "$P1/.cursor/rules/30-review-criteria.mdc"

# CC/Cursor consistency regression guard: gen-cursor deploys all packs, gen-claude
# filters — CC_COUNT must be <= CURSOR_COUNT and the overlay (3 packs) should
# strictly exceed CC output. agent-check must not emit "unexpected divergence".
T1_CHECK_OUT=$("$AGENT_CHECK" "$P1" 2>&1 || true)
# Tighten the regex so an accidental text drift ("CC rules configured" etc.)
# can't silently satisfy the check — require literal "CC rules (N) <= Cursor
# rules (M)" with both counts present.
assert_output_match "agent-check: CC <= Cursor accepted" 'CC rules \([0-9]+\) (<=|=) Cursor rules \([0-9]+\)' "$T1_CHECK_OUT"
if printf '%s' "$T1_CHECK_OUT" | grep -q 'unexpected divergence'; then
    fail "agent-check emitted 'unexpected divergence' on a fresh sync (regression of HIST-003 P0)"
else
    pass "agent-check: no 'unexpected divergence' on fresh sync"
fi

# ===== T2: Staleness skip (re-run should be instant) =====

echo ""
echo "=== T2: Staleness skip ==="
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
assert "AGENTS.override.md preserved"   test -f "$P1/AGENTS.override.md"
assert "agent-check passes"             "$AGENT_CHECK" "$P1"

# ===== T5: Codex Mode=off → .codex/ + AGENTS.md cleaned =====
# Note: 'dual' overlay value is intentionally used here to verify that the
# deprecation alias folds to 'native' without failing the rest of the sync
# (covered more explicitly in T16).

echo ""
echo "=== T5: Codex Mode=off (reconcile removes .codex/) ==="
write_overlay "$P1" "dual" "off"
"$AGENT_SYNC" "$P1" >/dev/null 2>&1 || true

assert ".codex/config.toml gone" test ! -f "$P1/.codex/config.toml"
assert ".agents/ gone"           test ! -d "$P1/.agents/skills"
assert "AGENTS.override.md gone" test ! -f "$P1/AGENTS.override.md"
assert "No legacy AGENTS.md"     test ! -f "$P1/.agent-rules/AGENTS.md"
assert "No CLAUDE.md (HIST-004)" test ! -f "$P1/.agent-rules/CLAUDE.md"
assert ".claude/rules/ restored" test -d "$P1/.claude/rules"
assert "agent-check passes"      "$AGENT_CHECK" "$P1"

# ===== T6: Codex Mode=legacy → AGENTS.md but no native files =====

echo ""
echo "=== T6: Codex Mode=legacy ==="
write_overlay "$P1" "native" "legacy"
"$AGENT_SYNC" "$P1" >/dev/null 2>&1 || true

assert "No .codex/config.toml" test ! -f "$P1/.codex/config.toml"
assert "No .agents/skills/"    test ! -d "$P1/.agents/skills"
# HIST-007: Codex Mode=legacy still produces the AGENTS body, just at the
# new root location instead of .agent-rules/.
assert "AGENTS.override.md exists" test -f "$P1/AGENTS.override.md"
assert "No legacy AGENTS.md"   test ! -f "$P1/.agent-rules/AGENTS.md"
assert "No CLAUDE.md (HIST-004)" test ! -f "$P1/.agent-rules/CLAUDE.md"
assert "agent-check passes"    "$AGENT_CHECK" "$P1"

# ===== T7: CC=native + Codex=off → no legacy files at all =====

echo ""
echo "=== T7: CC=native + Codex=off (no legacy) ==="
P7="$(new_project)"
write_overlay "$P7" "native" "off"
"$AGENT_SYNC" "$P7" >/dev/null 2>&1 || true

assert ".claude/rules/ exists"  test -d "$P7/.claude/rules"
assert "No CLAUDE.md"           test ! -f "$P7/.agent-rules/CLAUDE.md"
assert "No legacy AGENTS.md"    test ! -f "$P7/.agent-rules/AGENTS.md"
assert "No root AGENTS.override.md" test ! -f "$P7/AGENTS.override.md"
assert "No .codex/"             test ! -d "$P7/.codex"
assert "agent-check passes"     "$AGENT_CHECK" "$P7"

# ===== T8: Sub-repo overlay =====

echo ""
echo "=== T8: Sub-repo overlay ==="
P8="$(new_project)"
write_overlay "$P8" "native" "native"
mkdir -p "$P8/libs/core"
printf '# Sub-repo overlay for libs/core\n' > "$P8/libs/core/.agent-local.md"
"$AGENT_SYNC" "$P8" >/dev/null 2>&1 || true

# HIST-004: sub-repo CLAUDE.md is no longer produced.
# HIST-007: sub-repo overlay file renamed to AGENTS.override.md so Cursor
# (which auto-injects nested AGENTS.md but not AGENTS.override.md) does
# not duplicate the same content already arriving via the
# .cursor/rules/libs-core-overlay.mdc path.
assert "No sub-repo CLAUDE.md (HIST-004)" test ! -f "$P8/libs/core/CLAUDE.md"
assert "No sub-repo AGENTS.md (HIST-007)" test ! -f "$P8/libs/core/AGENTS.md"
assert "Sub-repo AGENTS.override.md"      test -f "$P8/libs/core/AGENTS.override.md"
assert "Sub-repo Cursor .mdc"      test -f "$P8/.cursor/rules/libs-core-overlay.mdc"
assert "Sub-repo CC overlay .md"   test -f "$P8/.claude/rules/libs-core-overlay.md"
assert "agent-check passes"        "$AGENT_CHECK" "$P8"

# T8b: Ghost cleanup after removing sub-repo overlay
echo ""
echo "=== T8b: Sub-repo ghost cleanup ==="
rm "$P8/libs/core/.agent-local.md"
rm -f "$P8/.agent-sync-hash"
"$AGENT_SYNC" "$P8" >/dev/null 2>&1 || true

# Ghost cleanup wipes the new override.md target plus pre-HIST-007
# AGENTS.md and pre-HIST-004 CLAUDE.md (upgrade compat).
assert "Ghost AGENTS.override.md removed" test ! -f "$P8/libs/core/AGENTS.override.md"
assert "Ghost legacy AGENTS.md removed"   test ! -f "$P8/libs/core/AGENTS.md"
assert "Ghost .mdc removed"           test ! -f "$P8/.cursor/rules/libs-core-overlay.mdc"
assert "Ghost CC overlay removed"     test ! -f "$P8/.claude/rules/libs-core-overlay.md"

# ===== T9: Clean removes everything =====

echo ""
echo "=== T9: agent-sync clean ==="
P9="$(new_project)"
write_overlay "$P9" "native" "native"
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

# ===== T11: Explicit cc-rules / cc-skills subcommands (HIST-003) =====
# Guards the new dispatch cases against silent wiring regressions in agent-sync.sh.
# Each subcommand must deploy its own target only, not the full CC tree.

echo ""
echo "=== T11: Explicit cc-rules / cc-skills subcommands ==="
P11="$(new_project)"
write_overlay "$P11"
"$AGENT_SYNC" cc-rules "$P11" >/dev/null 2>&1 || true

assert "cc-rules produced .claude/rules/"    test -d "$P11/.claude/rules"
assert "cc-rules wrote some *.md rules"      test -n "$(ls "$P11/.claude/rules/"*.md 2>/dev/null)"
assert "cc-rules did not touch .claude/skills/" test ! -d "$P11/.claude/skills"
assert "cc-rules did not touch .cursor/rules/"  test ! -d "$P11/.cursor/rules"

"$AGENT_SYNC" cc-skills "$P11" >/dev/null 2>&1 || true

assert "cc-skills produced .claude/skills/"  test -d "$P11/.claude/skills"
assert "cc-skills deployed gla-simple-review"    test -d "$P11/.claude/skills/gla-simple-review"
assert "cc-skills deployed gla-pre-commit"       test -d "$P11/.claude/skills/gla-pre-commit"
assert "cc-skills still no .cursor/rules/"   test ! -d "$P11/.cursor/rules"

# ===== T12: Legacy .claude/commands/ stamp-gated cleanup (HIST-003) =====
# Simulates a pre-refactor deployment state by planting a commands/ directory
# with the historical agent-sync stamp, then runs a fresh sync and confirms the
# stamp-gated cleanup fires. Guards against a future regression that drops the
# cleanup path and lets `rmdir .claude` silently fail in `agent-sync clean`.

echo ""
echo "=== T12: Legacy .claude/commands/ stamp-gated cleanup ==="
P12="$(new_project)"
write_overlay "$P12"
mkdir -p "$P12/.claude/commands"
printf 'pre-commit.md\nreview.md\n' > "$P12/.claude/commands/.agent-sync-commands-manifest"
printf '# Legacy stub\n' > "$P12/.claude/commands/pre-commit.md"

"$AGENT_SYNC" "$P12" >/dev/null 2>&1 || true

assert "Legacy .claude/commands/ removed (stamp-gated)" test ! -d "$P12/.claude/commands"
assert ".claude/rules/ still present"                   test -d "$P12/.claude/rules"

# Inverse: user-authored .claude/commands/ (no stamp) must NOT be touched.
P12b="$(new_project)"
write_overlay "$P12b"
mkdir -p "$P12b/.claude/commands"
printf '# User command\n' > "$P12b/.claude/commands/my-cmd.md"

"$AGENT_SYNC" "$P12b" >/dev/null 2>&1 || true

assert "User-authored .claude/commands/ preserved"      test -d "$P12b/.claude/commands"
assert "User file under commands/ preserved"           test -f "$P12b/.claude/commands/my-cmd.md"

# Clean path must also remove the stamped legacy directory (agent-sync clean).
P12c="$(new_project)"
write_overlay "$P12c"
"$AGENT_SYNC" "$P12c" >/dev/null 2>&1 || true
mkdir -p "$P12c/.claude/commands"
printf 'stale.md\n' > "$P12c/.claude/commands/.agent-sync-commands-manifest"
printf '# stale\n' > "$P12c/.claude/commands/stale.md"
"$AGENT_SYNC" clean "$P12c" >/dev/null 2>&1 || true

assert "Clean removed legacy commands/"                 test ! -d "$P12c/.claude/commands"
assert "Clean removed .claude/ entirely"                test ! -d "$P12c/.claude"

# Mixed-ownership scenario (GPT-5.4 M1 regression guard):
# Pre-refactor agent-sync deployed legacy.md AND the user later added custom.md
# to the same .claude/commands/. The cleanup must remove manifest + legacy.md
# only, leaving custom.md and the directory in place.
P12d="$(new_project)"
write_overlay "$P12d"
"$AGENT_SYNC" "$P12d" >/dev/null 2>&1 || true   # baseline — no commands/
mkdir -p "$P12d/.claude/commands"
printf 'legacy.md\n' > "$P12d/.claude/commands/.agent-sync-commands-manifest"
printf '# legacy\n' > "$P12d/.claude/commands/legacy.md"
printf '# user-maintained\n' > "$P12d/.claude/commands/custom.md"
rm -f "$P12d/.agent-sync-hash"
"$AGENT_SYNC" "$P12d" >/dev/null 2>&1 || true

assert "Mixed-ownership: legacy.md removed"      test ! -f "$P12d/.claude/commands/legacy.md"
assert "Mixed-ownership: manifest removed"       test ! -f "$P12d/.claude/commands/.agent-sync-commands-manifest"
assert "Mixed-ownership: user file preserved"    test -f "$P12d/.claude/commands/custom.md"
assert "Mixed-ownership: directory preserved"    test -d "$P12d/.claude/commands"

# ===== T13: Orphan 30-review-criteria.mdc one-shot cleanup (HIST-003) =====
# Simulates a pre-refactor Cursor rule that must disappear on the next sync.

echo ""
echo "=== T13: Orphan .cursor/rules/30-review-criteria.mdc cleanup ==="
P13="$(new_project)"
write_overlay "$P13"
"$AGENT_SYNC" "$P13" >/dev/null 2>&1 || true
printf -- '---\ndescription: stale\n---\n# stale\n' \
    > "$P13/.cursor/rules/30-review-criteria.mdc"
rm -f "$P13/.agent-sync-hash"
"$AGENT_SYNC" "$P13" >/dev/null 2>&1 || true

assert "Orphan 30-review-criteria.mdc removed" test ! -f "$P13/.cursor/rules/30-review-criteria.mdc"

# ===== T14: cc / cc-rules / cc-skills fire legacy-commands cleanup (HIST-003) =====
# GLM m-2: opportunistic cleanup must fire on targeted subcommands, not only
# on full sync, so that `agent-sync cc-rules <project>` after a partial
# migration still scrubs stamp-marked .claude/commands/.

echo ""
echo "=== T14: cc-subcommands fire legacy-commands cleanup ==="
for sub in cc cc-rules cc-skills; do
    P14="$(new_project)"
    write_overlay "$P14"
    mkdir -p "$P14/.claude/commands"
    printf 'legacy.md\n' > "$P14/.claude/commands/.agent-sync-commands-manifest"
    printf '# legacy\n' > "$P14/.claude/commands/legacy.md"
    "$AGENT_SYNC" "$sub" "$P14" >/dev/null 2>&1 || true
    assert "'$sub' cleaned legacy commands/"           test ! -d "$P14/.claude/commands"
done

# ===== T15: .cursor/.reviewer-models-agent-sync stamp orphan cleanup (HIST-003) =====
# GLM m-3: the pre-refactor stamp is a pure agent-sync artifact with no
# user-facing value. It must be removed on `agent-sync clean`, even though
# the .reviewer-models.conf itself is intentionally user-managed (README §9).

echo ""
echo "=== T15: .cursor/.reviewer-models-agent-sync stamp orphan cleanup ==="
P15="$(new_project)"
write_overlay "$P15"
"$AGENT_SYNC" "$P15" >/dev/null 2>&1 || true
printf 'legacy stamp\n' > "$P15/.cursor/.reviewer-models-agent-sync"
"$AGENT_SYNC" clean "$P15" >/dev/null 2>&1 || true

assert "Clean removed reviewer-models stamp"   test ! -f "$P15/.cursor/.reviewer-models-agent-sync"

# ===== T16: HIST-004 — CC Mode 'dual' is a deprecated alias for 'native' =====
# Overlay with '**CC Mode**: dual' must (a) emit a DEPRECATED warning,
# (b) fold silently to native, (c) NOT produce .agent-rules/CLAUDE.md.

echo ""
echo "=== T16: CC Mode 'dual' deprecated alias (HIST-004) ==="
P16="$(new_project)"
write_overlay "$P16" "dual" "native"
T16_OUT=$("$AGENT_SYNC" "$P16" 2>&1 || true)

assert_output_match "DEPRECATED warning printed" "DEPRECATED: CC Mode 'dual'" "$T16_OUT"
assert "dual alias did not emit CLAUDE.md"  test ! -f "$P16/.agent-rules/CLAUDE.md"
# HIST-007: AGENTS body now lives at root AGENTS.override.md.
assert "AGENTS.override.md still produced"  test -f "$P16/AGENTS.override.md"
assert ".claude/rules/ produced"            test -d "$P16/.claude/rules"
assert "agent-check passes"                 "$AGENT_CHECK" "$P16"

# ===== T17: HIST-004 — legacy .agent-rules/CLAUDE.md + sub-repo CLAUDE.md =====
# Simulate a pre-HIST-004 project state: root .agent-rules/CLAUDE.md and a
# sub-repo CLAUDE.md both exist. A fresh sync must sweep them without
# requiring a manual `agent-sync clean`.

echo ""
echo "=== T17: Legacy CLAUDE.md upgrade cleanup (HIST-004) ==="
P17="$(new_project)"
write_overlay "$P17"
"$AGENT_SYNC" "$P17" >/dev/null 2>&1 || true
# Plant legacy CLAUDE.md artifacts.
mkdir -p "$P17/.agent-rules"
printf '<!-- Auto-generated by agent-sync. Do not edit manually. -->\n# legacy root\n' \
    > "$P17/.agent-rules/CLAUDE.md"
mkdir -p "$P17/libs/core"
printf '# Sub-repo overlay\n' > "$P17/libs/core/.agent-local.md"
printf '<!-- Auto-generated by agent-sync (sub-repo overlay only). -->\n# legacy sub\n' \
    > "$P17/libs/core/CLAUDE.md"
rm -f "$P17/.agent-sync-hash"
"$AGENT_SYNC" "$P17" >/dev/null 2>&1 || true

assert "Legacy root CLAUDE.md swept"    test ! -f "$P17/.agent-rules/CLAUDE.md"
assert "Legacy sub-repo CLAUDE.md swept" test ! -f "$P17/libs/core/CLAUDE.md"
# HIST-007: post-cleanup, AGENTS body lives at root, not .agent-rules/.
assert "Root AGENTS.override.md produced"     test -f "$P17/AGENTS.override.md"
assert "No legacy .agent-rules/AGENTS.md"     test ! -f "$P17/.agent-rules/AGENTS.md"
assert "Sub-repo AGENTS.override.md produced" test -f "$P17/libs/core/AGENTS.override.md"
assert "No sub-repo legacy AGENTS.md"         test ! -f "$P17/libs/core/AGENTS.md"

# ===== T18: HIST-004 — 'agent-sync claude' subcommand rejected =====
# The removed subcommand must print a loud HIST-004 error and exit non-zero
# so external scripts relying on it fail fast instead of silently cd-ing
# into a directory named 'claude'.

echo ""
echo "=== T18: 'agent-sync claude' rejected (HIST-004) ==="
P18="$(new_project)"
write_overlay "$P18"
T18_OUT=$("$AGENT_SYNC" claude "$P18" 2>&1 || true)
T18_EXIT=0
"$AGENT_SYNC" claude "$P18" >/dev/null 2>&1 || T18_EXIT=$?

assert_output_match "HIST-004 error printed" "removed in HIST-004" "$T18_OUT"
assert "claude subcommand exits non-zero"    test "$T18_EXIT" -ne 0
assert "claude subcommand did not mutate P18" test ! -f "$P18/.agent-rules/CLAUDE.md"
assert "claude subcommand did not write AGENTS.override.md" test ! -f "$P18/AGENTS.override.md"

# ===== T19: HIST-005 — Skill prefixing (namespace for agent-toolkit skills) =====
# Scheme B: every deployed skill — core and extras — gets $SKILL_PREFIX applied
# to both its target directory name and its SKILL.md frontmatter `name:` field.
# Default prefix is 'gla-'. The overlay key '**Skill Prefix**:' overrides it;
# 'none'/'off'/'-' opts out; missing trailing dash is auto-appended.

echo ""
echo "=== T19a: Default 'gla-' prefix applied to core + frontmatter ==="
P19A="$(new_project)"
write_overlay "$P19A"
"$AGENT_SYNC" "$P19A" >/dev/null 2>&1 || true

assert "T19a: Cursor skill dir prefixed"          test -d "$P19A/.cursor/skills/gla-pre-commit"
assert "T19a: CC skill dir prefixed"              test -d "$P19A/.claude/skills/gla-pre-commit"
assert "T19a: Codex skill dir prefixed"           test -d "$P19A/.agents/skills/gla-pre-commit"
assert "T19a: Frontmatter name: prefixed"         grep -q '^name: gla-pre-commit' "$P19A/.cursor/skills/gla-pre-commit/SKILL.md"
assert "T19a: Manifest records prefixed name"     grep -qx 'gla-pre-commit' "$P19A/.cursor/skills/.agent-sync-skills-manifest"

# T19b: idempotency — second sync must not double-prefix (no 'gla-gla-pre-commit').
echo ""
echo "=== T19b: Idempotent re-sync (no double-prefix) ==="
"$AGENT_SYNC" "$P19A" >/dev/null 2>&1 || true
"$AGENT_SYNC" cc-skills "$P19A" >/dev/null 2>&1 || true

assert "T19b: No double-prefixed dir"             test ! -d "$P19A/.cursor/skills/gla-gla-pre-commit"
assert "T19b: No double-prefixed frontmatter"     bash -c "! grep -q '^name: gla-gla-' '$P19A/.cursor/skills/gla-pre-commit/SKILL.md'"

# T19c: custom prefix from overlay, auto-dash applied to bare token.
echo ""
echo "=== T19c: Overlay custom prefix with auto-dash ==="
P19C="$(new_project)"
write_overlay "$P19C"
# Inject '**Skill Prefix**: myproj' (no trailing dash) — should become 'myproj-'.
awk '{print} /^\*\*Codex Mode\*\*:/ && !done {print "**Skill Prefix**: myproj"; done=1}' \
    "$P19C/.agent-local.md" > "$P19C/.agent-local.md.new"
mv "$P19C/.agent-local.md.new" "$P19C/.agent-local.md"
"$AGENT_SYNC" "$P19C" >/dev/null 2>&1 || true

assert "T19c: Custom prefix applied (auto-dash)"  test -d "$P19C/.cursor/skills/myproj-pre-commit"
assert "T19c: Frontmatter uses custom prefix"     grep -q '^name: myproj-pre-commit' "$P19C/.cursor/skills/myproj-pre-commit/SKILL.md"
assert "T19c: No default gla- dir leaked"         test ! -d "$P19C/.cursor/skills/gla-pre-commit"

# T19d: opt-out via 'none' — bare names deployed, frontmatter untouched.
echo ""
echo "=== T19d: 'none' opt-out deploys bare names ==="
P19D="$(new_project)"
write_overlay "$P19D"
awk '{print} /^\*\*Codex Mode\*\*:/ && !done {print "**Skill Prefix**: none"; done=1}' \
    "$P19D/.agent-local.md" > "$P19D/.agent-local.md.new"
mv "$P19D/.agent-local.md.new" "$P19D/.agent-local.md"
"$AGENT_SYNC" "$P19D" >/dev/null 2>&1 || true

assert "T19d: Bare skill dir deployed"            test -d "$P19D/.cursor/skills/pre-commit"
assert "T19d: Frontmatter bare name"              grep -q '^name: pre-commit' "$P19D/.cursor/skills/pre-commit/SKILL.md"
assert "T19d: No gla- dir produced"               test ! -d "$P19D/.cursor/skills/gla-pre-commit"

# T19e: prefix switch cleans the previous generation.
# Start with default gla-, then flip to 'myproj-', resync. Old gla-* dirs must
# be removed via the manifest-driven stale cleanup in deploy_artifacts.
echo ""
echo "=== T19e: Prefix switch cleans previous generation ==="
P19E="$(new_project)"
write_overlay "$P19E"
"$AGENT_SYNC" "$P19E" >/dev/null 2>&1 || true
assert "T19e: Default gla- dir exists"            test -d "$P19E/.cursor/skills/gla-pre-commit"

awk '{print} /^\*\*Codex Mode\*\*:/ && !done {print "**Skill Prefix**: myproj-"; done=1}' \
    "$P19E/.agent-local.md" > "$P19E/.agent-local.md.new"
mv "$P19E/.agent-local.md.new" "$P19E/.agent-local.md"
rm -f "$P19E/.agent-sync-hash"  # force re-sync (overlay-only change)
"$AGENT_SYNC" "$P19E" >/dev/null 2>&1 || true

assert "T19e: Switched to myproj- dir"            test -d "$P19E/.cursor/skills/myproj-pre-commit"
assert "T19e: Stale gla- dir removed"             test ! -d "$P19E/.cursor/skills/gla-pre-commit"

# ===== T20: HIST-006 — OpenCode Mode=native full sync =====
# Default OpenCode Mode is 'native'. A full sync must produce a stamp-gated
# opencode.json at project root, plus .opencode/skills/ and .opencode/agent/.
# Subagent source directories are empty upstream, so .opencode/agent/ should
# only be created when deploy_subagent_files has something to emit — test
# accordingly (no assertion that the dir exists unconditionally).

echo ""
echo "=== T20: OpenCode Mode=native full sync (HIST-006) ==="
P20="$(new_project)"
write_overlay "$P20"
"$AGENT_SYNC" "$P20" >/dev/null 2>&1 || true

assert "T20: opencode.json exists"               test -f "$P20/opencode.json"
assert "T20: opencode.json has no legacy marker" bash -c "! grep -q '_generated_by' '$P20/opencode.json'"
assert "T20: opencode.json stamp exists"         test -f "$P20/.opencode/.config-json-agent-sync"
assert "T20: opencode.json references Cursor"    grep -q '\.cursor/rules/\*\.mdc' "$P20/opencode.json"
assert "T20: opencode.json references CC rules"  grep -q '\.claude/rules/\*\.md' "$P20/opencode.json"
assert "T20: OpenCode skills dir exists"         test -d "$P20/.opencode/skills"
assert "T20: OpenCode skill gla-pre-commit"      test -d "$P20/.opencode/skills/gla-pre-commit"
assert "T20: OpenCode skill gla-simple-review"   test -d "$P20/.opencode/skills/gla-simple-review"
assert "T20: OpenCode skill manifest exists"     test -f "$P20/.opencode/skills/.agent-sync-skills-manifest"
assert "T20: OpenCode skill frontmatter prefixed" grep -q '^name: gla-pre-commit' "$P20/.opencode/skills/gla-pre-commit/SKILL.md"
assert "T20: agent-check passes"                 "$AGENT_CHECK" "$P20"

# ===== T21: HIST-006 — OpenCode Mode=off reconcile =====
# Flipping to 'off' must remove the stamp-gated opencode.json and clear
# .opencode/skills + .opencode/agent. Staleness hash must invalidate so the
# next sync executes (we don't gate on hash here because overlay change is
# hash-tracked).

echo ""
echo "=== T21: OpenCode Mode=off (reconcile removes outputs) ==="
P21="$(new_project)"
write_overlay "$P21"
"$AGENT_SYNC" "$P21" >/dev/null 2>&1 || true
# sanity: baseline present
test -f "$P21/opencode.json" || fail "T21: baseline opencode.json missing"

write_overlay "$P21" "native" "native" "off"
"$AGENT_SYNC" "$P21" >/dev/null 2>&1 || true

assert "T21: opencode.json removed"              test ! -f "$P21/opencode.json"
assert "T21: opencode.json stamp removed"        test ! -f "$P21/.opencode/.config-json-agent-sync"
assert "T21: .opencode/ fully removed"           test ! -d "$P21/.opencode"
assert "T21: Cursor / CC outputs preserved"      test -d "$P21/.cursor/rules" -a -d "$P21/.claude/rules"
assert "T21: agent-check passes"                 "$AGENT_CHECK" "$P21"

# ===== T22: HIST-006 — user-authored opencode.json preserved =====
# Stamp-gated ownership: if opencode.json exists without the stamp,
# agent-sync must NOT overwrite it, and agent-check must still pass as long as
# the JSON parses. No attempt to infer agent-sync conventions.

echo ""
echo "=== T22: User-authored opencode.json preserved ==="
P22="$(new_project)"
write_overlay "$P22"
# Plant a user-authored opencode.json BEFORE the first sync.
cat > "$P22/opencode.json" <<'JSON'
{
    "$schema": "https://opencode.ai/config.json",
    "instructions": ["CUSTOM.md"],
    "permission": {
        "skill": {"*": "deny"}
    }
}
JSON
USER_HASH_BEFORE=$(shasum "$P22/opencode.json" | awk '{print $1}')
"$AGENT_SYNC" "$P22" >/dev/null 2>&1 || true
USER_HASH_AFTER=$(shasum "$P22/opencode.json" | awk '{print $1}')

assert "T22: User opencode.json bytes unchanged" test "$USER_HASH_BEFORE" = "$USER_HASH_AFTER"
assert "T22: User opencode.json has no marker"   bash -c "! grep -q '_generated_by' '$P22/opencode.json'"
assert "T22: User opencode.json has no stamp"    test ! -f "$P22/.opencode/.config-json-agent-sync"
assert "T22: agent-check still passes"           "$AGENT_CHECK" "$P22"

# T22b: pre-HIST-009 agent-sync wrote an in-file marker that OpenCode's strict
# schema rejects. The next sync must treat that legacy marker as managed,
# rewrite the config without the marker, and create the external stamp.
echo ""
echo "=== T22b: Legacy OpenCode marker migrates to stamp ==="
P22B="$(new_project)"
write_overlay "$P22B"
cat > "$P22B/opencode.json" <<'JSON'
{
    "$schema": "https://opencode.ai/config.json",
    "_generated_by": "agent-sync",
    "instructions": [".cursor/rules/*.mdc"],
    "permission": {
        "skill": {"gla-*": "allow", "*": "ask"}
    }
}
JSON
"$AGENT_SYNC" "$P22B" >/dev/null 2>&1 || true
assert "T22b: legacy marker removed"             bash -c "! grep -q '_generated_by' '$P22B/opencode.json'"
assert "T22b: stamp created"                     test -f "$P22B/.opencode/.config-json-agent-sync"
assert "T22b: agent-check passes"                "$AGENT_CHECK" "$P22B"

# ===== T23: HIST-006 — skill prefix narrows permission.skill allow =====
# With a custom prefix, opencode.json must emit a narrowed allow
# ("myproj-*": "allow") plus a fallback ("*": "ask") — bare prefix-less
# skills stay behind a prompt so unrelated user-installed skills don't get
# a free pass from agent-toolkit's wildcard.

echo ""
echo "=== T23: Custom skill prefix → narrowed OpenCode permission.skill ==="
P23="$(new_project)"
write_overlay "$P23"
# Inject '**Skill Prefix**: myproj' like T19c.
awk '{print} /^\*\*Codex Mode\*\*:/ && !done {print "**Skill Prefix**: myproj"; done=1}' \
    "$P23/.agent-local.md" > "$P23/.agent-local.md.new"
mv "$P23/.agent-local.md.new" "$P23/.agent-local.md"
"$AGENT_SYNC" "$P23" >/dev/null 2>&1 || true

assert "T23: opencode.json exists"               test -f "$P23/opencode.json"
assert "T23: narrowed allow for myproj-*"        grep -q '"myproj-\*": "allow"' "$P23/opencode.json"
assert "T23: fallback ask for *"                 grep -q '"\*": "ask"' "$P23/opencode.json"
# Inverse: with 'none' opt-out, the wildcard allow must remain.
P23B="$(new_project)"
write_overlay "$P23B"
awk '{print} /^\*\*Codex Mode\*\*:/ && !done {print "**Skill Prefix**: none"; done=1}' \
    "$P23B/.agent-local.md" > "$P23B/.agent-local.md.new"
mv "$P23B/.agent-local.md.new" "$P23B/.agent-local.md"
"$AGENT_SYNC" "$P23B" >/dev/null 2>&1 || true
assert "T23: wildcard allow preserved on opt-out" grep -q '"\*": "allow"' "$P23B/opencode.json"

# ===== T24: HIST-006 — explicit OpenCode subcommands =====
# agent-sync opencode: runs config + skills + subagents together.
# agent-sync opencode-config: only emits opencode.json.
# agent-sync opencode-skills: only deploys skills.
# agent-sync opencode-subagents: no-op when subagents/opencode/ is empty
#                                (the current state), but still exits 0.
# agent-sync subagents: umbrella command, no-op on all tools currently.

echo ""
echo "=== T24: Explicit OpenCode subcommands ==="
P24="$(new_project)"
write_overlay "$P24"
"$AGENT_SYNC" opencode-config "$P24" >/dev/null 2>&1 || true
assert "T24: opencode-config only wrote JSON"         test -f "$P24/opencode.json"
assert "T24: opencode-config wrote stamp"             test -f "$P24/.opencode/.config-json-agent-sync"
assert "T24: opencode-config has no legacy marker"    bash -c "! grep -q '_generated_by' '$P24/opencode.json'"
assert "T24: opencode-config did not write skills"    test ! -d "$P24/.opencode/skills"

P24B="$(new_project)"
write_overlay "$P24B"
"$AGENT_SYNC" opencode-skills "$P24B" >/dev/null 2>&1 || true
assert "T24b: opencode-skills wrote .opencode/skills" test -d "$P24B/.opencode/skills/gla-pre-commit"
assert "T24b: opencode-skills did not write JSON"     test ! -f "$P24B/opencode.json"

# Umbrella subagents target — must succeed with exit 0 even though no
# subagents/<tool>/ source directory is populated upstream. Idempotent
# no-op is the expected behaviour per deploy_subagent_files design.
P24C="$(new_project)"
write_overlay "$P24C"
SUBAGENTS_EXIT=0
"$AGENT_SYNC" subagents "$P24C" >/dev/null 2>&1 || SUBAGENTS_EXIT=$?
assert "T24c: subagents umbrella exits 0"             test "$SUBAGENTS_EXIT" -eq 0

# opencode subcommand with Mode=off must be a polite no-op (exit 0 with warning).
P24D="$(new_project)"
write_overlay "$P24D" "native" "native" "off"
T24D_OUT=$("$AGENT_SYNC" opencode "$P24D" 2>&1 || true)
T24D_EXIT=0
"$AGENT_SYNC" opencode "$P24D" >/dev/null 2>&1 || T24D_EXIT=$?
assert "T24d: opencode+off exits 0"                   test "$T24D_EXIT" -eq 0
assert_output_match "T24d: opencode+off warns" "OpenCode Mode is 'off'" "$T24D_OUT"
assert "T24d: opencode+off did not create config"     test ! -f "$P24D/opencode.json"

# ===== T25: HIST-007 — AGENTS.override.md root entry + sub-repo override =====
# Validates the four pillars of HIST-007:
#   a) root AGENTS.override.md produced and contains real rule content
#   b) .agent-rules/ directory removed (legacy path swept)
#   c) .codex/config.toml carries child_agents_md but NOT
#      project_doc_fallback_filenames (HIST-007 simplification)
#   d) sub-repo AGENTS.override.md exists and AGENTS.md does NOT
#      (eliminates Cursor nested-AGENTS.md double injection)
#   e) end-to-end upgrade: pre-HIST-007 .agent-rules/AGENTS.md +
#      sub-repo AGENTS.md planted manually are both swept on next sync

echo ""
echo "=== T25a: HIST-007 root AGENTS.override.md ==="
P25="$(new_project)"
write_overlay "$P25" "native" "native"
mkdir -p "$P25/libs/core"
printf '# Sub-repo overlay\n' > "$P25/libs/core/.agent-local.md"
"$AGENT_SYNC" "$P25" >/dev/null 2>&1 || true

assert "T25a: root AGENTS.override.md exists"         test -f "$P25/AGENTS.override.md"
# Real rule content check — at least one core rule heading must be present.
assert "T25a: AGENTS.override.md contains core rules" grep -q 'Communication\|Workflow\|Quality' "$P25/AGENTS.override.md"
assert "T25a: AGENTS.override.md has agent-sync header" grep -q '<!-- Auto-generated by agent-sync' "$P25/AGENTS.override.md"

echo ""
echo "=== T25b: HIST-007 .agent-rules/ legacy dir removed ==="
assert "T25b: no .agent-rules/ dir"                   test ! -d "$P25/.agent-rules"
assert "T25b: no .agent-rules/AGENTS.md"              test ! -f "$P25/.agent-rules/AGENTS.md"

echo ""
echo "=== T25c: HIST-007 .codex/config.toml simplified ==="
assert "T25c: config.toml has child_agents_md"        grep -q 'child_agents_md = true' "$P25/.codex/config.toml"
assert "T25c: config.toml NO fallback_filenames"      bash -c "! grep -q 'project_doc_fallback_filenames' '$P25/.codex/config.toml'"

echo ""
echo "=== T25d: HIST-007 sub-repo AGENTS.override.md ==="
assert "T25d: sub-repo AGENTS.override.md exists"     test -f "$P25/libs/core/AGENTS.override.md"
assert "T25d: sub-repo AGENTS.md absent"              test ! -f "$P25/libs/core/AGENTS.md"
assert "T25d: agent-check passes"                     "$AGENT_CHECK" "$P25"

echo ""
echo "=== T25e: HIST-007 upgrade path (legacy artifacts swept) ==="
P25E="$(new_project)"
write_overlay "$P25E" "native" "native"
mkdir -p "$P25E/libs/core"
printf '# Sub-repo overlay\n' > "$P25E/libs/core/.agent-local.md"
# Plant pre-HIST-007 artifacts BEFORE the first sync so the cleanup pass
# walks them. Mark with the auto-generated header so the orphan scanner
# in `agent-sync clean` would also recognize them as agent-sync-owned.
mkdir -p "$P25E/.agent-rules"
printf '<!-- Auto-generated by agent-sync. Do not edit manually. -->\n# legacy root\n' \
    > "$P25E/.agent-rules/AGENTS.md"
printf '<!-- Auto-generated by agent-sync (sub-repo overlay only). -->\n# legacy sub\n' \
    > "$P25E/libs/core/AGENTS.md"
"$AGENT_SYNC" "$P25E" >/dev/null 2>&1 || true

assert "T25e: legacy .agent-rules/AGENTS.md swept"    test ! -f "$P25E/.agent-rules/AGENTS.md"
assert "T25e: legacy .agent-rules/ rmdir'd"           test ! -d "$P25E/.agent-rules"
assert "T25e: legacy sub-repo AGENTS.md swept"        test ! -f "$P25E/libs/core/AGENTS.md"
assert "T25e: new root AGENTS.override.md produced"   test -f "$P25E/AGENTS.override.md"
assert "T25e: new sub-repo AGENTS.override.md"        test -f "$P25E/libs/core/AGENTS.override.md"

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
