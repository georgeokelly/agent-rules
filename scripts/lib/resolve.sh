# lib/resolve.sh — Validation, pack/mode resolution, staleness detection
# Sourced by agent-sync.sh. Do not execute directly.

validate_rules_repo() {
    echo "Checking rules repo at $RULES_HOME ..."
    if [ ! -d "$RULES_HOME" ]; then
        _err "ERROR: Rules repo not found at $RULES_HOME"
        _err "  Set AGENT_TOOLKIT_HOME or create the directory."
        exit 1
    fi
    if [ ! -d "$RULES_HOME/core" ] || [ ! -d "$RULES_HOME/packs" ]; then
        _err "ERROR: Rules repo missing core/ or packs/ directory."
        exit 1
    fi
    git -C "$RULES_HOME" submodule update --init --recursive --quiet >/dev/null 2>&1 || {
        _warn "  WARNING: Submodule init failed — extras/ will be skipped."
        _warn "           Likely cause: SSH key not configured for the submodule remote."
        _warn "           Fix: add your SSH key to the remote host, or use HTTPS URL in .gitmodules."
        _warn "           Debug: git -C \"$RULES_HOME\" submodule update --init --recursive"
    }
}

# --- Pack resolution ---

ACTIVE_PACKS=""

resolve_packs() {
    local default_packs="cpp cuda python markdown shell git"
    ACTIVE_PACKS="$default_packs"
    if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
        local overlay_packs
        overlay_packs="$(sed -n 's/^\*\*Packs\*\*:[[:space:]]*//p' "$PROJECT_DIR/.agent-local.md" | head -1 | sed 's/<!--.*-->//')"
        if [ -n "$overlay_packs" ]; then
            ACTIVE_PACKS="$(echo "$overlay_packs" | tr ',' ' ' | xargs)"
        fi
    fi
    echo "  Active packs: $ACTIVE_PACKS"
}

pack_is_active() {
    local pack_name="$1" p
    for p in $ACTIVE_PACKS; do
        [ "$p" = "$pack_name" ] && return 0
    done
    return 1
}

# --- CC Mode resolution ---

CC_MODE="dual"

resolve_cc_mode() {
    if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
        local mode
        mode="$(sed -n 's/^\*\*CC Mode\*\*:[[:space:]]*//p' "$PROJECT_DIR/.agent-local.md" | head -1 | sed 's/<!--.*-->//' | xargs)"
        case "$mode" in
            off|dual|native) CC_MODE="$mode" ;;
            "") CC_MODE="dual" ;;
            *) _warn "  WARNING: Unknown CC Mode '$mode'. Defaulting to 'dual'."; CC_MODE="dual" ;;
        esac
    fi
    echo "  CC Mode: $CC_MODE"
}

# --- Codex Mode resolution ---

CODEX_MODE="native"

resolve_codex_mode() {
    if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
        local mode
        mode="$(sed -n 's/^\*\*Codex Mode\*\*:[[:space:]]*//p' "$PROJECT_DIR/.agent-local.md" | head -1 | sed 's/<!--.*-->//' | xargs)"
        case "$mode" in
            off|legacy|native) CODEX_MODE="$mode" ;;
            "") CODEX_MODE="native" ;;
            *) _warn "  WARNING: Unknown Codex Mode '$mode'. Defaulting to 'native'."; CODEX_MODE="native" ;;
        esac
    fi
    echo "  Codex Mode: $CODEX_MODE"
}

# --- Staleness check (full sync only) ---

CURRENT_HASH=""

check_staleness() {
    echo "Computing staleness hash ..."

    local hash_cmd="shasum"
    command -v shasum &>/dev/null || hash_cmd="sha1sum"
    command -v "$hash_cmd" &>/dev/null || hash_cmd="md5sum"

    local rules_hash=""
    if [ -d "$RULES_HOME/.git" ]; then
        local sub_hash
        sub_hash="$(git -C "$RULES_HOME" submodule status 2>/dev/null | awk '{print $1}' | tr -d '+-U' | sort | tr -d '\n')"
        rules_hash="$(git -C "$RULES_HOME" rev-parse HEAD 2>/dev/null || echo "no-git"):${sub_hash:-no-submodules}"
    else
        rules_hash="$(find "$RULES_HOME" \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.sh' \) -type f -exec "$hash_cmd" {} + 2>/dev/null | sort | "$hash_cmd" | awk '{print $1}')"
    fi

    local overlay_hash
    overlay_hash="$(find "$PROJECT_DIR" -maxdepth 3 -name '.agent-local.md' -not -path '*/.git/*' -not -path '*/node_modules/*' -type f -exec "$hash_cmd" {} + 2>/dev/null | sort | "$hash_cmd" | awk '{print $1}')"

    local reviewer_conf_hash=""
    if [ -f "$PROJECT_DIR/.cursor/reviewer-models.conf" ]; then
        reviewer_conf_hash="$("$hash_cmd" "$PROJECT_DIR/.cursor/reviewer-models.conf" 2>/dev/null | awk '{print $1}')"
    fi
    CURRENT_HASH="${rules_hash}:${overlay_hash}:${reviewer_conf_hash}"

    local stored_hash=""
    [ -f "$HASH_FILE" ] && stored_hash="$(cat "$HASH_FILE")"

    local cursor_exists=false claude_exists=false agents_exists=false
    local skills_ok=true commands_ok=true cursor_agents_ok=true
    [ -d "$PROJECT_DIR/.cursor/rules" ] && [ "$(ls -A "$PROJECT_DIR/.cursor/rules/" 2>/dev/null)" ] && cursor_exists=true
    [ -f "$PROJECT_DIR/.agent-rules/CLAUDE.md" ] && claude_exists=true
    [ -f "$PROJECT_DIR/.agent-rules/AGENTS.md" ] && agents_exists=true

    if [ -f "$SKILLS_MANIFEST" ]; then
        local expected_skill
        for expected_skill in "$RULES_HOME/skills"/*/; do
            [ -d "$expected_skill" ] || continue
            grep -qx "$(basename "$expected_skill")" "$SKILLS_MANIFEST" 2>/dev/null || { skills_ok=false; break; }
        done
        if $skills_ok && [ -d "$RULES_HOME/extras" ]; then
            local extras_dir
            for extras_dir in "$RULES_HOME/extras"/*/; do
                [ -d "$extras_dir/skills" ] || continue
                for expected_skill in "$extras_dir/skills"/*/; do
                    [ -d "$expected_skill" ] || continue
                    grep -qx "$(basename "$expected_skill")" "$SKILLS_MANIFEST" 2>/dev/null || { skills_ok=false; break 2; }
                done
            done
        fi
    else
        [ "$(ls -d "$RULES_HOME/skills/"*/ 2>/dev/null)" ] && skills_ok=false
    fi
    [ -d "$RULES_HOME/commands" ] && [ "$(ls "$RULES_HOME/commands/"*.md 2>/dev/null)" ] && { [ -f "$COMMANDS_MANIFEST" ] || commands_ok=false; }
    [ -d "$RULES_HOME/agents" ] && [ "$(ls "$RULES_HOME/agents/"*.md 2>/dev/null)" ] && { [ -f "$CURSOR_AGENTS_MANIFEST" ] || cursor_agents_ok=false; }

    # Mode-aware required artifacts
    local cc_rules_ok=true codex_config_ok=true
    local claude_required=true agents_required=true
    [ "$CC_MODE" != "off" ] && { [ -d "$PROJECT_DIR/.claude/rules" ] && [ -n "$(ls "$PROJECT_DIR/.claude/rules/"*.md 2>/dev/null)" ] || cc_rules_ok=false; }
    [ "$CODEX_MODE" = "native" ] && { [ -f "$PROJECT_DIR/.codex/config.toml" ] || codex_config_ok=false; }
    [ "$CC_MODE" = "native" ] && [ "$CODEX_MODE" = "off" ] && claude_required=false
    [ "$CODEX_MODE" = "off" ] && agents_required=false

    local legacy_ok=true
    $claude_required && ! $claude_exists && legacy_ok=false
    $agents_required && ! $agents_exists && legacy_ok=false

    if [ "$CURRENT_HASH" = "$stored_hash" ] && $cursor_exists && $legacy_ok && $skills_ok && $commands_ok && $cursor_agents_ok && $cc_rules_ok && $codex_config_ok; then
        _ok "Rules up to date. No sync needed."
        exit 0
    fi
}

store_hash() {
    echo "$CURRENT_HASH" > "$HASH_FILE"
}
