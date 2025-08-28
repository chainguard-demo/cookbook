#!/bin/bash
set -euo pipefail

if [ "$1" != "post-commit" ]; then
  exit 0
fi

DB="${APK_DB:-/usr/lib/apk/db/installed}"
OUTPUT="/usr/lib/apk/fix-permissions-openshift"
: > "$OUTPUT"

apply_group_perms() {
  local p="$1"
  [ -e "$p" ] || return 0
  [ -L "$p" ] && return 0   # no symlinks

  local before after
  before="$(stat -c '%U:%G %A' "$p")"

  # cp user perms to group && set gid to 0
  chmod g=u "$p"  
  chgrp root "$p"

  after="$(stat -c '%U:%G %A' "$p")"

  if [ "$before" != "$after" ]; then
    echo "$p" >> "$OUTPUT"
  fi
}

if [ -r "$DB" ]; then
  while IFS= read -r line; do
    case "$line" in
      F:*)
        rel=${line#F:}
        [ -n "$rel" ] || continue
        apply_group_perms "/$rel"
        ;;
    esac
  done < "$DB"
fi

if [ -d /home/nonroot ]; then
  find /home/nonroot -xdev \( -type f -o -type d \) -print0 \
    | while IFS= read -r -d '' p; do
        apply_group_perms "$p"
      done
fi
