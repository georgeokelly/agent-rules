#!/bin/bash
set -euo pipefail

# agent-sync.sh — Sync rules from central repo to project directory
# Usage: agent-sync.sh [subcommand] [project-dir]
#
# Environment:
#   AGENT_RULES_HOME  — path to central rules repo (default: ~/.config/agent-rules)

show_help() {
    cat <<'EOF'
agent-sync — Sync rules from central repo to project directory

USAGE
    agent-sync [project-dir]              Full sync (default)
    agent-sync codex [project-dir]        Only generate AGENTS.md
    agent-sync claude [project-dir]       Only generate CLAUDE.md
    agent-sync skills [project-dir]       Only sync skills to .cursor/skills/
    agent-sync commands [project-dir]     Only sync commands to .cursor/commands/
    agent-sync clean [project-dir]        Remove all generated files
    agent-sync -h | --help                Show this help message

ARGUMENTS
    project-dir    Target project directory (default: current directory)

ENVIRONMENT
    AGENT_RULES_HOME   Path to central rules repo (default: ~/.config/agent-rules)

SUBCOMMANDS
    (default)   Full sync: generates Cursor .mdc files, CLAUDE.md, AGENTS.md,
                applies project overlays, handles sub-repo overlays, and
                cleans up root-level remnants. Skips if already up to date.

    codex       Only generate .agent-rules/AGENTS.md for Codex.
                Always regenerates (skips staleness check).

    claude      Only generate .agent-rules/CLAUDE.md for Claude Code.
                Always regenerates (skips staleness check).

    skills      Only sync skills from $AGENT_RULES_HOME/skills/ to
                .cursor/skills/ in the target project (root only).

    commands    Only sync commands from $AGENT_RULES_HOME/commands/ to
                .cursor/commands/ in the target project (root only).

    clean       Remove all generated files:
                .cursor/rules/*.mdc, .cursor/skills/, .cursor/commands/,
                .agent-rules/, .agent-sync-hash, .agent-sync-manifest,
                and sub-repo CLAUDE.md/AGENTS.md.

EXAMPLES
    agent-sync                  # Full sync to current directory
    agent-sync ~/my-project     # Full sync to a specific project
    agent-sync codex .          # Regenerate only AGENTS.md
    agent-sync claude .         # Regenerate only CLAUDE.md
    agent-sync clean            # Remove all generated files
EOF
    exit 0
}

# --- Parse arguments: detect subcommand, then project-dir ---

SUBCOMMAND="sync"
case "${1:-}" in
    -h|--help) show_help ;;
    codex|claude|skills|commands|clean)
        SUBCOMMAND="$1"
        shift
        ;;
esac

RULES_HOME="${AGENT_RULES_HOME:-$HOME/.config/agent-rules}"

strip_html_comments() {
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
MANIFEST="$PROJECT_DIR/.agent-sync-manifest"

# --- Validation ---

validate_rules_repo() {
    echo "Checking rules repo at $RULES_HOME ..."
    if [ ! -d "$RULES_HOME" ]; then
        echo "ERROR: Rules repo not found at $RULES_HOME"
        echo "  Set AGENT_RULES_HOME or create the directory."
        exit 1
    fi
    if [ ! -d "$RULES_HOME/core" ] || [ ! -d "$RULES_HOME/packs" ]; then
        echo "ERROR: Rules repo missing core/ or packs/ directory."
        exit 1
    fi
    # Initialize submodules (extras/) so their content is available; non-blocking on failure
    git -C "$RULES_HOME" submodule update --init --recursive --quiet 2>&1 || {
        echo "  WARNING: Submodule initialization failed. extras/ will be skipped."
        echo "           To diagnose: git -C \"$RULES_HOME\" submodule update --init --recursive"
    }
}

# --- Pack resolution ---

ACTIVE_PACKS=""

resolve_packs() {
    local default_packs="cpp cuda python markdown shell git"
    ACTIVE_PACKS="$default_packs"
    if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
        local overlay_packs
        # Strip inline HTML comments left by project-overlay skill (e.g. <!-- [推断] ... -->)
        overlay_packs="$(sed -n 's/^\*\*Packs\*\*:[[:space:]]*//p' "$PROJECT_DIR/.agent-local.md" | head -1 | sed 's/<!--.*-->//')"
        if [ -n "$overlay_packs" ]; then
            ACTIVE_PACKS="$(echo "$overlay_packs" | tr ',' ' ' | xargs)"
        fi
    fi
    echo "  Active packs: $ACTIVE_PACKS"
}

pack_is_active() {
    local pack_name="$1"
    local p
    for p in $ACTIVE_PACKS; do
        [ "$p" = "$pack_name" ] && return 0
    done
    return 1
}

# --- Staleness check (full sync only) ---

CURRENT_HASH=""

check_staleness() {
    echo "Computing staleness hash ..."

    local hash_cmd="shasum"
    command -v shasum &>/dev/null || hash_cmd="sha1sum"
    command -v $hash_cmd &>/dev/null || hash_cmd="md5sum"

    local rules_hash=""
    if [ -d "$RULES_HOME/.git" ]; then
        local sub_hash
        # Include each submodule's pinned commit so extras/ updates trigger re-sync
        sub_hash="$(git -C "$RULES_HOME" submodule status 2>/dev/null | awk '{print $1}' | tr -d '+-U' | sort | tr -d '\n')"
        rules_hash="$(git -C "$RULES_HOME" rev-parse HEAD 2>/dev/null || echo "no-git"):${sub_hash:-no-submodules}"
    else
        rules_hash="$(find "$RULES_HOME" \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.sh' \) -type f -exec $hash_cmd {} + 2>/dev/null | $hash_cmd | awk '{print $1}')"
    fi

    # -maxdepth 3: intentional trade-off — .agent-local.md deeper than 3 levels is unsupported
    # to avoid costly full-tree traversal in large repos (build dirs, .venv, etc.)
    local overlay_hash
    overlay_hash="$(find "$PROJECT_DIR" -maxdepth 3 -name '.agent-local.md' -not -path '*/.git/*' -not -path '*/node_modules/*' -type f -exec $hash_cmd {} + 2>/dev/null | $hash_cmd | awk '{print $1}')"
    CURRENT_HASH="${rules_hash}:${overlay_hash}"

    local stored_hash=""
    if [ -f "$HASH_FILE" ]; then
        stored_hash="$(cat "$HASH_FILE")"
    fi

    local cursor_exists=false claude_exists=false agents_exists=false skills_ok=true commands_ok=true
    [ -d "$PROJECT_DIR/.cursor/rules" ] && [ "$(ls -A "$PROJECT_DIR/.cursor/rules/" 2>/dev/null)" ] && cursor_exists=true
    [ -f "$PROJECT_DIR/.agent-rules/CLAUDE.md" ] && claude_exists=true
    [ -f "$PROJECT_DIR/.agent-rules/AGENTS.md" ] && agents_exists=true
    # If rules repo has skills, ensure they are deployed
    if [ -d "$RULES_HOME/skills" ] && [ "$(ls -d "$RULES_HOME/skills/"*/ 2>/dev/null)" ]; then
        [ -f "$SKILLS_MANIFEST" ] || skills_ok=false
    fi
    # If rules repo has commands, ensure they are deployed
    if [ -d "$RULES_HOME/commands" ] && [ "$(ls "$RULES_HOME/commands/"*.md 2>/dev/null)" ]; then
        [ -f "$COMMANDS_MANIFEST" ] || commands_ok=false
    fi

    if [ "$CURRENT_HASH" = "$stored_hash" ] && $cursor_exists && $claude_exists && $agents_exists && $skills_ok && $commands_ok; then
        echo "Rules up to date. No sync needed."
        exit 0
    fi
}

# --- Generation functions ---

generate_cursor() {
    mkdir -p "$PROJECT_DIR/.cursor/rules"
    local frontmatter_dir="$RULES_HOME/templates/cursor-frontmatter"

    local rule_file basename_no_ext lookup_name target
    for rule_file in "$RULES_HOME"/core/*.md "$RULES_HOME"/packs/*.md; do
        [ -f "$rule_file" ] || continue
        basename_no_ext="$(basename "$rule_file" .md)"
        # Strip numeric prefix for frontmatter lookup (00-communication → communication)
        lookup_name="$(echo "$basename_no_ext" | sed 's/^[0-9]*-//')"
        target="$PROJECT_DIR/.cursor/rules/${basename_no_ext}.mdc"

        echo "---" > "$target"
        if [ -f "$frontmatter_dir/${lookup_name}.yaml" ]; then
            cat "$frontmatter_dir/${lookup_name}.yaml" >> "$target"
        else
            echo "description: ${lookup_name} rules" >> "$target"
            echo "alwaysApply: false" >> "$target"
        fi
        echo "---" >> "$target"
        echo "" >> "$target"
        cat "$rule_file" >> "$target"
    done

    # Project overlay as a separate always-apply .mdc
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
        echo "  NOTE: No .agent-local.md found. Project overlay skipped."
        echo "        Create one manually: cp \$AGENT_RULES_HOME/templates/overlay-template.md .agent-local.md"
        echo "        Or ask your AI agent to run the \"project-overlay\" skill for guided setup."
    fi

    echo "  Cursor: $(ls "$PROJECT_DIR/.cursor/rules/"*.mdc 2>/dev/null | wc -l | tr -d ' ') .mdc files"
}

# Deploy skills from $RULES_HOME/skills/ to project root .cursor/skills/ (depth=0 only)
# Uses manifest for precise cleanup; convergent sync (rm + cp) to avoid stale files.
SKILLS_MANIFEST="$PROJECT_DIR/.cursor/skills/.agent-sync-skills-manifest"

generate_skills() {
    local skills_src="$RULES_HOME/skills"
    [ -d "$skills_src" ] || return 0

    local skill_dir skill_name target_dir
    local count=0
    local manifest_new="${SKILLS_MANIFEST}.new"
    mkdir -p "$PROJECT_DIR/.cursor/skills"
    : > "$manifest_new"

    for skill_dir in "$skills_src"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name="$(basename "$skill_dir")"
        target_dir="$PROJECT_DIR/.cursor/skills/$skill_name"
        # Convergent sync: clean target then copy fresh
        rm -rf "$target_dir"
        mkdir -p "$target_dir"
        # Guard: skip copy if skill dir is empty (glob won't expand under set -e)
        if [ -n "$(ls -A "$skill_dir" 2>/dev/null)" ]; then
            cp -R "$skill_dir"* "$target_dir/"
        fi
        echo "$skill_name" >> "$manifest_new"
        count=$((count + 1))
    done

    # Deploy skills from extras/ — core takes priority; skip extras duplicates
    if [ -d "$RULES_HOME/extras" ]; then
        local extras_dir bundle_name
        for extras_dir in "$RULES_HOME/extras"/*/; do
            [ -d "$extras_dir/skills" ] || continue
            bundle_name="$(basename "$extras_dir")"
            for skill_dir in "$extras_dir/skills"/*/; do
                [ -d "$skill_dir" ] || continue
                skill_name="$(basename "$skill_dir")"
                # Core always wins — skip extras duplicate
                if [ -d "$skills_src/$skill_name" ]; then
                    echo "  SKIP: extras/$bundle_name skill '$skill_name' — same name exists in core (core wins)"
                    echo "        To use both, create a renamed symlink in the extras bundle."
                    continue
                fi
                target_dir="$PROJECT_DIR/.cursor/skills/$skill_name"
                rm -rf "$target_dir"
                mkdir -p "$target_dir"
                if [ -n "$(ls -A "$skill_dir" 2>/dev/null)" ]; then
                    cp -R "$skill_dir"* "$target_dir/"
                fi
                echo "$skill_name" >> "$manifest_new"
                count=$((count + 1))
            done
        done
    fi

    # Remove skills that were previously synced but no longer exist in any source (core or extras)
    if [ -f "$SKILLS_MANIFEST" ]; then
        local old_skill found extras_dir
        while IFS= read -r old_skill; do
            [ -z "$old_skill" ] && continue
            found=false
            [ -d "$skills_src/$old_skill" ] && found=true
            if ! $found && [ -d "$RULES_HOME/extras" ]; then
                for extras_dir in "$RULES_HOME/extras"/*/; do
                    [ -d "${extras_dir}skills/$old_skill" ] && found=true && break
                done
            fi
            if ! $found; then
                rm -rf "$PROJECT_DIR/.cursor/skills/$old_skill"
                echo "  Removed stale skill: $old_skill"
            fi
        done < "$SKILLS_MANIFEST"
    fi

    mv "$manifest_new" "$SKILLS_MANIFEST"
    echo "  Skills: $count skill(s) synced to .cursor/skills/"
}

# Deploy commands from $RULES_HOME/commands/ to project root .cursor/commands/
# Commands are flat .md files (not directories like skills).
# Uses manifest for precise cleanup; convergent sync to avoid stale files.
COMMANDS_MANIFEST="$PROJECT_DIR/.cursor/commands/.agent-sync-commands-manifest"

generate_commands() {
    local commands_src="$RULES_HOME/commands"
    [ -d "$commands_src" ] || return 0

    local cmd_file cmd_name
    local count=0
    local manifest_new="${COMMANDS_MANIFEST}.new"
    mkdir -p "$PROJECT_DIR/.cursor/commands"
    : > "$manifest_new"

    for cmd_file in "$commands_src"/*.md; do
        [ -f "$cmd_file" ] || continue
        cmd_name="$(basename "$cmd_file")"
        cp "$cmd_file" "$PROJECT_DIR/.cursor/commands/$cmd_name"
        echo "$cmd_name" >> "$manifest_new"
        count=$((count + 1))
    done

    # Deploy commands from extras/ — core takes priority; skip extras duplicates
    if [ -d "$RULES_HOME/extras" ]; then
        local extras_dir bundle_name
        for extras_dir in "$RULES_HOME/extras"/*/; do
            [ -d "$extras_dir/commands" ] || continue
            bundle_name="$(basename "$extras_dir")"
            for cmd_file in "$extras_dir/commands"/*.md; do
                [ -f "$cmd_file" ] || continue
                cmd_name="$(basename "$cmd_file")"
                # Core always wins — skip extras duplicate
                if [ -f "$commands_src/$cmd_name" ]; then
                    echo "  SKIP: extras/$bundle_name command '$cmd_name' — same name exists in core (core wins)"
                    echo "        To use both, create a renamed copy or symlink in the extras bundle."
                    continue
                fi
                cp "$cmd_file" "$PROJECT_DIR/.cursor/commands/$cmd_name"
                echo "$cmd_name" >> "$manifest_new"
                count=$((count + 1))
            done
        done
    fi

    # Remove commands that were previously synced but no longer exist in any source (core or extras)
    if [ -f "$COMMANDS_MANIFEST" ]; then
        local old_cmd found extras_dir
        while IFS= read -r old_cmd; do
            [ -z "$old_cmd" ] && continue
            found=false
            [ -f "$commands_src/$old_cmd" ] && found=true
            if ! $found && [ -d "$RULES_HOME/extras" ]; then
                for extras_dir in "$RULES_HOME/extras"/*/; do
                    [ -f "${extras_dir}commands/$old_cmd" ] && found=true && break
                done
            fi
            if ! $found; then
                rm -f "$PROJECT_DIR/.cursor/commands/$old_cmd"
                echo "  Removed stale command: $old_cmd"
            fi
        done < "$COMMANDS_MANIFEST"
    fi

    mv "$manifest_new" "$COMMANDS_MANIFEST"
    echo "  Commands: $count command(s) synced to .cursor/commands/"
}

generate_claude() {
    mkdir -p "$PROJECT_DIR/.agent-rules"
    local claude_file="$PROJECT_DIR/.agent-rules/CLAUDE.md"
    echo "<!-- Auto-generated by agent-sync. Do not edit manually. -->" > "$claude_file"
    echo "" >> "$claude_file"

    local rule_file pack_name
    for rule_file in "$RULES_HOME"/core/*.md; do
        [ -f "$rule_file" ] || continue
        cat "$rule_file" >> "$claude_file"
        echo "" >> "$claude_file"
        echo "---" >> "$claude_file"
        echo "" >> "$claude_file"
    done

    for rule_file in "$RULES_HOME"/packs/*.md; do
        [ -f "$rule_file" ] || continue
        pack_name="$(basename "$rule_file" .md)"
        pack_is_active "$pack_name" || continue
        cat "$rule_file" >> "$claude_file"
        echo "" >> "$claude_file"
        echo "---" >> "$claude_file"
        echo "" >> "$claude_file"
    done

    if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
        strip_html_comments < "$PROJECT_DIR/.agent-local.md" >> "$claude_file"
        echo "" >> "$claude_file"
    fi

    echo "  Claude Code: CLAUDE.md ($(wc -c < "$claude_file" | tr -d ' ') bytes)"
}

generate_codex() {
    mkdir -p "$PROJECT_DIR/.agent-rules"

    # AGENTS.md is derived from CLAUDE.md; always regenerate to avoid stale content
    generate_claude

    cp "$PROJECT_DIR/.agent-rules/CLAUDE.md" "$PROJECT_DIR/.agent-rules/AGENTS.md"
    sed -i.bak '1s/.*<!-- Auto-generated.*/<!-- Auto-generated by agent-sync for Codex. Do not edit manually. -->/' "$PROJECT_DIR/.agent-rules/AGENTS.md" 2>/dev/null || true
    rm -f "$PROJECT_DIR/.agent-rules/AGENTS.md.bak"

    local agents_size
    agents_size=$(wc -c < "$PROJECT_DIR/.agent-rules/AGENTS.md" | tr -d ' ')
    echo "  Codex: AGENTS.md ($agents_size bytes)"
    if [ "$agents_size" -gt 32768 ]; then
        echo "  WARNING: AGENTS.md exceeds 32KiB ($agents_size bytes). Codex may silently truncate!"
    fi
}

cleanup_remnants() {
    rm -f "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/AGENTS.md" "$PROJECT_DIR/.cursorignore"
}

sync_sub_repos() {
    local manifest_new="$MANIFEST.new"
    : > "$manifest_new"

    # -maxdepth 3: matches check_staleness depth — overlays deeper than 3 levels are unsupported
    local sub_overlay sub_dir sub_rel sub_claude
    find "$PROJECT_DIR" -mindepth 2 -maxdepth 3 -name '.agent-local.md' -not -path '*/.git/*' -not -path '*/node_modules/*' | while read -r sub_overlay; do
        sub_dir="$(dirname "$sub_overlay")"
        sub_rel="${sub_dir#"$PROJECT_DIR"/}"

        sub_claude="$sub_dir/CLAUDE.md"
        echo "<!-- Auto-generated by agent-sync (sub-repo overlay only). Do not edit manually. -->" > "$sub_claude"
        echo "" >> "$sub_claude"
        strip_html_comments < "$sub_overlay" >> "$sub_claude"

        cp "$sub_claude" "$sub_dir/AGENTS.md"

        echo "$sub_rel" >> "$manifest_new"
        echo "  Sub-repo $sub_rel: CLAUDE.md + AGENTS.md (overlay only, $(wc -c < "$sub_claude" | tr -d ' ') bytes)"
    done

    # Clean up ghost rule files from deleted sub-repo overlays
    if [ -f "$MANIFEST" ]; then
        local old_rel
        while IFS= read -r old_rel; do
            if [ ! -f "$PROJECT_DIR/$old_rel/.agent-local.md" ]; then
                rm -f "$PROJECT_DIR/$old_rel/CLAUDE.md" "$PROJECT_DIR/$old_rel/AGENTS.md"
                echo "  Cleaned ghost rules: $old_rel/ (overlay removed)"
            fi
        done < "$MANIFEST"
    fi
    mv "$manifest_new" "$MANIFEST"
}

store_hash() {
    echo "$CURRENT_HASH" > "$HASH_FILE"
}

# --- Clean subcommand ---

do_clean() {
    echo "Cleaning generated files in $PROJECT_DIR ..."

    if [ -d "$PROJECT_DIR/.cursor/rules" ]; then
        rm -f "$PROJECT_DIR/.cursor/rules/"*.mdc
        rmdir "$PROJECT_DIR/.cursor/rules" 2>/dev/null || true
        echo "  Removed .cursor/rules/*.mdc"
    fi

    # Clean only agent-sync managed skills (manifest-based)
    if [ -f "$SKILLS_MANIFEST" ]; then
        local old_skill
        while IFS= read -r old_skill; do
            [ -z "$old_skill" ] && continue
            rm -rf "$PROJECT_DIR/.cursor/skills/$old_skill"
        done < "$SKILLS_MANIFEST"
        rm -f "$SKILLS_MANIFEST"
        rmdir "$PROJECT_DIR/.cursor/skills" 2>/dev/null || true
        echo "  Removed agent-sync managed skills"
    elif [ -d "$PROJECT_DIR/.cursor/skills" ]; then
        echo "  WARNING: .cursor/skills/ exists but no manifest found."
        echo "           Cannot determine which skills were managed by agent-sync."
        echo "           Run 'agent-sync .' to regenerate manifest, then 'agent-sync clean' to retry."
    fi

    # Clean only agent-sync managed commands (manifest-based)
    if [ -f "$COMMANDS_MANIFEST" ]; then
        local old_cmd
        while IFS= read -r old_cmd; do
            [ -z "$old_cmd" ] && continue
            rm -f "$PROJECT_DIR/.cursor/commands/$old_cmd"
        done < "$COMMANDS_MANIFEST"
        rm -f "$COMMANDS_MANIFEST"
        rmdir "$PROJECT_DIR/.cursor/commands" 2>/dev/null || true
        echo "  Removed agent-sync managed commands"
    elif [ -d "$PROJECT_DIR/.cursor/commands" ]; then
        echo "  WARNING: .cursor/commands/ exists but no manifest found."
        echo "           Cannot determine which commands were managed by agent-sync."
        echo "           Run 'agent-sync .' to regenerate manifest, then 'agent-sync clean' to retry."
    fi

    rmdir "$PROJECT_DIR/.cursor" 2>/dev/null || true

    if [ -d "$PROJECT_DIR/.agent-rules" ]; then
        rm -rf "$PROJECT_DIR/.agent-rules"
        echo "  Removed .agent-rules/"
    fi

    rm -f "$HASH_FILE"
    echo "  Removed .agent-sync-hash"

    # Clean sub-repo generated files using manifest
    if [ -f "$MANIFEST" ]; then
        local old_rel
        while IFS= read -r old_rel; do
            rm -f "$PROJECT_DIR/$old_rel/CLAUDE.md" "$PROJECT_DIR/$old_rel/AGENTS.md"
            echo "  Removed sub-repo rules: $old_rel/"
        done < "$MANIFEST"
    fi
    rm -f "$MANIFEST"
    echo "  Removed .agent-sync-manifest"

    # Fallback: scan for auto-generated files missed by manifest (e.g., manifest was deleted)
    local stale_file
    find "$PROJECT_DIR" -mindepth 2 -maxdepth 4 \( -name 'CLAUDE.md' -o -name 'AGENTS.md' \) -not -path '*/.git/*' -not -path '*/.agent-rules/*' -not -path '*/node_modules/*' -type f | while read -r stale_file; do
        if head -1 "$stale_file" 2>/dev/null | grep -q '<!-- Auto-generated by agent-sync'; then
            rm -f "$stale_file"
            echo "  Removed orphan: ${stale_file#"$PROJECT_DIR"/}"
        fi
    done

    # Root-level remnants
    rm -f "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/AGENTS.md" "$PROJECT_DIR/.cursorignore"

    echo "Clean complete."
}

# --- Main dispatch ---

case "$SUBCOMMAND" in
    clean)
        do_clean
        ;;
    codex)
        validate_rules_repo
        resolve_packs
        echo "Generating AGENTS.md for Codex in $PROJECT_DIR ..."
        generate_codex
        echo "Done."
        ;;
    claude)
        validate_rules_repo
        resolve_packs
        echo "Generating CLAUDE.md for Claude Code in $PROJECT_DIR ..."
        generate_claude
        echo "Done."
        ;;
    skills)
        validate_rules_repo
        echo "Syncing skills to $PROJECT_DIR/.cursor/skills/ ..."
        generate_skills
        echo "Done."
        ;;
    commands)
        validate_rules_repo
        echo "Syncing commands to $PROJECT_DIR/.cursor/commands/ ..."
        generate_commands
        echo "Done."
        ;;
    sync)
        validate_rules_repo
        check_staleness
        echo "Syncing rules from $RULES_HOME → $PROJECT_DIR"
        resolve_packs
        generate_cursor
        generate_skills
        generate_commands
        # generate_codex internally calls generate_claude first
        generate_codex
        cleanup_remnants
        sync_sub_repos
        store_hash
        echo "Sync complete."
        ;;
esac
