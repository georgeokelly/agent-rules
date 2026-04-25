# lib/common.sh — Output helpers, HTML stripping, generic artifact deployment
# Sourced by agent-sync.sh. Do not execute directly.

# Terminal colors (disabled when stdout is not a TTY)
if [ -t 1 ]; then
    _R='\033[0;31m' _Y='\033[0;33m' _G='\033[0;32m' _N='\033[0m'
else
    _R='' _Y='' _G='' _N=''
fi
_err()  { printf '%b%s%b\n' "$_R" "$*" "$_N"; }
_warn() { printf '%b%s%b\n' "$_Y" "$*" "$_N"; }
_ok()   { printf '%b%s%b\n' "$_G" "$*" "$_N"; }

strip_html_comments() {
    perl -0777 -pe 's/<!--.*?-->\n?//gs' 2>/dev/null \
        || python3 -c "
import re, sys
text = sys.stdin.read()
print(re.sub(r'<!--.*?-->\n?', '', text, flags=re.DOTALL), end='')
" 2>/dev/null \
        || cat
}

# --- Skill prefix frontmatter rewriter (HIST-005) ---
# Rewrites a deployed SKILL.md's frontmatter `name:` value to include
# $SKILL_PREFIX. Idempotent: skips if the current name already starts with the
# prefix. Uses perl -i for portable in-place editing (macOS BSD sed and GNU sed
# disagree on the `-i` argument; perl is consistent on both). Falls back to
# python3 if perl is unavailable. Only rewrites the first `^name:` match —
# YAML frontmatter always sits at the top, so this avoids touching literal
# `name:` strings that may appear in the skill's body text.
# Args: $1=skill_dir
_apply_skill_prefix() {
    local skill_file="$1/SKILL.md"
    [ -n "${SKILL_PREFIX:-}" ] || return 0
    [ -f "$skill_file" ] || return 0

    SKILL_PREFIX="$SKILL_PREFIX" perl -i -pe '
        BEGIN { $done = 0 }
        if (!$done && /^name:\s*(\S.*?)\s*$/) {
            my $name = $1;
            my $p = $ENV{SKILL_PREFIX};
            $_ = "name: ${p}${name}\n" unless index($name, $p) == 0;
            $done = 1;
        }
    ' "$skill_file" 2>/dev/null && return 0

    SKILL_PREFIX="$SKILL_PREFIX" python3 - "$skill_file" <<'PY' 2>/dev/null
import os, re, sys
path = sys.argv[1]
prefix = os.environ["SKILL_PREFIX"]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()
def sub(m):
    name = m.group(1).strip()
    return m.group(0) if name.startswith(prefix) else f"name: {prefix}{name}"
new = re.sub(r"^name:\s*(\S.*?)\s*$", sub, text, count=1, flags=re.MULTILINE)
if new != text:
    with open(path, "w", encoding="utf-8") as f:
        f.write(new)
PY
}

# --- Generic artifact deployment ---
# Deploys skill-style directory artifacts from core + extras to target. Handles
# core-priority conflict resolution and manifest-based stale cleanup. The only
# live callers sync skill directories (see generate_skills / generate_cc_skills
# / generate_codex_skills). The former `files` mode (flat *.md) was used by the
# decommissioned commands/ subsystem and has been removed — a future flat
# deployer, if needed, should add a dedicated helper rather than re-introduce a
# mode switch (YAGNI; git history preserves the previous implementation).
#
# HIST-005: when $SKILL_PREFIX is non-empty, each deployed item's target name
# and SKILL.md frontmatter `name:` are prefixed (e.g. 'pre-commit' →
# 'gla-pre-commit'). Manifests record the prefixed names, so stale cleanup
# tracks target-side identity (including when the user toggles the overlay
# opt-out on/off between syncs).
#
# Args: $1=src_dir $2=target_dir $3=manifest_file $4=label
deploy_artifacts() {
    local src_dir="$1" target_dir="$2" manifest_file="$3" label="$4"
    local prefix="${SKILL_PREFIX:-}"
    [ -d "$src_dir" ] || return 0

    local count=0
    local manifest_new="${manifest_file}.new"
    mkdir -p "$target_dir"
    : > "$manifest_new"

    local item item_name item_target_name item_target
    for item in "$src_dir"/*/; do
        [ -d "$item" ] || continue
        item_name="$(basename "$item")"
        item_target_name="${prefix}${item_name}"
        item_target="$target_dir/$item_target_name"
        rm -rf "$item_target"
        mkdir -p "$item_target"
        [ -n "$(ls -A "$item" 2>/dev/null)" ] && cp -a "$item/." "$item_target/"
        _apply_skill_prefix "$item_target"
        echo "$item_target_name" >> "$manifest_new"
        count=$((count + 1))
    done

    # Deploy from extras/ — core takes priority. extras/ items are prefixed by
    # the same rule as core (HIST-005 assumption: all skill sources share one
    # naming convention under agent-toolkit's deploy pipeline).
    local src_type
    src_type="$(basename "$src_dir")"
    if [ -d "$RULES_HOME/extras" ]; then
        local extras_dir bundle_name extras_sub
        for extras_dir in "$RULES_HOME/extras"/*/; do
            extras_sub="$extras_dir$src_type"
            [ -d "$extras_sub" ] || continue
            bundle_name="$(basename "$extras_dir")"
            for item in "$extras_sub"/*/; do
                [ -d "$item" ] || continue
                item_name="$(basename "$item")"
                if [ -d "$src_dir/$item_name" ]; then
                    _warn "  SKIP: extras/$bundle_name $src_type '$item_name' — same name exists in core (core wins)"
                    continue
                fi
                item_target_name="${prefix}${item_name}"
                item_target="$target_dir/$item_target_name"
                rm -rf "$item_target"
                mkdir -p "$item_target"
                [ -n "$(ls -A "$item" 2>/dev/null)" ] && cp -a "$item/." "$item_target/"
                _apply_skill_prefix "$item_target"
                echo "$item_target_name" >> "$manifest_new"
                count=$((count + 1))
            done
        done
    fi

    # Remove directories that were previously synced but no longer exist.
    if [ -f "$manifest_file" ]; then
        local old_item
        while IFS= read -r old_item; do
            [ -z "$old_item" ] && continue
            if ! grep -qx "$old_item" "$manifest_new" 2>/dev/null; then
                rm -rf "$target_dir/$old_item"
                echo "  Removed stale $label: $old_item"
            fi
        done < "$manifest_file"
    fi

    mv "$manifest_new" "$manifest_file"
    echo "  $label: $count item(s) synced to ${target_dir#"$PROJECT_DIR"/}/"
}

# --- Subagent prefix rewriter (HIST-006) ---
# Mirrors _apply_skill_prefix for single-file subagent sources. Both YAML
# frontmatter (markdown / `.yaml`) and TOML assignments (`name = "..."`)
# get the first `name` value prefixed; idempotent for already-prefixed names.
# Non-matching files (no `name` in the first few lines) are left untouched —
# agent-toolkit does not require every subagent to declare one, but the
# prefix is applied whenever it does.
# Args: $1=file_path $2=extension(md|yaml|yml|toml)
_apply_subagent_prefix() {
    local file="$1" ext="$2"
    [ -n "${SKILL_PREFIX:-}" ] || return 0
    [ -f "$file" ] || return 0

    case "$ext" in
        md|yaml|yml)
            SKILL_PREFIX="$SKILL_PREFIX" perl -i -pe '
                BEGIN { $done = 0 }
                if (!$done && /^name:\s*(\S.*?)\s*$/) {
                    my $name = $1;
                    my $p = $ENV{SKILL_PREFIX};
                    $_ = "name: ${p}${name}\n" unless index($name, $p) == 0;
                    $done = 1;
                }
            ' "$file" 2>/dev/null && return 0

            SKILL_PREFIX="$SKILL_PREFIX" python3 - "$file" <<'PY' 2>/dev/null
import os, re, sys
path = sys.argv[1]
prefix = os.environ["SKILL_PREFIX"]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()
def sub(m):
    name = m.group(1).strip()
    return m.group(0) if name.startswith(prefix) else f"name: {prefix}{name}"
new = re.sub(r"^name:\s*(\S.*?)\s*$", sub, text, count=1, flags=re.MULTILINE)
if new != text:
    with open(path, "w", encoding="utf-8") as f:
        f.write(new)
PY
            ;;
        toml)
            SKILL_PREFIX="$SKILL_PREFIX" perl -i -pe '
                BEGIN { $done = 0 }
                if (!$done && /^name\s*=\s*"([^"]+)"\s*$/) {
                    my $name = $1;
                    my $p = $ENV{SKILL_PREFIX};
                    $_ = "name = \"${p}${name}\"\n" unless index($name, $p) == 0;
                    $done = 1;
                }
            ' "$file" 2>/dev/null || true
            ;;
    esac
}

# --- Flat subagent file deployment (HIST-006) ---
# Complements deploy_artifacts() (which handles directory-based skills). A
# subagent source is one file per agent: `subagents/<tool>/<name>.<ext>`
# (ext = md for Claude/Cursor/OpenCode, toml for Codex's TOML-based config).
#
# Target: `target_dir/<prefix><name>.<ext>`. Prefix behavior matches skill
# deployment (HIST-005) so a project's `/gla-*` convention extends uniformly
# from skills to subagents.
#
# Extras support mirrors deploy_artifacts: we scan
# `$RULES_HOME/extras/<bundle>/subagents/<tool>/` for the same tool name.
# Core files win on name collision.
#
# No-op is idempotent: if the source directory is missing or empty, we
# (a) do nothing new, and (b) still prune targets recorded in a previous
# manifest so removing the last source file cleans up the target side. This
# lets upstream wire the function before any subagents are authored (the
# current state — `subagents/<tool>/` directories don't exist yet) without
# noise on fresh projects.
#
# Args: $1=src_dir $2=target_dir $3=manifest_file $4=label
deploy_subagent_files() {
    local src_dir="$1" target_dir="$2" manifest_file="$3" label="$4"
    local prefix="${SKILL_PREFIX:-}"

    # Probe whether src_dir has any deployable files so we can short-circuit
    # to the cleanup-only branch without touching target_dir otherwise.
    local has_src=false
    if [ -d "$src_dir" ]; then
        local probe
        for probe in "$src_dir"/*.md "$src_dir"/*.toml "$src_dir"/*.yaml "$src_dir"/*.yml; do
            [ -f "$probe" ] && { has_src=true; break; }
        done
    fi

    # Extras may still contribute even if core src_dir is empty — check those too.
    if ! $has_src && [ -d "$RULES_HOME/extras" ]; then
        local rel_src="${src_dir#"$RULES_HOME/"}"
        local extras_dir probe
        for extras_dir in "$RULES_HOME/extras"/*/; do
            for probe in "$extras_dir$rel_src"/*.md "$extras_dir$rel_src"/*.toml \
                         "$extras_dir$rel_src"/*.yaml "$extras_dir$rel_src"/*.yml; do
                [ -f "$probe" ] && { has_src=true; break 2; }
            done
        done
    fi

    if ! $has_src; then
        # Source-side empty: still clean stale manifest-tracked files so a
        # previous deploy's artifacts don't linger after all sources are
        # removed. Keep the target directory if the user added their own
        # files (manifest-tracked cleanup only).
        if [ -f "$manifest_file" ]; then
            local stale
            while IFS= read -r stale; do
                [ -z "$stale" ] && continue
                rm -f "$target_dir/$stale"
            done < "$manifest_file"
            rm -f "$manifest_file"
            rmdir "$target_dir" 2>/dev/null || true
        fi
        return 0
    fi

    local count=0
    local manifest_new="${manifest_file}.new"
    mkdir -p "$target_dir"
    : > "$manifest_new"

    local file file_name ext bare target_name target
    for file in "$src_dir"/*.md "$src_dir"/*.toml "$src_dir"/*.yaml "$src_dir"/*.yml; do
        [ -f "$file" ] || continue
        file_name="$(basename "$file")"
        ext="${file_name##*.}"
        bare="${file_name%.*}"
        target_name="${prefix}${bare}.${ext}"
        target="$target_dir/$target_name"
        cp "$file" "$target"
        _apply_subagent_prefix "$target" "$ext"
        echo "$target_name" >> "$manifest_new"
        count=$((count + 1))
    done

    # Scan extras — core wins on name collision.
    local rel_src="${src_dir#"$RULES_HOME/"}"
    if [ -d "$RULES_HOME/extras" ]; then
        local extras_dir bundle_name extras_sub
        for extras_dir in "$RULES_HOME/extras"/*/; do
            extras_sub="$extras_dir$rel_src"
            [ -d "$extras_sub" ] || continue
            bundle_name="$(basename "$extras_dir")"
            for file in "$extras_sub"/*.md "$extras_sub"/*.toml \
                        "$extras_sub"/*.yaml "$extras_sub"/*.yml; do
                [ -f "$file" ] || continue
                file_name="$(basename "$file")"
                ext="${file_name##*.}"
                bare="${file_name%.*}"
                if [ -f "$src_dir/$file_name" ]; then
                    _warn "  SKIP: extras/$bundle_name $rel_src '$file_name' — same name exists in core (core wins)"
                    continue
                fi
                target_name="${prefix}${bare}.${ext}"
                target="$target_dir/$target_name"
                cp "$file" "$target"
                _apply_subagent_prefix "$target" "$ext"
                echo "$target_name" >> "$manifest_new"
                count=$((count + 1))
            done
        done
    fi

    # Remove files that were previously synced but are no longer in source.
    if [ -f "$manifest_file" ]; then
        local old_item
        while IFS= read -r old_item; do
            [ -z "$old_item" ] && continue
            if ! grep -qx "$old_item" "$manifest_new" 2>/dev/null; then
                rm -f "$target_dir/$old_item"
                echo "  Removed stale $label: $old_item"
            fi
        done < "$manifest_file"
    fi

    mv "$manifest_new" "$manifest_file"
    echo "  $label: $count subagent(s) synced to ${target_dir#"$PROJECT_DIR"/}/"
}

# Clean all items tracked by a manifest, then remove the manifest itself.
# CC rules use the `files` mode (flat *.md); skills use the `dirs` mode. This
# function is intentionally retained separately from deploy_artifacts — it has
# two distinct callers (CC rules in files mode, skill manifests in dirs mode).
# Args: $1=manifest $2=base_dir $3=mode(dirs|files)
clean_manifest() {
    local manifest="$1" base_dir="$2" mode="$3"
    [ -f "$manifest" ] || return 0
    local item
    while IFS= read -r item; do
        [ -z "$item" ] && continue
        if [ "$mode" = "dirs" ]; then
            rm -rf "$base_dir/$item"
        else
            rm -f "$base_dir/$item"
        fi
    done < "$manifest"
    rm -f "$manifest"
}
