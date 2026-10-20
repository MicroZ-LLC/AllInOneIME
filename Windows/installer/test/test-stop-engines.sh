#!/usr/bin/env bash
# The installer's helper's stop-engines (AllInOneIMESetup), ending nothing: its --dry-run, with a copy of the engine
# in a folder of its own beside a copy of the helper (as `msiexec INSTALLFOLDER=` puts them, outside Program Files).
# That engine is one to stop; its console's process (`--run-in-console`, its program still running) is left to it.
# Nothing installed is touched (a dry run ends nothing), so it runs from any shell, SSH's too.
#
#   bash installer/test/test-stop-engines.sh [HELPER.exe] [ENGINE.exe]
#
# HELPER: the helper to test (default: installer/build/x64/Release, as build.ps1 or MSBuild makes it); ENGINE: an
# engine to copy (default: the debug build, which runs on the Swift runtime on PATH).
set -u
export MSYS_NO_PATHCONV=1
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$(dirname "$HERE")"
WINDOWS="$(dirname "$INSTALLER")"
HELPER="${1:-$INSTALLER/build/x64/Release/AllInOneIMESetup.exe}"
ENGINE="${2:-$WINDOWS/.build/debug/AllInOneIMEEngine.exe}"
failures=0
check() { local what="$1"; shift; if "$@"; then echo "PASS $what"; else echo "FAIL $what"; failures=$((failures + 1)); fi; }

[ -f "$HELPER" ] && [ -f "$ENGINE" ] || { echo "build the helper and the engine first ($HELPER, $ENGINE)"; exit 2; }
DIR="$(mktemp -d "${TMP:-/tmp}/aio-stop-engines-XXXXXX")"
DIR_WIN="$(cygpath -w "$DIR")"
cp "$HELPER" "$ENGINE" "$DIR/"
echo '{}' > "$DIR/config.json"

# The engine, on a pipe of its own (a test engine's mutex: the user's engine, if one runs, is another).
"$DIR/AllInOneIMEEngine.exe" --test --no-rime --no-panel --quiet --config "$DIR_WIN\\config.json" --pipe "aio-stop-engines-$$" \
  >/dev/null 2>&1 &
# A console's process of it, its program (ping) running.
ALLINONEIME_CONSOLE_APPLICATION="$(cygpath -W -w)\\System32\\PING.EXE" ALLINONEIME_CONSOLE_COMMAND_LINE="ping -n 60 127.0.0.1" \
  "$DIR/AllInOneIMEEngine.exe" --run-in-console >/dev/null 2>&1 </dev/null &
sleep 3

processes="$(powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='AllInOneIMEEngine.exe'\" |
  Where-Object { \$_.ExecutablePath -like '$DIR_WIN\\*' } | ForEach-Object { '{0} {1}' -f \$_.ProcessId, \$_.CommandLine }" | tr -d '\r')"
engine_pid="$(grep -v -- '--run-in-console' <<<"$processes" | awk 'NF {print $1}' | head -1)"
console_pid="$(grep -- '--run-in-console' <<<"$processes" | awk 'NF {print $1}' | head -1)"
echo "engine pid ${engine_pid:-none}, its console's ${console_pid:-none}, in $DIR_WIN"

out="$("$DIR/AllInOneIMESetup.exe" stop-engines --dry-run | tr -d '\r')"
echo "$out" | sed 's/^/  /'
check "both running" test -n "$engine_pid" -a -n "$console_pid"
check "the engine beside the helper (installed elsewhere than Program Files) is one to stop" grep -q "would stop pid $engine_pid " <<<"$out"
check "its console's process is left to its program" grep -q "left pid $console_pid alone (a console's" <<<"$out"
running() { tasklist /FI "PID eq $1" /NH 2>/dev/null | grep -qw "$1"; }
check "a dry run stops nothing: both still running" eval '! grep -q "stop-engines: stopped pid" <<<"$out" && running "$engine_pid" && running "$console_pid"'

# The console's process with its tree (its ping).
for pid in $engine_pid $console_pid; do taskkill /PID "$pid" /T /F >/dev/null 2>&1; done
sleep 1
rm -rf "$DIR"
[ "$failures" = 0 ] && echo "ALL PASSED" || echo "$failures FAILED"
[ "$failures" = 0 ]
