#!/usr/bin/env bash
set -euo pipefail

## [ABOUT] Update local agent-toolkit repo with safe unlock/relock flow.
## [USAGE] bash async_agent_rules.sh

readonly RULES_DIR="${HOME}/.config/agent-toolkit"
readonly LOCK_TARGETS=("core" "packs" "templates")

show_help() {
  cat <<'EOF'
bash async_agent_rules.sh

Update local agent-toolkit repository:
1) unlock writable permissions for managed rule folders
2) pull latest commits with fast-forward only
3) always re-lock folders on exit (success or failure)
EOF
}

apply_mode_recursive() {
  local mode="$1"
  local target
  for target in "${LOCK_TARGETS[@]}"; do
    chmod -R "${mode}" "${RULES_DIR}/${target}"
  done
}

relock_on_exit() {
  local exit_code="$1"
  printf '[INFO] re-locking managed rule folders...\n' >&2
  apply_mode_recursive "a-w"
  if [[ "${exit_code}" -eq 0 ]]; then
    printf '[INFO] re-lock completed\n' >&2
  else
    printf '[WARN] re-lock completed after failure (exit=%s)\n' "${exit_code}" >&2
  fi
}

validate_environment() {
  if ! command -v git >/dev/null 2>&1; then
    printf '[ERROR] git not found in PATH\n' >&2
    exit 1
  fi

  if [[ ! -d "${RULES_DIR}/.git" ]]; then
    printf '[ERROR] %s is not a git repository\n' "${RULES_DIR}" >&2
    exit 1
  fi

  local target
  for target in "${LOCK_TARGETS[@]}"; do
    if [[ ! -d "${RULES_DIR}/${target}" ]]; then
      printf '[ERROR] missing rules subdirectory: %s\n' "${RULES_DIR}/${target}" >&2
      exit 1
    fi
  done
}

main() {
  case "${1:-}" in
    -h|--help)
      show_help
      exit 0
      ;;
    "")
      ;;
    *)
      printf '[ERROR] unknown argument: %s\n' "$1" >&2
      show_help
      exit 1
      ;;
  esac

  # Step 1: Validate runtime prerequisites and expected repository structure.
  validate_environment

  # Step 2: Ensure relock always runs, even when pull fails midway.
  trap 'relock_on_exit "$?"' EXIT

  # Step 3: Temporarily unlock folders, sync repo, then rely on EXIT trap relock.
  printf '[INFO] unlocking managed rule folders...\n' >&2
  apply_mode_recursive "u+w"
  printf '[INFO] unlock completed\n' >&2

  printf '[INFO] pulling latest rules from origin/main...\n' >&2
  if git -C "${RULES_DIR}" pull --ff-only; then
    :
  else
    printf '[WARN] fast-forward failed (remote was likely force-pushed), resetting to origin/main...\n' >&2
    git -C "${RULES_DIR}" fetch origin main
    git -C "${RULES_DIR}" reset --hard origin/main
  fi
  printf '[INFO] updating submodules...\n' >&2
  git -C "${RULES_DIR}" submodule update --init --recursive
  printf '[INFO] update completed for %s\n' "${RULES_DIR}" >&2
}

main "$@"
