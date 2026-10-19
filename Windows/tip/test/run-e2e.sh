#!/usr/bin/env bash
# The end-to-end harness (M3): the real engine and the real, registered DLL typing English into a real edit control
# through AllInOneIME, read back with UI Automation.
#
#   bash test/run-e2e.sh            # the hosted-edit end-to-end (default): the whole real stack, and it passes here
#   bash test/run-e2e.sh --notepad  # drive real Notepad (see below: modern/packaged Notepad can't host the TIP)
#   bash test/run-e2e.sh --probe    # the Notepad path, stopping after the switch, reporting what it found
#
# TSF and SendInput need an interactive desktop, so the driver runs in the logged-on user's session as a one-shot
# scheduled task (run-in-session.sh), as tiptest does. The engine runs in that session too (the driver starts it as a
# child), so the engine and the DLL pass §2.1's same-session client check. The driver talks to the real pipe, so the
# DLL that TSF loads (not told AIO_TIP_PIPE) reaches our engine.
#
# Notepad: on this Windows 11 the only Notepad is the packaged (WinUI) Store app, whose text input does not host a
# classic in-process TSF text service — ActivateProfile succeeds but TSF never loads the DLL into it, so AllInOneIME
# can't compose there. The driver's Notepad path (--notepad/--probe) demonstrates this safely (it seeds its own temp
# file and only ever types into the document it can prove is its own, never the user's tab). The default hosted-edit
# run exercises the identical pipeline — the real DLL loaded by TSF, the real engine over the pipe, SendInput keys,
# UIA TextPattern — through a classic EDIT control the DLL *does* load into, and it is where the measurements come
# from.
#
# This needs the Release build (build.cmd) and an elevated shell to register the DLL (an administrator's SSH session).
# It registers the DLL, runs the driver, then unregisters it again unless everything passed, and always leaves the
# session's input method as it was.
set -u
export MSYS_NO_PATHCONV=1
TIP_UNIX="$(cd "$(dirname "$0")/.." && pwd)"
TIP_WIN="$(cygpath -w "$TIP_UNIX")"
EXE_DIR="$TIP_WIN\\build\\x64\\Release"
DLL="$EXE_DIR\\AllInOneTIP.dll"
DRIVER="$EXE_DIR\\e2edriver.exe"
TSFSTATE="$EXE_DIR\\tsfstate.exe"
ENGINE_WIN="$(cygpath -w "$TIP_UNIX/../.build/release/AllInOneIMEEngine.exe")"
FIXTURE_WIN="$(cygpath -w "$TIP_UNIX/../../Core/Tests/AllInOneIMEWireTests/WireGoldens/fixtures/improve-hello.json")"
LOGDIR_UNIX="$TIP_UNIX/build/test-logs"
LOGDIR_WIN="$(cygpath -w "$LOGDIR_UNIX")"
mkdir -p "$LOGDIR_UNIX"
cd "$TIP_UNIX" || exit 1

# Default to the hosted-edit end-to-end (the pipeline that engages on this machine). --notepad drives real Notepad;
# --probe is the Notepad path stopping after the switch.
MODE="--host"
for a in "$@"; do
  [ "$a" = "--probe" ] && MODE="--probe"
  [ "$a" = "--notepad" ] && MODE=""
  [ "$a" = "--host" ] && MODE="--host"
done

[ -f "$TIP_UNIX/../.build/release/AllInOneIMEEngine.exe" ] || { echo "no engine: build it with 'swift build -c release' in Windows/"; exit 1; }
[ -f "$TIP_UNIX/build/x64/Release/e2edriver.exe" ] || { echo "no driver: build.cmd Release"; exit 1; }

echo "== the session's input method before =="
bash test/run-in-session.sh e2e-tsfstate-before "$TSFSTATE" >/dev/null 2>&1
BEFORE="$(grep -E '^active:' "$LOGDIR_UNIX/e2e-tsfstate-before.log" | tr -d '\r')"
echo "  ${BEFORE:-unknown}"

echo "== register the DLL =="
regsvr32 /s "$DLL" || { echo "regsvr32 failed (not elevated?)"; exit 1; }

echo "== run the driver in the user's session =="
# The driver starts the engine (test mode, scripted provider, system clock) itself, in the session. The engine's log
# and the DLL's diagnostic log (AIO_TIP_LOG, set by run-in-session.sh) go to build/test-logs.
ENGINE_LOG_WIN="$LOGDIR_WIN\\e2e-engine.log"
bash test/run-in-session.sh e2e-driver "$DRIVER" \
    --engine "$ENGINE_WIN" --fixture "$FIXTURE_WIN" --engine-log "$ENGINE_LOG_WIN" --langid 0x0409 $MODE
RC=$?

echo
echo "== engine log =="
[ -f "$LOGDIR_UNIX/e2e-engine.log" ] && sed 's/^/  /' "$LOGDIR_UNIX/e2e-engine.log" || echo "  (none)"
echo "== the DLL's per-key round trips (from the diagnostic log) =="
grep -E "key (down|up): round trip" "$LOGDIR_UNIX/e2e-driver.diag.log" 2>/dev/null | sed 's/^/  /' || echo "  (none)"

echo "== the session's input method after =="
bash test/run-in-session.sh e2e-tsfstate-after "$TSFSTATE" >/dev/null 2>&1
AFTER="$(grep -E '^active:' "$LOGDIR_UNIX/e2e-tsfstate-after.log" | tr -d '\r')"
echo "  ${AFTER:-unknown}"
if [ -n "$BEFORE" ] && [ "$BEFORE" != "$AFTER" ]; then
  echo "  the input method changed: restoring"
  lang=$(sed -E 's/.*lang (0x[0-9a-f]+).*/\1/' <<<"$BEFORE")
  clsid=$(sed -E 's/.*clsid (\{[^}]*\}).*/\1/' <<<"$BEFORE")
  profile=$(sed -E 's/.*profile (\{[^}]*\}).*/\1/' <<<"$BEFORE")
  bash test/run-in-session.sh e2e-tsfstate-restore "$TSFSTATE" --restore "$lang" "$clsid" "$profile" | grep -E "active now"
fi

echo
if [ "$RC" = 0 ] && [ "$MODE" != "--probe" ]; then
  echo "PASS: the DLL stays registered. To add it to the keyboard list and try it (then remove it):"
  echo "  \$l = Get-WinUserLanguageList"
  echo "  \$l[0].InputMethodTips.Add('0804:{DBB94280-C4C2-4C91-816F-79BB471AFE56}{5BD6752B-379B-4ECD-9B1B-0819CBE55171}')"
  echo "  Set-WinUserLanguageList \$l -Force      # switch with Win+Space; .Remove(...) the same string to take it out"
  echo "  regsvr32 /u /s \"$DLL\"                  # unregister the DLL"
else
  regsvr32 /u /s "$DLL" && echo "the DLL is unregistered again"
fi
exit $RC
