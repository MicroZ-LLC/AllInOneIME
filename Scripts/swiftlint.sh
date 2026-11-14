#!/bin/sh
# SwiftLint at a pinned version, against today's violations: fails on a violation of .swiftlint.yml's rules that isn't
# in .swiftlint.baseline.json, so new code has to meet the rules while old code is fixed as it is touched (a line of
# a baselined violation that changes is new again). Downloads SwiftLint once from its GitHub release (macOS: the
# universal portable binary; Linux: the static one), checks its SHA-256, and keeps it in ~/.cache/allinoneime (or
# $ALLINONEIME_TOOL_CACHE): no Homebrew, nothing in the repository. Run by `make lint`.
#
#   Scripts/swiftlint.sh                    lint: the new violations, exit 1 if there are any
#   Scripts/swiftlint.sh --write-baseline   record today's violations (after fixing some, or renaming a file); one a
#                                           line, sorted. CI fails a PR whose baseline gains an entry its base lacks
#                                           (Scripts/check-ratchet.sh --base): it may only shrink.
#   Scripts/swiftlint.sh --count            how many violations the baseline holds
#   Scripts/swiftlint.sh --all              every violation, the baselined ones too
set -eu
VERSION=0.65.1
repo=$(cd "$(dirname "$0")/.." && pwd)
baseline=$repo/.swiftlint.baseline.json

case "$(uname -s)-$(uname -m)" in
Darwin-*) asset=portable_swiftlint.zip binary=swiftlint
          sha=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0 ;;
Linux-x86_64) asset=swiftlint_linux_amd64.zip binary=swiftlint-static
          sha=caeed6f4a679c35539ffaf124f6c4ab4a8416917f7d8796279dc52b74026059d ;;
Linux-aarch64 | Linux-arm64) asset=swiftlint_linux_arm64.zip binary=swiftlint-static
          sha=9ffa52f478e6d8eb485d37d14715ffac90abc81c58f3370d598bf75be05605f8 ;;
*) echo "swiftlint: no SwiftLint $VERSION download for $(uname -sm)" >&2; exit 2 ;;
esac

if [ "${1:-}" = --count ]; then
    python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))))' "$baseline"
    exit 0
fi

dir=${ALLINONEIME_TOOL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/allinoneime}/swiftlint-$VERSION
swiftlint=$dir/$binary
if [ ! -x "$swiftlint" ]; then
    mkdir -p "$dir"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    echo "swiftlint: downloading SwiftLint $VERSION ($asset)" >&2
    curl -fsSL -o "$tmp/$asset" "https://github.com/realm/SwiftLint/releases/download/$VERSION/$asset"
    echo "$sha  $tmp/$asset" | shasum -a 256 -c - >/dev/null
    (cd "$tmp" && unzip -q "$asset" "$binary")
    chmod +x "$tmp/$binary"
    mv "$tmp/$binary" "$swiftlint"
fi

cd "$repo"
case "${1:-}" in
--write-baseline)
    # Every violation, the baselined ones too; then sorted, one a line, so a diff shows which went or came.
    "$swiftlint" lint --quiet --strict --write-baseline "$baseline.tmp" >/dev/null || true
    python3 - "$baseline.tmp" "$baseline" <<'EOF'
import json, sys
entries = json.load(open(sys.argv[1]))
key = lambda e: (e["violation"]["location"]["file"], e["violation"]["ruleIdentifier"], e["violation"]["location"]["line"])
lines = [json.dumps(e, sort_keys=True, ensure_ascii=False) for e in sorted(entries, key=key)]
open(sys.argv[2], "w").write("[\n" + ",\n".join(lines) + "\n]\n")
print(f"swiftlint: {len(entries)} violations in .swiftlint.baseline.json")
EOF
    rm -f "$baseline.tmp"
    ;;
--all)
    exec "$swiftlint" lint --quiet --strict
    ;;
'')
    if ! "$swiftlint" lint --quiet --strict --baseline "$baseline"; then
        echo "swiftlint: new violations (above). Fix them; where a rule is wrong for a line, disable it on that line with" >&2
        echo "  the reason: // swiftlint:disable:next <rule> - <why>. Only renamed a file? Scripts/swiftlint.sh --write-baseline" >&2
        exit 1
    fi
    echo "swiftlint: no new violations ($(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))))' "$baseline") baselined)"
    ;;
*) echo "usage: $0 [--write-baseline | --count | --all]" >&2; exit 2 ;;
esac
