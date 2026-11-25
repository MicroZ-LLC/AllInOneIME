#!/bin/sh
# Mirrors the core (Core/, with its history) to MicroZ-LLC/AllInOneIME-Core at a release: `git subtree split` of Core/
# at this repository's tag v<version>, pushed as that repository's main (a fast-forward only) and tagged v<version>
# there, the tag the Windows shell (MicroZ-LLC/AllInOneIME-Windows) and any other depends on by URL. The core is
# developed here; nothing is ever committed there. Run again it does nothing: a tag already there at the same commit is
# fine, at another one it stops. Needs push access to AllInOneIME-Core (a `gh` or git credential signed in).
#
#   Scripts/mirror-core.sh [--dry-run] VERSION       e.g. Scripts/mirror-core.sh 0.7.5 (after the release's tag v0.7.5)
set -eu
dry=no
if [ "${1:-}" = --dry-run ]; then dry=yes; shift; fi
[ $# -eq 1 ] || { echo "usage: $0 [--dry-run] VERSION" >&2; exit 2; }
version=$1
tag=v$version
remote=${CORE_MIRROR_URL:-https://github.com/MicroZ-LLC/AllInOneIME-Core.git}
cd "$(dirname "$0")/.."

git rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null || git fetch -q origin "refs/tags/$tag:refs/tags/$tag" ||
    { echo "mirror-core: no tag $tag here or on origin: release first" >&2; exit 1; }
# The same commits every time for the same history (subtree split is deterministic), so earlier mirrors stay ancestors.
split=$(git subtree split --prefix=Core "$tag" 2>/dev/null | tail -1)
[ -n "$split" ] || { echo "mirror-core: subtree split of Core/ at $tag failed" >&2; exit 1; }

there_tag=$(git ls-remote "$remote" "refs/tags/$tag" | cut -f1)
if [ -n "$there_tag" ]; then
    [ "$there_tag" = "$split" ] || { echo "mirror-core: $tag is already at $there_tag there, not $split" >&2; exit 1; }
    echo "mirror-core: $tag already mirrored ($split)"
    exit 0
fi
there_main=$(git ls-remote "$remote" refs/heads/main | cut -f1)
if [ -n "$there_main" ]; then
    git cat-file -e "$there_main^{commit}" 2>/dev/null || git fetch -q "$remote" main
    git merge-base --is-ancestor "$there_main" "$split" ||
        { echo "mirror-core: its main ($there_main) isn't in Core/'s history at $tag: not a fast-forward" >&2; exit 1; }
fi

if [ $dry = yes ]; then
    echo "git push $remote $split:refs/heads/main $split:refs/tags/$tag"
else
    git push "$remote" "$split:refs/heads/main" "$split:refs/tags/$tag"
    echo "mirror-core: $remote main and $tag at $split"
fi
