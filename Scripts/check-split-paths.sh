#!/bin/sh
# Keeps Core/.split-paths working: the paths it lists as where the core's files were before they moved into Core/ (0.6.5)
# stay free in this repository's root. `git filter-repo --paths-from-file Core/.split-paths` renames Core/ to the root,
# and a file at one of them would collide with Core/'s (filter-repo aborts). Fails when one is there, committed or about
# to be (untracked and not ignored; without git, any file there). Run by `make test`.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
git=no
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git=yes
taken=
checked=0
while IFS= read -r path || [ -n "$path" ]; do
    case $path in
    '' | '#'* | Core/* | *'==>'* | glob:* | regex:*) continue ;;  # comments, today's core and its rename, patterns
    literal:*) path=${path#literal:} ;;
    esac
    checked=$((checked + 1))
    if [ "$git" = yes ]; then
        found=$(git ls-files --cached --others --exclude-standard -- "$path" 2>/dev/null | head -n 1)
    elif [ -e "${path%/}" ]; then
        found=$path
    else
        found=
    fi
    if [ -n "$found" ]; then taken="$taken
  $path ($found)"; fi
done < Core/.split-paths
if [ -n "$taken" ]; then
    echo "split-paths: the root has files where Core/.split-paths says the core's were before the move (filter-repo would" \
        "abort on them):$taken"
    exit 1
fi
echo "split-paths: the $checked paths the core's files had before the move are free in the root"
