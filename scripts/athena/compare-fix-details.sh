#!/bin/bash
#
# Compare two check-cgp-osv-status.sh output files and show what changed.
#
#   ./compare-fix-details.sh <old-file> <new-file>
#
# Output is line-oriented ("Fix available for CGP-... "), so this is a plain
# set difference: lines present in the new run but not the old one are new
# fixes, and vice versa.

set -euo pipefail

OLD_FILE="${1:-}"
NEW_FILE="${2:-}"

if [[ -z "$OLD_FILE" || -z "$NEW_FILE" ]]; then
  echo "Usage: $0 <old-file> <new-file>" >&2
  exit 1
fi

for f in "$OLD_FILE" "$NEW_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "Error: file '$f' not found." >&2
    exit 1
  fi
done

# Normalize: drop blank lines, sort, de-dupe so comm can do set math.
old_sorted=$(mktemp)
new_sorted=$(mktemp)
trap 'rm -f "$old_sorted" "$new_sorted"' EXIT

grep -v '^[[:space:]]*$' "$OLD_FILE" | sort -u > "$old_sorted"
grep -v '^[[:space:]]*$' "$NEW_FILE" | sort -u > "$new_sorted"

added=$(comm -13 "$old_sorted" "$new_sorted")
removed=$(comm -23 "$old_sorted" "$new_sorted")

added_count=$([ -n "$added" ] && echo "$added" | wc -l | tr -d ' ' || echo 0)
removed_count=$([ -n "$removed" ] && echo "$removed" | wc -l | tr -d ' ' || echo 0)

echo "Comparing:"
echo "  old: $OLD_FILE ($(wc -l < "$old_sorted" | tr -d ' ') unique lines)"
echo "  new: $NEW_FILE ($(wc -l < "$new_sorted" | tr -d ' ') unique lines)"
echo

echo "=== ADDED ($added_count) — in new run, not in old ==="
if [ -n "$added" ]; then
  echo "$added"
else
  echo "(none)"
fi
echo

echo "=== REMOVED ($removed_count) — in old run, not in new ==="
if [ -n "$removed" ]; then
  echo "$removed"
else
  echo "(none)"
fi
