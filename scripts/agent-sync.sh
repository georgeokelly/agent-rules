#!/bin/bash
set -euo pipefail

# agent-sync.sh — Sync rules from central repo to project directory
# Usage: agent-sync.sh [project-dir]
#
# Environment:
#   AGENT_RULES_HOME  — path to central rules repo (default: ~/.config/agent-rules)

show_help() {
    cat <<'EOF'
agent-sync — Sync rules from central repo to project directory

USAGE
    agent-sync [options] [project-dir]

ARGUMENTS
    project-dir    Target project directory (default: current directory)

OPTIONS
    -h, --help     Show this help message and exit

ENVIRONMENT
    AGENT_RULES_HOME   Path to central rules repo (default: ~/.config/agent-rules)

WHAT IT DOES
    1. Generates Cursor .mdc files in .cursor/rules/ (with frontmatter)
    2. Generates CLAUDE.md for Claude Code
    3. Generates AGENTS.md for Codex
    4. Applies project-specific overlays from .agent-local.md
    5. Handles nested sub-repo overlays

EXAMPLES
    agent-sync                  # Sync rules to current directory
    agent-sync ~/my-project     # Sync rules to a specific project
EOF
    exit 0
}

case "${1:-}" in
    -h|--help) show_help ;;
esac

RULES_HOME="${AGENT_RULES_HOME:-$HOME/.config/agent-rules}"

strip_html_comments() {
    # Remove HTML comments (<!-- ... -->) including multi-line ones
    # Keeps all other content intact
    perl -0777 -pe 's/<!--.*?-->\n?//gs' 2>/dev/null \
        || python3 -c "
import re, sys
text = sys.stdin.read()
print(re.sub(r'<!--.*?-->\n?', '', text, flags=re.DOTALL), end='')
" 2>/dev/null \
        || cat  # fallback: pass through unchanged
}
PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

HASH_FILE="$PROJECT_DIR/.agent-sync-hash"

# --- Validation ---

if [ ! -d "$RULES_HOME" ]; then
    echo "ERROR: Rules repo not found at $RULES_HOME"
    echo "  Set AGENT_RULES_HOME or create the directory."
    exit 1
fi

if [ ! -d "$RULES_HOME/core" ] || [ ! -d "$RULES_HOME/packs" ]; then
    echo "ERROR: Rules repo missing core/ or packs/ directory."
    exit 1
fi

# --- Check if sync is needed ---

HASH_CMD="shasum"
command -v shasum &>/dev/null || HASH_CMD="sha1sum"
command -v $HASH_CMD &>/dev/null || HASH_CMD="md5sum"

RULES_HASH=""
if [ -d "$RULES_HOME/.git" ]; then
    RULES_HASH="$(git -C "$RULES_HOME" rev-parse HEAD 2>/dev/null || echo "no-git")"
else
    RULES_HASH="$(find "$RULES_HOME" \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.css' -o -name '*.sh' \) -type f -exec $HASH_CMD {} + 2>/dev/null | $HASH_CMD | awk '{print $1}')"
fi

OVERLAY_HASH="$(find "$PROJECT_DIR" -name '.agent-local.md' -not -path '*/.git/*' -not -path '*/node_modules/*' -type f -exec $HASH_CMD {} + 2>/dev/null | $HASH_CMD | awk '{print $1}')"
CURRENT_HASH="${RULES_HASH}:${OVERLAY_HASH}"

STORED_HASH=""
if [ -f "$HASH_FILE" ]; then
    STORED_HASH="$(cat "$HASH_FILE")"
fi

CURSOR_EXISTS=false
CLAUDE_EXISTS=false
AGENTS_EXISTS=false
[ -d "$PROJECT_DIR/.cursor/rules" ] && [ "$(ls -A "$PROJECT_DIR/.cursor/rules/" 2>/dev/null)" ] && CURSOR_EXISTS=true
[ -f "$PROJECT_DIR/CLAUDE.md" ] && CLAUDE_EXISTS=true
[ -f "$PROJECT_DIR/AGENTS.md" ] && AGENTS_EXISTS=true

if [ "$CURRENT_HASH" = "$STORED_HASH" ] && $CURSOR_EXISTS && $CLAUDE_EXISTS && $AGENTS_EXISTS; then
    echo "Rules up to date. No sync needed."
    exit 0
fi

echo "Syncing rules from $RULES_HOME → $PROJECT_DIR"

# --- Resolve active packs (for CLAUDE.md / AGENTS.md) ---

DEFAULT_PACKS="cpp cuda python markdown shell git"
ACTIVE_PACKS="$DEFAULT_PACKS"

if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
    OVERLAY_PACKS="$(sed -n 's/^\*\*Packs\*\*:[[:space:]]*//p' "$PROJECT_DIR/.agent-local.md" | head -1)"
    if [ -n "$OVERLAY_PACKS" ]; then
        ACTIVE_PACKS="$(echo "$OVERLAY_PACKS" | tr ',' ' ' | xargs)"
    fi
fi

pack_is_active() {
    local pack_name="$1"
    for p in $ACTIVE_PACKS; do
        [ "$p" = "$pack_name" ] && return 0
    done
    return 1
}

echo "  Active packs: $ACTIVE_PACKS"

# --- Generate Cursor .mdc files ---

mkdir -p "$PROJECT_DIR/.cursor/rules"

FRONTMATTER_DIR="$RULES_HOME/templates/cursor-frontmatter"

for rule_file in "$RULES_HOME"/core/*.md "$RULES_HOME"/packs/*.md; do
    [ -f "$rule_file" ] || continue
    basename_no_ext="$(basename "$rule_file" .md)"
    # Strip numeric prefix for frontmatter lookup (00-communication → communication)
    lookup_name="$(echo "$basename_no_ext" | sed 's/^[0-9]*-//')"
    target="$PROJECT_DIR/.cursor/rules/${basename_no_ext}.mdc"

    echo "---" > "$target"
    if [ -f "$FRONTMATTER_DIR/${lookup_name}.yaml" ]; then
        cat "$FRONTMATTER_DIR/${lookup_name}.yaml" >> "$target"
    else
        echo "description: ${lookup_name} rules" >> "$target"
        echo "alwaysApply: false" >> "$target"
    fi
    echo "---" >> "$target"
    echo "" >> "$target"
    cat "$rule_file" >> "$target"
done

# Append project overlay to a separate always-apply .mdc
if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
    target="$PROJECT_DIR/.cursor/rules/project-overlay.mdc"
    echo "---" > "$target"
    echo "description: Project-specific rules and constraints" >> "$target"
    echo "alwaysApply: true" >> "$target"
    echo "---" >> "$target"
    echo "" >> "$target"
    strip_html_comments < "$PROJECT_DIR/.agent-local.md" >> "$target"
else
    rm -f "$PROJECT_DIR/.cursor/rules/project-overlay.mdc"
fi

echo "  Cursor: $(ls "$PROJECT_DIR/.cursor/rules/"*.mdc 2>/dev/null | wc -l | tr -d ' ') .mdc files"

# --- Ensure .cursorignore excludes CLAUDE.md/AGENTS.md ---

CURSORIGNORE="$PROJECT_DIR/.cursorignore"
IGNORE_ENTRIES=("CLAUDE.md" "AGENTS.md")
for entry in "${IGNORE_ENTRIES[@]}"; do
    if [ ! -f "$CURSORIGNORE" ] || ! grep -qxF "$entry" "$CURSORIGNORE"; then
        echo "$entry" >> "$CURSORIGNORE"
    fi
done

# --- Generate CLAUDE.md ---

CLAUDE_FILE="$PROJECT_DIR/CLAUDE.md"
echo "<!-- Auto-generated by agent-sync. Do not edit manually. -->" > "$CLAUDE_FILE"
echo "" >> "$CLAUDE_FILE"

for rule_file in "$RULES_HOME"/core/*.md; do
    [ -f "$rule_file" ] || continue
    cat "$rule_file" >> "$CLAUDE_FILE"
    echo "" >> "$CLAUDE_FILE"
    echo "---" >> "$CLAUDE_FILE"
    echo "" >> "$CLAUDE_FILE"
done

for rule_file in "$RULES_HOME"/packs/*.md; do
    [ -f "$rule_file" ] || continue
    pack_name="$(basename "$rule_file" .md)"
    pack_is_active "$pack_name" || continue
    cat "$rule_file" >> "$CLAUDE_FILE"
    echo "" >> "$CLAUDE_FILE"
    echo "---" >> "$CLAUDE_FILE"
    echo "" >> "$CLAUDE_FILE"
done

if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
    strip_html_comments < "$PROJECT_DIR/.agent-local.md" >> "$CLAUDE_FILE"
    echo "" >> "$CLAUDE_FILE"
fi

echo "  Claude Code: CLAUDE.md ($(wc -c < "$CLAUDE_FILE" | tr -d ' ') bytes)"

# --- Generate AGENTS.md (same content as CLAUDE.md for Codex) ---

cp "$CLAUDE_FILE" "$PROJECT_DIR/AGENTS.md"
sed -i.bak '1s/.*<!-- Auto-generated.*/<!-- Auto-generated by agent-sync for Codex. Do not edit manually. -->/' "$PROJECT_DIR/AGENTS.md" 2>/dev/null || true
rm -f "$PROJECT_DIR/AGENTS.md.bak"

AGENTS_SIZE=$(wc -c < "$PROJECT_DIR/AGENTS.md" | tr -d ' ')
echo "  Codex: AGENTS.md ($AGENTS_SIZE bytes)"

if [ "$AGENTS_SIZE" -gt 32768 ]; then
    echo "  WARNING: AGENTS.md exceeds 32KiB ($AGENTS_SIZE bytes). Codex may silently truncate!"
fi

# --- Recursive: generate sub-repo CLAUDE.md/AGENTS.md for nested .agent-local.md ---

MANIFEST="$PROJECT_DIR/.agent-sync-manifest"
MANIFEST_NEW="$MANIFEST.new"
: > "$MANIFEST_NEW"

find "$PROJECT_DIR" -mindepth 2 -name '.agent-local.md' -not -path '*/.git/*' -not -path '*/node_modules/*' | while read -r sub_overlay; do
    SUB_DIR="$(dirname "$sub_overlay")"
    SUB_REL="${SUB_DIR#"$PROJECT_DIR"/}"

    SUB_CLAUDE="$SUB_DIR/CLAUDE.md"
    echo "<!-- Auto-generated by agent-sync (sub-repo overlay only). Do not edit manually. -->" > "$SUB_CLAUDE"
    echo "" >> "$SUB_CLAUDE"
    strip_html_comments < "$sub_overlay" >> "$SUB_CLAUDE"

    cp "$SUB_CLAUDE" "$SUB_DIR/AGENTS.md"

    echo "$SUB_REL" >> "$MANIFEST_NEW"
    echo "  Sub-repo $SUB_REL: CLAUDE.md + AGENTS.md (overlay only, $(wc -c < "$SUB_CLAUDE" | tr -d ' ') bytes)"
done

# Clean up ghost rule files from deleted sub-repo overlays
if [ -f "$MANIFEST" ]; then
    while IFS= read -r old_rel; do
        if [ ! -f "$PROJECT_DIR/$old_rel/.agent-local.md" ]; then
            rm -f "$PROJECT_DIR/$old_rel/CLAUDE.md" "$PROJECT_DIR/$old_rel/AGENTS.md"
            echo "  Cleaned ghost rules: $old_rel/ (overlay removed)"
        fi
    done < "$MANIFEST"
fi
mv "$MANIFEST_NEW" "$MANIFEST"

# --- Store sync hash ---

echo "$CURRENT_HASH" > "$HASH_FILE"

echo "Sync complete."
