# lib/gen-cursor.sh — Cursor-specific generation (rules, skills, worktrees)
# Sourced by agent-sync.sh. Do not execute directly.

generate_cursor() {
    mkdir -p "$PROJECT_DIR/.cursor/rules"
    # One-shot orphan cleanup for HIST-003 (commands/review decommission):
    # core/30-review-criteria.md is gone, but pre-refactor deployments still
    # carry the generated .mdc. This file is 100% agent-sync-managed (not in
    # the user-managed path-set we intentionally protect), so unconditional
    # removal is safe and non-destructive for fresh projects where the file
    # never existed.
    rm -f "$PROJECT_DIR/.cursor/rules/30-review-criteria.mdc" 2>/dev/null || true
    local frontmatter_dir="$RULES_HOME/templates/rule_templates/cursor_frontmatter"

    local rule_file basename_no_ext lookup_name target
    for rule_file in "$RULES_HOME"/core/*.md "$RULES_HOME"/packs/*.md; do
        [ -f "$rule_file" ] || continue
        basename_no_ext="$(basename "$rule_file" .md)"
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
        _warn "  NOTE: No .agent-local.md found. Project overlay skipped."
        _warn "        Create one manually: cp \$AGENT_TOOLKIT_HOME/templates/overlay-template.md .agent-local.md"
        _warn "        Or ask your AI agent to run the \"project-overlay\" skill for guided setup."
    fi

    echo "  Cursor: $(ls "$PROJECT_DIR/.cursor/rules/"*.mdc 2>/dev/null | wc -l | tr -d ' ') .mdc files"
}

generate_skills() {
    deploy_artifacts "$RULES_HOME/skills" "$PROJECT_DIR/.cursor/skills" "$SKILLS_MANIFEST" "Skills"
}

# Cursor subagents (HIST-006, skeleton). Source:
#   $RULES_HOME/subagents/cursor/<name>.md        (core)
#   $RULES_HOME/extras/<bundle>/subagents/cursor/<name>.md  (optional)
# Target: $PROJECT_DIR/.cursor/agents/<prefix><name>.md
#
# deploy_subagent_files is a no-op when both sources are empty/missing,
# so this is safe to call on every full sync even before any Cursor
# subagent files exist in the repo. When files are eventually authored,
# they deploy without any further changes to agent-sync.
generate_cursor_subagents() {
    deploy_subagent_files "$RULES_HOME/subagents/cursor" "$PROJECT_DIR/.cursor/agents" "$CURSOR_SUBAGENTS_MANIFEST" "Cursor Subagents"
}

# --- Worktrees deployment ---

WORKTREES_TEMPLATE="$RULES_HOME/templates/worktrees.json"
WORKTREES_TARGET="$PROJECT_DIR/.cursor/worktrees.json"
WORKTREES_STAMP="$PROJECT_DIR/.cursor/.worktrees-agent-sync"

generate_worktrees() {
    [ -f "$WORKTREES_TEMPLATE" ] || return 0
    mkdir -p "$PROJECT_DIR/.cursor"

    if [ -f "$WORKTREES_TARGET" ] && [ ! -f "$WORKTREES_STAMP" ]; then
        _warn "  SKIP: .cursor/worktrees.json exists and is not managed by agent-sync."
        _warn "        To let agent-sync manage it, delete it and re-run."
        return 0
    fi

    [ -f "$WORKTREES_TARGET" ] && [ ! -w "$WORKTREES_TARGET" ] && rm -f "$WORKTREES_TARGET"
    cp "$WORKTREES_TEMPLATE" "$WORKTREES_TARGET"
    touch "$WORKTREES_STAMP"
    echo "  Worktrees: .cursor/worktrees.json deployed"
}
