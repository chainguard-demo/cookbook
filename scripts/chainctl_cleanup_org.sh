#!/usr/bin/env bash
# chainctl_cleanup_org.sh
# List image repos for an org, delete selected (or all) repos, then delete the org.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  chainctl_cleanup_org.sh <ORG> [REPO ...] [--dry-run]

Examples:
  # Delete ALL image repos under the org, then delete the org
  CONFIRM=delete ./chainctl_cleanup_org.sh mycompany

  # Preview actions only (no deletions)
  ./chainctl_cleanup_org.sh mycompany --dry-run

  # Delete only specific repos, then delete the org
  CONFIRM=delete ./chainctl_cleanup_org.sh mycompany aspnet-runtime node python
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

DRY_RUN=false
ORG="$1"; shift || true
REPOS=()

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    *) REPOS+=("$1"); shift ;;
  esac
done

log()   { printf '[%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S')" "$*"; }
run()   { $DRY_RUN && { echo "DRY-RUN: $*"; } || { eval "$@"; }; }
abort() { echo "ERROR: $*" >&2; exit 1; }

# Ensure chainctl is present
command -v chainctl >/dev/null 2>&1 || abort "chainctl not found in PATH."

log "Listing image repos for org: $ORG"
LIST_OUTPUT="$(chainctl images repos list --parent "$ORG")" || abort "Failed to list image repos for org '$ORG'"

echo "----- Repo tree -----"
echo "$LIST_OUTPUT"
echo "---------------------"

# If no repos explicitly provided, parse names from the tree output (Bash 3-friendly; no mapfile)
if [[ ${#REPOS[@]} -eq 0 ]]; then
  PARSED_REPOS="$(
    echo "$LIST_OUTPUT" \
      | sed -n 's/.*\[\(.*\)\].*/\1/p' \
      | grep -v '/' || true
  )"

  # Build array safely (avoids mapfile/readarray)
  while IFS= read -r repo; do
    [[ -n "${repo:-}" ]] && REPOS+=("$repo")
  done <<***REMOVED***
$PARSED_REPOS
***REMOVED***

  if [[ ${#REPOS[@]} -eq 0 ]]; then
    log "No repos found to delete under org '$ORG'."
  else
    log "Parsed repos: ${REPOS[*]}"
  fi
else
  log "Using explicitly provided repos: ${REPOS[*]}"
fi

# Safety check
if [[ "${CONFIRM:-}" != "delete" ]]; then
  echo
  echo "SAFETY GUARD: Set CONFIRM=delete to proceed with deletions."
  echo "Nothing has been deleted."
  exit 0
fi

# Delete repos
if [[ ${#REPOS[@]} -gt 0 ]]; then
  log "Deleting ${#REPOS[@]} repo(s) under '$ORG'..."
  for repo in "${REPOS[@]}"; do
    [[ -z "$repo" ]] && continue
    log "Deleting repo: $repo"
    if $DRY_RUN; then
      echo "DRY-RUN: chainctl image repo delete --parent \"$ORG\" \"$repo\""
    else
      if ! chainctl image repo delete --parent "$ORG" "$repo"; then
        echo "WARN: Failed to delete repo '$repo' (continuing)..." >&2
      fi
    fi
  done
else
  log "No repos to delete."
fi

# Delete the org
log "Deleting org: $ORG"
run "chainctl iam organizations delete \"$ORG\""

log "Done."

