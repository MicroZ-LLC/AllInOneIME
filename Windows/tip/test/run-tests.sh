#!/usr/bin/env bash
# Builds everything, registers the DLL, and runs every test. tiptest and the pipe half of wiretest need the
# interactive session, so they go through run-in-session.sh (from SSH: a one-shot scheduled task in the logged-on
# user's session).
#
#   bash test/run-tests.sh              # build Debug and Release, register, run all
#   AIO_SKIP_BUILD=1 bash test/run-tests.sh
#
# Registration needs an elevated shell (an administrator's SSH session is one). If every test passes the DLL stays
# registered, so the profile can be tried; otherwise it is unregistered again.
set -u
export MSYS_NO_PATHCONV=1
TIP_UNIX="$(cd "$(dirname "$0")/.." && pwd)"
TIP_WIN="$(cygpath -w "$TIP_UNIX")"
EXE_DIR="$TIP_WIN\\build\\x64\\Release"
DLL="$EXE_DIR\\AllInOneTIP.dll"
GOLDENS_WIN="$TIP_WIN\\test\\goldens"
GOLDENS="notepad-improve notepad-improve-click terminated retest secure-field engine-missing timeout-resync reconnect"
TSFSTATE="$EXE_DIR\\tsfstate.exe"
cd "$TIP_UNIX" || exit 1

if [ "${AIO_SKIP_BUILD:-0}" != "1" ]; then
  echo "== build (Debug, Release) =="
  cmd.exe /c "$TIP_WIN\\build.cmd" all > build/build.log 2>&1 || { tail -30 build/build.log; echo "build failed"; exit 1; }
  grep -E "warning|error" build/build.log | grep -v "0 error" || echo "no warnings"
fi

echo "== register =="
regsvr32 /s "$DLL" || { echo "regsvr32 failed (not elevated?)"; exit 1; }
# Immersive apps (AppContainers) load the DLL only if ALL APPLICATION PACKAGES may read it; an installed copy under
# Program Files has that already.
icacls "$DLL" /grant "*S-1-15-2-1:(RX)" "*S-1-15-2-2:(RX)" >/dev/null

declare -a SUMMARY
fail=0
run() { # name exe args...
  local name="$1"; shift
  if bash test/run-in-session.sh "$name" "$@" > "build/test-logs/$name.out" 2>&1; then
    SUMMARY+=("PASS  $name")
  else
    SUMMARY+=("FAIL  $name")
    fail=1
  fi
  grep -E "^\s+\[FAIL\]|^engine:|^(PASS|FAIL) \(" "build/test-logs/$name.out" | sed 's/^/    /'
}

# The session's input method before the tests: tiptest must leave it as it was (see tiptest/main.cpp).
active_profile() { # name
  bash test/run-in-session.sh "$1" "$TSFSTATE" >/dev/null 2>&1
  grep -E "^active:" "build/test-logs/$1.log" | tr -d '\r'
}
BEFORE="$(active_profile tsfstate-before)"
echo "== the session's input method: ${BEFORE:-unknown} =="

echo "== wiretest over SSH (session 0: the pipe half must skip, by §2.1) =="
"$TIP_UNIX/build/x64/Release/wiretest.exe" | grep -E "skip|PASS \(|FAIL" | sed 's/^/    /'

echo "== wiretest (interactive session) =="
run wiretest "$EXE_DIR\\wiretest.exe"
for g in $GOLDENS; do
  echo "== tiptest $g =="
  run "tiptest-$g" "$EXE_DIR\\tiptest.exe" "$GOLDENS_WIN\\$g.jsonl"
done

AFTER="$(active_profile tsfstate-after)"
if [ -n "$BEFORE" ] && [ "$BEFORE" = "$AFTER" ]; then
  SUMMARY+=("PASS  the session's input method is as it was")
else
  SUMMARY+=("FAIL  the session's input method changed: ${AFTER:-unknown}")
  fail=1
  # Put it back: "active: type 1, lang 0x0804, clsid {…}, profile {…}, hkl …"
  lang=$(sed -E 's/.*lang (0x[0-9a-f]+).*/\1/' <<<"$BEFORE")
  clsid=$(sed -E 's/.*clsid (\{[^}]*\}).*/\1/' <<<"$BEFORE")
  profile=$(sed -E 's/.*profile (\{[^}]*\}).*/\1/' <<<"$BEFORE")
  if [ -n "$BEFORE" ]; then
    bash test/run-in-session.sh tsfstate-restore "$TSFSTATE" --restore "$lang" "$clsid" "$profile" | grep -E "active now"
  fi
fi

echo
echo "== summary =="
for line in "${SUMMARY[@]}"; do echo "  $line"; done
if [ $fail = 0 ]; then
  echo "all passed: the DLL stays registered. To remove it: regsvr32 /u /s \"$DLL\""
else
  regsvr32 /u /s "$DLL" && echo "a test failed: the DLL is unregistered again"
fi
exit $fail
