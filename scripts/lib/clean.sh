# lib/clean.sh — Full cleanup of all generated files
# Sourced by agent-sync.sh. Do not execute directly.

do_clean() {
    echo "Cleaning generated files in $PROJECT_DIR ..."

    if [ -d "$PROJECT_DIR/.cursor/rules" ]; then
        rm -f "$PROJECT_DIR/.cursor/rules/"*.mdc
        rmdir "$PROJECT_DIR/.cursor/rules" 2>/dev/null || true
        echo "  Removed .cursor/rules/*.mdc"
    fi

    if [ -f "$SKILLS_MANIFEST" ]; then
        clean_manifest "$SKILLS_MANIFEST" "$PROJECT_DIR/.cursor/skills" "dirs"
        rmdir "$PROJECT_DIR/.cursor/skills" 2>/dev/null || true
        echo "  Removed agent-sync managed skills"
    elif [ -d "$PROJECT_DIR/.cursor/skills" ]; then
        _warn "  WARNING: .cursor/skills/ exists but no manifest found."
    fi

    # HIST-006: Cursor subagents under .cursor/agents/. Manifest-gated so
    # user-authored files under .cursor/agents/ (unrelated to agent-sync)
    # remain untouched.
    if [ -f "$CURSOR_SUBAGENTS_MANIFEST" ]; then
        clean_manifest "$CURSOR_SUBAGENTS_MANIFEST" "$PROJECT_DIR/.cursor/agents" "files"
        rmdir "$PROJECT_DIR/.cursor/agents" 2>/dev/null || true
        echo "  Removed agent-sync managed Cursor subagents"
    fi

    if [ -f "$PROJECT_DIR/.cursor/.worktrees-agent-sync" ]; then
        rm -f "$PROJECT_DIR/.cursor/worktrees.json" "$PROJECT_DIR/.cursor/.worktrees-agent-sync"
        echo "  Removed .cursor/worktrees.json (agent-sync managed)"
    elif [ -f "$PROJECT_DIR/.cursor/worktrees.json" ]; then
        _warn "  SKIP: .cursor/worktrees.json is not managed by agent-sync — left intact."
    fi

    # HIST-003 GLM-m3: pre-refactor agent-sync generated .cursor/reviewer-models.conf
    # and stamped it with .cursor/.reviewer-models-agent-sync. The .conf file is now
    # user-managed (see README §9 migration), but the stamp is a pure agent-sync
    # artifact with no user-facing value — leaving it behind creates an orphan that
    # misleads future deployments into thinking .conf is still agent-sync-owned.
    rm -f "$PROJECT_DIR/.cursor/.reviewer-models-agent-sync" 2>/dev/null || true

    rmdir "$PROJECT_DIR/.cursor" 2>/dev/null || true

    # CC native files
    if [ -f "$CC_RULES_MANIFEST" ]; then
        clean_manifest "$CC_RULES_MANIFEST" "$PROJECT_DIR/.claude/rules" "files"
        rmdir "$PROJECT_DIR/.claude/rules" 2>/dev/null || true
        echo "  Removed agent-sync managed CC rules"
    elif [ -d "$PROJECT_DIR/.claude/rules" ]; then
        _warn "  WARNING: .claude/rules/ exists but no manifest found."
    fi

    if [ -f "$CC_SKILLS_MANIFEST" ]; then
        clean_manifest "$CC_SKILLS_MANIFEST" "$PROJECT_DIR/.claude/skills" "dirs"
        rmdir "$PROJECT_DIR/.claude/skills" 2>/dev/null || true
        echo "  Removed agent-sync managed CC skills"
    elif [ -d "$PROJECT_DIR/.claude/skills" ]; then
        _warn "  WARNING: .claude/skills/ exists but no manifest found."
    fi

    # HIST-006: CC subagents under .claude/agents/.
    if [ -f "$CC_SUBAGENTS_MANIFEST" ]; then
        clean_manifest "$CC_SUBAGENTS_MANIFEST" "$PROJECT_DIR/.claude/agents" "files"
        rmdir "$PROJECT_DIR/.claude/agents" 2>/dev/null || true
        echo "  Removed agent-sync managed CC subagents"
    fi

    # HIST-003: remove stamp-gated legacy .claude/commands/ so rmdir .claude
    # below does not silently fail on pre-refactor deployments.
    cleanup_legacy_cc_commands

    rmdir "$PROJECT_DIR/.claude" 2>/dev/null || true

    # Codex native files
    if [ -f "$CODEX_CONFIG_STAMP" ]; then
        rm -f "$PROJECT_DIR/.codex/config.toml" "$CODEX_CONFIG_STAMP"
        echo "  Removed .codex/config.toml (agent-sync managed)"
    elif [ -f "$PROJECT_DIR/.codex/config.toml" ]; then
        _warn "  SKIP: .codex/config.toml is not managed by agent-sync — left intact."
    fi

    if [ -f "$CODEX_SKILLS_MANIFEST" ]; then
        clean_manifest "$CODEX_SKILLS_MANIFEST" "$PROJECT_DIR/.agents/skills" "dirs"
        rmdir "$PROJECT_DIR/.agents/skills" 2>/dev/null || true
        echo "  Removed agent-sync managed Codex skills"
    elif [ -d "$PROJECT_DIR/.agents/skills" ]; then
        _warn "  WARNING: .agents/skills/ exists but no manifest found."
    fi

    # HIST-006: Codex subagents under .agents/agents/.
    if [ -f "$CODEX_SUBAGENTS_MANIFEST" ]; then
        clean_manifest "$CODEX_SUBAGENTS_MANIFEST" "$PROJECT_DIR/.agents/agents" "files"
        rmdir "$PROJECT_DIR/.agents/agents" 2>/dev/null || true
        echo "  Removed agent-sync managed Codex subagents"
    fi

    rmdir "$PROJECT_DIR/.agents" 2>/dev/null || true
    rmdir "$PROJECT_DIR/.codex" 2>/dev/null || true

    # HIST-006: OpenCode cleanup.
    # opencode.json removal is marker-gated ("_generated_by": "agent-sync")
    # so a user-authored config is preserved.
    if [ -f "$PROJECT_DIR/opencode.json" ] && grep -q '"_generated_by": "agent-sync"' "$PROJECT_DIR/opencode.json" 2>/dev/null; then
        rm -f "$PROJECT_DIR/opencode.json"
        echo "  Removed opencode.json (agent-sync managed)"
    elif [ -f "$PROJECT_DIR/opencode.json" ]; then
        _warn "  SKIP: opencode.json is not managed by agent-sync — left intact."
    fi

    if [ -f "$OPENCODE_SKILLS_MANIFEST" ]; then
        clean_manifest "$OPENCODE_SKILLS_MANIFEST" "$PROJECT_DIR/.opencode/skills" "dirs"
        rmdir "$PROJECT_DIR/.opencode/skills" 2>/dev/null || true
        echo "  Removed agent-sync managed OpenCode skills"
    elif [ -d "$PROJECT_DIR/.opencode/skills" ]; then
        _warn "  WARNING: .opencode/skills/ exists but no manifest found."
    fi

    if [ -f "$OPENCODE_SUBAGENTS_MANIFEST" ]; then
        clean_manifest "$OPENCODE_SUBAGENTS_MANIFEST" "$PROJECT_DIR/.opencode/agent" "files"
        rmdir "$PROJECT_DIR/.opencode/agent" 2>/dev/null || true
        echo "  Removed agent-sync managed OpenCode subagents"
    fi

    rmdir "$PROJECT_DIR/.opencode" 2>/dev/null || true

    # HIST-007: root AGENTS.override.md is the Codex-exclusive entry point.
    # Always remove on clean; it is unconditionally agent-sync-managed
    # (no marker check — unlike opencode.json — because pre-HIST-007
    # users never wrote to this filename, and post-HIST-007 it is solely
    # a generated artifact).
    rm -f "$PROJECT_DIR/AGENTS.override.md"
    echo "  Removed AGENTS.override.md"

    # HIST-007 carry-over: old .agent-rules/ self-built directory.
    if [ -d "$PROJECT_DIR/.agent-rules" ]; then
        rm -rf "$PROJECT_DIR/.agent-rules"
        echo "  Removed .agent-rules/ (legacy)"
    fi

    rm -f "$HASH_FILE"
    echo "  Removed .agent-sync-hash"

    # Sub-repo cleanup (HIST-007 expanded: AGENTS.override.md added; old
    # AGENTS.md / CLAUDE.md kept in the sweep for upgrade compatibility).
    if [ -f "$MANIFEST" ]; then
        local old_rel ghost_mdc ghost_cc
        while IFS= read -r old_rel; do
            rm -f "$PROJECT_DIR/$old_rel/AGENTS.override.md" \
                  "$PROJECT_DIR/$old_rel/AGENTS.md" \
                  "$PROJECT_DIR/$old_rel/CLAUDE.md"
            ghost_mdc="$(echo "$old_rel" | tr '/' '-')-overlay.mdc"
            rm -f "$PROJECT_DIR/.cursor/rules/$ghost_mdc"
            ghost_cc="$(echo "$old_rel" | tr '/' '-')-overlay.md"
            rm -f "$PROJECT_DIR/.claude/rules/$ghost_cc"
            echo "  Removed sub-repo rules: $old_rel/"
        done < "$MANIFEST"
    fi
    rm -f "$MANIFEST"
    echo "  Removed .agent-sync-manifest"

    # Fallback: scan for orphaned auto-generated files (sub-repos that left
    # the manifest before clean ran). HIST-007: include AGENTS.override.md.
    find "$PROJECT_DIR" -mindepth 2 -maxdepth 4 \
        \( -name 'CLAUDE.md' -o -name 'AGENTS.md' -o -name 'AGENTS.override.md' \) \
        -not -path '*/.git/*' -not -path '*/.agent-rules/*' \
        -not -path '*/node_modules/*' -type f | while read -r stale_file; do
        if head -1 "$stale_file" 2>/dev/null | grep -q '<!-- Auto-generated by agent-sync'; then
            rm -f "$stale_file"
            echo "  Removed orphan: ${stale_file#"$PROJECT_DIR"/}"
        fi
    done

    # Final root sweep for stale CLAUDE.md / AGENTS.md (pre-HIST-007 mounts).
    rm -f "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/AGENTS.md"

    _ok "Clean complete."
}
