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

# --- Generic artifact deployment ---
# Deploys skills (directories) or commands/agents (files) from core + extras to target.
# Handles core-priority conflict resolution, manifest-based stale cleanup.
# Args: $1=src_dir $2=target_dir $3=manifest_file $4=label $5=mode(dirs|files)
deploy_artifacts() {
    local src_dir="$1" target_dir="$2" manifest_file="$3" label="$4" mode="$5"
    [ -d "$src_dir" ] || return 0

    local count=0
    local manifest_new="${manifest_file}.new"
    mkdir -p "$target_dir"
    : > "$manifest_new"

    local item item_name item_target
    if [ "$mode" = "dirs" ]; then
        for item in "$src_dir"/*/; do
            [ -d "$item" ] || continue
            item_name="$(basename "$item")"
            item_target="$target_dir/$item_name"
            rm -rf "$item_target"
            mkdir -p "$item_target"
            [ -n "$(ls -A "$item" 2>/dev/null)" ] && cp -a "$item/." "$item_target/"
            echo "$item_name" >> "$manifest_new"
            count=$((count + 1))
        done
    else
        for item in "$src_dir"/*.md; do
            [ -f "$item" ] || continue
            item_name="$(basename "$item")"
            cp "$item" "$target_dir/$item_name"
            echo "$item_name" >> "$manifest_new"
            count=$((count + 1))
        done
    fi

    # Deploy from extras/ — core takes priority
    local src_type
    src_type="$(basename "$src_dir")"
    if [ -d "$RULES_HOME/extras" ]; then
        local extras_dir bundle_name extras_sub
        for extras_dir in "$RULES_HOME/extras"/*/; do
            extras_sub="$extras_dir$src_type"
            [ -d "$extras_sub" ] || continue
            bundle_name="$(basename "$extras_dir")"
            if [ "$mode" = "dirs" ]; then
                for item in "$extras_sub"/*/; do
                    [ -d "$item" ] || continue
                    item_name="$(basename "$item")"
                    if [ -d "$src_dir/$item_name" ]; then
                        _warn "  SKIP: extras/$bundle_name $src_type '$item_name' — same name exists in core (core wins)"
                        continue
                    fi
                    item_target="$target_dir/$item_name"
                    rm -rf "$item_target"
                    mkdir -p "$item_target"
                    [ -n "$(ls -A "$item" 2>/dev/null)" ] && cp -a "$item/." "$item_target/"
                    echo "$item_name" >> "$manifest_new"
                    count=$((count + 1))
                done
            else
                for item in "$extras_sub"/*.md; do
                    [ -f "$item" ] || continue
                    item_name="$(basename "$item")"
                    if [ -f "$src_dir/$item_name" ]; then
                        _warn "  SKIP: extras/$bundle_name $src_type '$item_name' — same name exists in core (core wins)"
                        continue
                    fi
                    cp "$item" "$target_dir/$item_name"
                    echo "$item_name" >> "$manifest_new"
                    count=$((count + 1))
                done
            fi
        done
    fi

    # Remove items that were previously synced but no longer exist
    if [ -f "$manifest_file" ]; then
        local old_item
        while IFS= read -r old_item; do
            [ -z "$old_item" ] && continue
            if ! grep -qx "$old_item" "$manifest_new" 2>/dev/null; then
                if [ "$mode" = "dirs" ]; then
                    rm -rf "$target_dir/$old_item"
                else
                    rm -f "$target_dir/$old_item"
                fi
                echo "  Removed stale $label: $old_item"
            fi
        done < "$manifest_file"
    fi

    mv "$manifest_new" "$manifest_file"
    echo "  $label: $count item(s) synced to ${target_dir#"$PROJECT_DIR"/}/"
}

# Clean all items tracked by a manifest, then remove the manifest itself.
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
