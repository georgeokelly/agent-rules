# lib/gen-claude.sh — Claude Code native generation (.claude/rules/, skills/)
# Sourced by agent-sync.sh. Do not execute directly.
#
# HIST-004: legacy .agent-rules/CLAUDE.md generation was decommissioned.
# Claude Code v2.0.64+ discovers rules natively via .claude/rules/*.md, so
# the monolithic CLAUDE.md is redundant. See issue_history/HISTORY.md.

# Generate CC-native .claude/rules/*.md files.
# Rule categories:
#   A (always-on): core rules — no frontmatter in CC (always loaded)
#   B (path-scoped): packs with globs — CC uses globs: from cc-frontmatter/
#   C (description-only): packs with only description — always-on in CC
generate_cc_rules() {
    mkdir -p "$PROJECT_DIR/.claude/rules"

    local cc_fm_dir="$RULES_HOME/templates/cc-frontmatter"
    local manifest_new="${CC_RULES_MANIFEST}.new"
    : > "$manifest_new"

    local rule_file basename_no_ext lookup_name target count=0
    for rule_file in "$RULES_HOME"/core/*.md "$RULES_HOME"/packs/*.md; do
        [ -f "$rule_file" ] || continue
        basename_no_ext="$(basename "$rule_file" .md)"
        if [[ "$rule_file" == */packs/* ]]; then
            pack_is_active "$basename_no_ext" || continue
        fi

        lookup_name="$(echo "$basename_no_ext" | sed 's/^[0-9]*-//')"
        target="$PROJECT_DIR/.claude/rules/${basename_no_ext}.md"

        if [ -f "$cc_fm_dir/${lookup_name}.yaml" ]; then
            echo "---" > "$target"
            cat "$cc_fm_dir/${lookup_name}.yaml" >> "$target"
            echo "---" >> "$target"
            echo "" >> "$target"
        else
            : > "$target"
        fi
        cat "$rule_file" >> "$target"

        echo "${basename_no_ext}.md" >> "$manifest_new"
        count=$((count + 1))
    done

    if [ -f "$PROJECT_DIR/.agent-local.md" ]; then
        target="$PROJECT_DIR/.claude/rules/project-overlay.md"
        strip_html_comments < "$PROJECT_DIR/.agent-local.md" > "$target"
        echo "project-overlay.md" >> "$manifest_new"
        count=$((count + 1))
    fi

    if [ -f "$CC_RULES_MANIFEST" ]; then
        local old_rule
        while IFS= read -r old_rule; do
            [ -z "$old_rule" ] && continue
            if ! grep -qx "$old_rule" "$manifest_new" 2>/dev/null; then
                rm -f "$PROJECT_DIR/.claude/rules/$old_rule"
                echo "  Removed stale CC rule: $old_rule"
            fi
        done < "$CC_RULES_MANIFEST"
    fi

    mv "$manifest_new" "$CC_RULES_MANIFEST"
    echo "  CC Rules: $count .md files in .claude/rules/"
}

generate_cc_skills() {
    deploy_artifacts "$RULES_HOME/skills" "$PROJECT_DIR/.claude/skills" "$CC_SKILLS_MANIFEST" "CC Skills"
}
