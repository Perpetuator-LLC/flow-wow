#!/usr/bin/env bash
# Settles the usual CHANGELOG.md conflict when a contributor's pull request is
# merged (docs/MERGING.md, step 5): their "## Unreleased" block goes on top,
# numbered, with a thanks line; ours (the numbered entries) follow.
#
#   tools/pr-changelog.sh CHANGELOG.md 0.35.164 18 BIMpossible
#
# Run it in Git Bash while the merge is stopped on the conflict, then look at
# the top of the file before `git add`.
set -e
file="$1"; ver="$2"; pr="$3"; who="${4:-the contributor}"
if [ -z "$file" ] || [ -z "$ver" ] || [ -z "$pr" ]; then
    echo "usage: pr-changelog.sh FILE VERSION PR [NAME]" >&2
    exit 2
fi
if ! grep -q '^<<<<<<< ' "$file"; then
    echo "$file has no conflict to settle" >&2
    exit 1
fi
awk -v ver="$ver" -v pr="$pr" -v who="$who" '
/^<<<<<<< /   { inhead = 1; next }
/^=======$/   { if (inhead) { inhead = 0; inpr = 1; next } }
/^>>>>>>> /   { inpr = 0
                sub(/\n+$/, "\n", prtext)
                printf "%s", prtext
                printf "  (Thanks, %s: pull request %s.)\n\n", who, pr
                printf "%s", head
                next }
inhead        { head = head $0 "\n"; next }
inpr          { if ($0 ~ /^## Unreleased/) $0 = "## " ver; prtext = prtext $0 "\n"; next }
              { print }
' "$file" > "$file.resolved"
mv "$file.resolved" "$file"
