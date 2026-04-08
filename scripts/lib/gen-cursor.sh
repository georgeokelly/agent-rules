# lib/gen-cursor.sh — Cursor-specific generation (rules, skills, commands, agents, worktrees)
# Sourced by agent-sync.sh. Do not execute directly.

generate_cursor() {
    mkdir -p "$PROJECT_DIR/.cursor/rules"
    local frontmatter_dir="$RULES_HOME/templates/cursor-frontmatter"

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
        _warn "        Create one manually: cp \$AGENT_RULES_HOME/templates/overlay-template.md .agent-local.md"
        _warn "        Or ask your AI agent to run the \"project-overlay\" skill for guided setup."
    fi

    echo "  Cursor: $(ls "$PROJECT_DIR/.cursor/rules/"*.mdc 2>/dev/null | wc -l | tr -d ' ') .mdc files"
}

generate_skills() {
    deploy_artifacts "$RULES_HOME/skills" "$PROJECT_DIR/.cursor/skills" "$SKILLS_MANIFEST" "Skills" "dirs"
}

generate_commands() {
    deploy_artifacts "$RULES_HOME/commands" "$PROJECT_DIR/.cursor/commands" "$COMMANDS_MANIFEST" "Commands" "files"
}

generate_cursor_agents() {
    deploy_artifacts "$RULES_HOME/agents" "$PROJECT_DIR/.cursor/agents" "$CURSOR_AGENTS_MANIFEST" "Agents" "files"
}

# --- Reviewer models config ---

REVIEWER_CONF_TEMPLATE="$RULES_HOME/templates/reviewer-models.conf"
REVIEWER_CONF_TARGET="$PROJECT_DIR/.cursor/reviewer-models.conf"
REVIEWER_CONF_STAMP="$PROJECT_DIR/.cursor/.reviewer-models-agent-sync"

deploy_reviewer_models_conf() {
    [ -f "$REVIEWER_CONF_TEMPLATE" ] || return 0
    mkdir -p "$PROJECT_DIR/.cursor"

    if [ -f "$REVIEWER_CONF_TARGET" ] && [ ! -f "$REVIEWER_CONF_STAMP" ]; then
        _warn "  SKIP: .cursor/reviewer-models.conf exists and is not managed by agent-sync."
        _warn "        To let agent-sync manage it, delete it and re-run."
        return 0
    fi

    [ -f "$REVIEWER_CONF_TARGET" ] && [ ! -w "$REVIEWER_CONF_TARGET" ] && rm -f "$REVIEWER_CONF_TARGET"
    cp "$REVIEWER_CONF_TEMPLATE" "$REVIEWER_CONF_TARGET"
    touch "$REVIEWER_CONF_STAMP"
    echo "  Reviewer models: .cursor/reviewer-models.conf deployed"
}

# --- Reviewer variant generation ---

REVIEWER_VARIANTS_MANIFEST="$PROJECT_DIR/.cursor/agents/.generated-reviewers-manifest"

generate_reviewer_variants() {
    local gen_script="$RULES_HOME/scripts/generate-reviewers.sh"
    [ -x "$gen_script" ] || return 0

    local conf_file="$PROJECT_DIR/.cursor/reviewer-models.conf"
    [ -f "$conf_file" ] || [ -f "$REVIEWER_VARIANTS_MANIFEST" ] || return 0

    AGENT_RULES_HOME="$RULES_HOME" "$gen_script" "$PROJECT_DIR"
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
