# lib/sync.sh — Mode reconciliation, sub-repo sync, cleanup remnants
# Sourced by agent-sync.sh. Do not execute directly.

# HIST-003 orphan (GPT-5.4 M1 refinement): pre-refactor agent-sync deployed CC
# commands via deploy_artifacts in "files" mode and recorded each filename in
# .agent-sync-commands-manifest. We now clean **only** the files listed in that
# manifest, then the manifest itself, then attempt rmdir (which succeeds only
# if the directory is empty — i.e. user added no files of their own).
#
# Ownership matrix:
#   (a) No manifest present            → no-op (user-authored commands/, honored)
#   (b) Manifest present, no user adds → all listed files + manifest removed,
#                                         directory removed cleanly
#   (c) Manifest present, user added   → listed files + manifest removed, but
#                                         user-added files (and containing dir)
#                                         preserved
#
# Fresh projects (never had agent-sync-managed commands) are always case (a),
# so this is a no-op for them. Also called from do_clean() in clean.sh and
# from the cc / cc-rules / cc-skills subcommands in agent-sync.sh.
cleanup_legacy_cc_commands() {
    local commands_dir="$PROJECT_DIR/.claude/commands"
    local stamp="$commands_dir/.agent-sync-commands-manifest"
    [ -f "$stamp" ] || return 0

    local removed=0 item
    while IFS= read -r item; do
        [ -z "$item" ] && continue
        if [ -e "$commands_dir/$item" ]; then
            rm -f "$commands_dir/$item"
            removed=$((removed + 1))
        fi
    done < "$stamp"

    rm -f "$stamp"

    # rmdir succeeds only when the directory is empty — i.e. the user did not
    # add any of their own files. Failure here is the mixed-ownership case and
    # is intentionally silent; we keep user content untouched.
    if rmdir "$commands_dir" 2>/dev/null; then
        echo "  Removed legacy .claude/commands/ ($removed file(s) decommissioned, HIST-003)"
    else
        echo "  Removed $removed agent-sync-managed file(s) from .claude/commands/ (user-added files preserved, HIST-003)"
    fi
}

# Remove artifacts from modes that are now disabled (convergent sync).
reconcile_mode_outputs() {
    # Always opportunistic: decommissioned subsystems never come back, so we
    # can clean their remnants regardless of CC_MODE.
    cleanup_legacy_cc_commands

    if [ "$CC_MODE" = "off" ]; then
        if [ -f "$CC_RULES_MANIFEST" ] || [ -f "$CC_SKILLS_MANIFEST" ] || [ -f "$CC_SUBAGENTS_MANIFEST" ]; then
            echo "  Reconciling CC Mode=off: removing .claude/ artifacts..."
            clean_manifest "$CC_RULES_MANIFEST" "$PROJECT_DIR/.claude/rules" "files"
            rmdir "$PROJECT_DIR/.claude/rules" 2>/dev/null || true
            clean_manifest "$CC_SKILLS_MANIFEST" "$PROJECT_DIR/.claude/skills" "dirs"
            rmdir "$PROJECT_DIR/.claude/skills" 2>/dev/null || true
            # HIST-006: CC subagents follow the same off-mode reconciliation.
            clean_manifest "$CC_SUBAGENTS_MANIFEST" "$PROJECT_DIR/.claude/agents" "files"
            rmdir "$PROJECT_DIR/.claude/agents" 2>/dev/null || true
            rmdir "$PROJECT_DIR/.claude" 2>/dev/null || true
        fi
    fi

    if [ "$CODEX_MODE" = "off" ]; then
        # HIST-007: AGENTS.override.md is the new entry point. Also keep
        # sweeping .agent-rules/AGENTS.md for upgrade compatibility.
        rm -f "$PROJECT_DIR/AGENTS.override.md"
        rm -f "$PROJECT_DIR/.agent-rules/AGENTS.md"
        if [ -f "$CODEX_CONFIG_STAMP" ]; then
            rm -f "$PROJECT_DIR/.codex/config.toml" "$CODEX_CONFIG_STAMP"
            rmdir "$PROJECT_DIR/.codex" 2>/dev/null || true
        fi
        clean_manifest "$CODEX_SKILLS_MANIFEST" "$PROJECT_DIR/.agents/skills" "dirs"
        rmdir "$PROJECT_DIR/.agents/skills" 2>/dev/null || true
        # HIST-006: Codex subagent cleanup parity with the legacy branch.
        if [ -f "$CODEX_SUBAGENTS_MANIFEST" ]; then
            clean_manifest "$CODEX_SUBAGENTS_MANIFEST" "$PROJECT_DIR/.agents/agents" "files"
            rmdir "$PROJECT_DIR/.agents/agents" 2>/dev/null || true
        fi
        rmdir "$PROJECT_DIR/.agents" 2>/dev/null || true
    fi

    if [ "$CODEX_MODE" = "legacy" ]; then
        if [ -f "$CODEX_CONFIG_STAMP" ]; then
            rm -f "$PROJECT_DIR/.codex/config.toml" "$CODEX_CONFIG_STAMP"
            rmdir "$PROJECT_DIR/.codex" 2>/dev/null || true
        fi
        clean_manifest "$CODEX_SKILLS_MANIFEST" "$PROJECT_DIR/.agents/skills" "dirs"
        rmdir "$PROJECT_DIR/.agents/skills" 2>/dev/null || true
        # HIST-006: Codex subagents live in .agents/agents/ (sibling of
        # .agents/skills/). Legacy mode drops every .agents/ artifact too.
        if [ -f "$CODEX_SUBAGENTS_MANIFEST" ]; then
            clean_manifest "$CODEX_SUBAGENTS_MANIFEST" "$PROJECT_DIR/.agents/agents" "files"
            rmdir "$PROJECT_DIR/.agents/agents" 2>/dev/null || true
        fi
        rmdir "$PROJECT_DIR/.agents" 2>/dev/null || true
    fi

    # HIST-006: OpenCode off-mode reconciliation. opencode.json removal is
    # marker-gated so a user-authored config is never deleted; .opencode/
    # subtrees are manifest-gated so user-added files under them are
    # preserved while agent-sync-managed artifacts disappear.
    if [ "${OPENCODE_MODE:-native}" = "off" ]; then
        if [ -f "$PROJECT_DIR/opencode.json" ] && grep -q "$OPENCODE_MARKER" "$PROJECT_DIR/opencode.json" 2>/dev/null; then
            rm -f "$PROJECT_DIR/opencode.json"
            echo "  Reconciled OpenCode Mode=off: removed opencode.json"
        fi
        if [ -f "$OPENCODE_SKILLS_MANIFEST" ] || [ -f "$OPENCODE_SUBAGENTS_MANIFEST" ]; then
            echo "  Reconciling OpenCode Mode=off: removing .opencode/ artifacts..."
            clean_manifest "$OPENCODE_SKILLS_MANIFEST" "$PROJECT_DIR/.opencode/skills" "dirs"
            rmdir "$PROJECT_DIR/.opencode/skills" 2>/dev/null || true
            clean_manifest "$OPENCODE_SUBAGENTS_MANIFEST" "$PROJECT_DIR/.opencode/agent" "files"
            rmdir "$PROJECT_DIR/.opencode/agent" 2>/dev/null || true
            rmdir "$PROJECT_DIR/.opencode" 2>/dev/null || true
        fi
    fi
}

cleanup_remnants() {
    # HIST-007: root AGENTS.md / CLAUDE.md must not coexist with the new
    # AGENTS.override.md entry — Cursor would auto-inject them as
    # always_applied_workspace_rules and duplicate every rule already
    # carried by .cursor/rules/*.mdc. AGENTS.override.md is exempt:
    # Cursor's auto-injection list is hard-coded to AGENTS.md/CLAUDE.md.
    rm -f "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/AGENTS.md"

    # HIST-004 carry-over: pre-HIST-004 agent-sync wrote .agent-rules/CLAUDE.md.
    # HIST-007 follow-up: pre-HIST-007 agent-sync wrote .agent-rules/AGENTS.md.
    # Both paths are now obsolete; sweep them on every sync so upgrading
    # projects don't keep stale artifacts until the user runs
    # `agent-sync clean`. The directory itself is rmdir'd if it ends up
    # empty (rmdir is a no-op on non-empty dirs, so user-added files survive).
    rm -f "$PROJECT_DIR/.agent-rules/CLAUDE.md" "$PROJECT_DIR/.agent-rules/AGENTS.md"
    rmdir "$PROJECT_DIR/.agent-rules" 2>/dev/null || true
}

sync_sub_repos() {
    local manifest_new="$MANIFEST.new"
    : > "$manifest_new"

    local sub_overlay sub_dir sub_rel sub_agents_override mdc_name mdc_target overlay_bytes
    while read -r sub_overlay; do
        sub_dir="$(dirname "$sub_overlay")"
        sub_rel="${sub_dir#"$PROJECT_DIR"/}"

        # HIST-007: sub-repo overlay file renamed from AGENTS.md to
        # AGENTS.override.md so Cursor's nested-AGENTS.md auto-injection
        # stops duplicating the same content that already arrives via
        # .cursor/rules/<sub_rel>-overlay.mdc. Codex still picks
        # AGENTS.override.md first (highest precedence in its own dir).
        # Pre-HIST-007 deployments left a sub-repo AGENTS.md behind —
        # unconditional rm -f sweeps it on every sync (B1 strategy:
        # agent-sync owns this file outright).
        sub_agents_override="$sub_dir/AGENTS.override.md"
        if [ "$CODEX_MODE" != "off" ]; then
            {
                echo "<!-- Auto-generated by agent-sync for Codex (sub-repo overlay only). Do not edit manually. -->"
                echo ""
                strip_html_comments < "$sub_overlay"
            } > "$sub_agents_override"
        else
            rm -f "$sub_agents_override"
        fi
        # Migration sweep: pre-HIST-007 AGENTS.md and pre-HIST-004 CLAUDE.md.
        rm -f "$sub_dir/AGENTS.md" "$sub_dir/CLAUDE.md"

        mdc_name="$(echo "$sub_rel" | tr '/' '-')-overlay.mdc"
        mdc_target="$PROJECT_DIR/.cursor/rules/$mdc_name"
        {
            echo "---"
            echo "description: ${sub_rel} project overlay"
            echo "globs: ${sub_rel}/**"
            echo "alwaysApply: false"
            echo "---"
            echo ""
            strip_html_comments < "$sub_overlay"
        } > "$mdc_target"

        if [ "$CC_MODE" != "off" ]; then
            local cc_overlay_name cc_overlay_target
            cc_overlay_name="$(echo "$sub_rel" | tr '/' '-')-overlay.md"
            cc_overlay_target="$PROJECT_DIR/.claude/rules/$cc_overlay_name"
            {
                echo "---"
                echo "globs: \"${sub_rel}/**\""
                echo "---"
                echo ""
                strip_html_comments < "$sub_overlay"
            } > "$cc_overlay_target"
        fi

        overlay_bytes=$(wc -c < "$sub_overlay" | tr -d ' ')
        echo "$sub_rel" >> "$manifest_new"
        echo "  Sub-repo $sub_rel: ${mdc_name} + overlays (source $overlay_bytes bytes)"
    done < <(find "$PROJECT_DIR" -mindepth 2 -maxdepth 3 -name '.agent-local.md' -not -path '*/.git/*' -not -path '*/node_modules/*')

    if [ -f "$MANIFEST" ]; then
        local old_rel ghost_mdc ghost_cc
        while IFS= read -r old_rel; do
            if [ ! -f "$PROJECT_DIR/$old_rel/.agent-local.md" ]; then
                # HIST-007: clean both the new override.md target and any
                # pre-HIST-007/004 AGENTS.md / CLAUDE.md leftovers.
                rm -f "$PROJECT_DIR/$old_rel/AGENTS.override.md" \
                      "$PROJECT_DIR/$old_rel/AGENTS.md" \
                      "$PROJECT_DIR/$old_rel/CLAUDE.md"
                ghost_mdc="$(echo "$old_rel" | tr '/' '-')-overlay.mdc"
                rm -f "$PROJECT_DIR/.cursor/rules/$ghost_mdc"
                ghost_cc="$(echo "$old_rel" | tr '/' '-')-overlay.md"
                rm -f "$PROJECT_DIR/.claude/rules/$ghost_cc"
                echo "  Cleaned ghost rules: $old_rel/ (overlay removed)"
            fi
        done < "$MANIFEST"
    fi
    mv "$manifest_new" "$MANIFEST"
}
