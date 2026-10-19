#!/usr/bin/env bash
# The end-to-end harness: the real engine and the real, registered DLL typing English into a real text field through
# AllInOneIME, read back with UI Automation.
#
#   bash test/run-e2e.sh            # into a classic EDIT control in the driver's own window (the default)
#   bash test/run-e2e.sh --console  # into a classic console of its own (conhost.exe cmd.exe), at cmd's prompt
#   bash test/run-e2e.sh --webview2 # into the text field of a WebView2 in a window of its own (test/webview2host)
#   bash test/run-e2e.sh --notepad  # into real Notepad: a document of its own there, never the user's
#   bash test/run-e2e.sh --probe    # the Notepad path, stopping after the switch, reporting what it found
#
#   ... [--installed [DIR] [--engine EXE]] [--plain TEXT | --pinyin | --ai | --terminal] [--langid 0xNNNN]
#
#   --installed  the installed copy (Program Files\AllInOneIME\<version>, as HKLM\Software\AllInOneIME names it, or
#                DIR): its DLL as the MSI registered it, so no regsvr32 here, before or after; and its engine. The
#                driver checks which DLL loaded: in its own window it must be that copy; a Notepad that was already
#                running keeps the DLL it loaded before (COM doesn't load a class's DLL again in a process) and is only
#                reported. The language is the one the user's list has AllInOneIME under.
#   --engine     with --installed, this engine instead of the installed one (a build's, .build/release's) with the
#                installed DLL as it is registered: an engine tried before it is packaged
#   --plain      types TEXT through the engine as it runs for a user (no test mode, no provider) and expects it as
#                typed; otherwise "hi @improve helo", Return and "1" with the scripted provider, expecting "hi Hello."
#   --pinyin     pinyin through librime (M5): a tap of Shift, "nihao", Space, "nihao", "1", expecting "你好你好", with the
#                engine as a user's runs, on settings of the run's own (English and Chinese, typing starting in English)
#   --ai         a real AI request (M7): "@improve hello", Return, "1", expecting "Hello there.", the engine as a user's
#                runs, its settings naming the Claude API at Scripts/stub-provider.py on localhost, started here (never a
#                paid API), its key from the environment (--no-keychain: the user's Credential Manager isn't read)
#   --terminal   a console window (`@aioterm hello`, Return: a `terminal` command of the run's settings, a batch file
#                that prints what it gets and ends with exit code 3): it must come to the front, show the output and
#                the exit code, stay open after the program, and close on a key written into that console (never typed
#                anywhere else); the console is a tab or window of the default terminal (Windows Terminal, or conhost)
#   --langid     the profile's language (default 0x0409)
#
# Except with the scripted provider, the engine gets a librime user folder of the run's own (--rime-user), so nothing
# typed here is learned in the user's. For all but --plain the driver checks the engine's candidate window (M6) and
# captures it as PNGs into build/test-logs/shots-<scenario>/.
#
# TSF and SendInput need an interactive desktop, so the driver runs in the logged-on user's session as a one-shot
# scheduled task (run-in-session.sh), as tiptest does. The engine runs in that session too (the driver starts it as a
# child), so the engine and the DLL pass §2.1's same-session client check. The driver talks to the real pipe, so the
# DLL that TSF loads (not told AIO_TIP_PIPE) reaches our engine; an engine already running for the user is stopped
# first (it holds the pipe), and with --installed started again after.
#
# Notepad: the Store (WinUI 3) Notepad runs TSF on threads of its own, so the driver's hook activates the profile for
# Notepad's process, from inside it, and puts the session's input method back after. The driver seeds its own temp file
# and only ever types into the document it can prove is its own, never the user's tabs, and closes only that tab.
#
# --console starts `conhost.exe cmd.exe` itself (a classic console, whatever the default terminal is), --webview2 its own
# WebView2 app (built here with `dotnet build` if it isn't, which needs the .NET SDK; it runs on the WebView2 runtime),
# with its data in the run's folder; both get AllInOneIME through the hook as Notepad does (conhost.exe, msedgewebview2.exe
# are where TSF runs there), and are closed at the end.
#
# Without --installed this needs the Release build (build.cmd) and an elevated shell to register the DLL (an
# administrator's SSH session): it registers the DLL, runs the driver, then unregisters it again unless everything
# passed. It always leaves the session's input method as it was.
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

# Default to the hosted-edit end-to-end. --notepad drives real Notepad; --probe is the Notepad path stopping after the
# switch.
MODE="--host"
INSTALLED=""
ENGINE_GIVEN=""
PLAIN=""
SCENARIO="improve"
LANGID="0x0409"
LANGID_GIVEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --probe) MODE="--probe" ;;
    --notepad) MODE="" ;;
    --host) MODE="--host" ;;
    --console) MODE="--console" ;;
    --webview2) MODE="--webview2" ;;
    --installed)
      INSTALLED="auto"
      if [ $# -gt 1 ] && [ "${2#--}" = "$2" ]; then INSTALLED="$2"; shift; fi ;;
    --engine) ENGINE_GIVEN="$2"; shift ;;
    --plain) PLAIN="$2"; SCENARIO="plain"; shift ;;
    --pinyin) SCENARIO="pinyin" ;;
    --ai) SCENARIO="ai" ;;
    --terminal) SCENARIO="terminal" ;;
    --langid) LANGID="$2"; LANGID_GIVEN=1; shift ;;
    *) echo "unknown argument $1"; exit 2 ;;
  esac
  shift
done

SETUP=""
if [ -n "$INSTALLED" ]; then
  if [ "$INSTALLED" = "auto" ]; then
    INSTALLED="$(reg query 'HKLM\Software\AllInOneIME' /v InstallDir 2>/dev/null | tr -d '\r' |
      sed -nE 's/^ *InstallDir +REG_SZ +(.*[^\\])\\?$/\1/p')"
    [ -n "$INSTALLED" ] || { echo "AllInOneIME isn't installed (no HKLM\\Software\\AllInOneIME InstallDir)"; exit 1; }
  fi
  DLL="$INSTALLED\\AllInOneTIP.dll"
  ENGINE_WIN="$INSTALLED\\AllInOneIMEEngine.exe"
  [ -n "$ENGINE_GIVEN" ] && ENGINE_WIN="$(cygpath -w "$ENGINE_GIVEN")"
  SETUP="$(cygpath -u "$INSTALLED\\AllInOneIMESetup.exe")"
  [ -f "$(cygpath -u "$ENGINE_WIN")" ] || { echo "no engine at $ENGINE_WIN"; exit 1; }
  if [ -z "$LANGID_GIVEN" ]; then
    listed="$("$SETUP" status | tr -d '\r' | sed -nE 's/^language-list: ([0-9A-F]{4}):.*/\1/p' | head -1)"
    [ -n "$listed" ] && LANGID="0x$listed"
  fi
  echo "== the installed copy: $INSTALLED (language $LANGID) =="
else
  [ -f "$(cygpath -u "$ENGINE_WIN")" ] || { echo "no engine: build it with 'swift build -c release' in Windows/"; exit 1; }
fi
[ -f "$TIP_UNIX/build/x64/Release/e2edriver.exe" ] || { echo "no driver: build.cmd Release"; exit 1; }

echo "== the session's input method before =="
bash test/run-in-session.sh e2e-tsfstate-before "$TSFSTATE" >/dev/null 2>&1
BEFORE="$(grep -E '^active:' "$LOGDIR_UNIX/e2e-tsfstate-before.log" | tr -d '\r')"
echo "  ${BEFORE:-unknown}"

if [ -n "$INSTALLED" ]; then
  echo "== the user's engine, stopped for the run (it holds the pipe) =="
  "$SETUP" stop-engines | sed 's/^/  /'
else
  echo "== register the DLL =="
  regsvr32 /s "$DLL" || { echo "regsvr32 failed (not elevated?)"; exit 1; }
fi

# The run's own folder: librime's user folder, the settings of --pinyin and --ai, the stub's log, the PNGs.
RUN_UNIX="$LOGDIR_UNIX/e2e-run-$SCENARIO"
rm -rf "$RUN_UNIX" && mkdir -p "$RUN_UNIX/rime" "$RUN_UNIX/shots"
RUN_WIN="$(cygpath -w "$RUN_UNIX")"
ENGINE_ARGS=()
SESSION_ENV=""
STUB_PID=""
stop_stub() { [ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null; STUB_PID=""; }
trap stop_stub EXIT
if [ "$SCENARIO" != "improve" ]; then
  ENGINE_ARGS+=(--engine-arg --rime-user --engine-arg "\"$RUN_WIN\\rime\"")
fi
case "$SCENARIO" in
  terminal)
    # The batch file the `terminal` command runs (CRLF, for cmd), and the command, with the file's path in JSON.
    printf '@echo AllInOneIME e2e terminal %%*\r\n@exit /b 3\r\n' > "$RUN_UNIX/terminal.cmd"
    TERMINAL_JSON="$(printf '%s' "$RUN_WIN\\terminal.cmd" | sed 's/\\/\\\\/g')"
    printf '{"inputLanguages": ["en"], "customCommands": [{"name": "aioterm", "type": "terminal", "argv": ["%s", "{input}"]}]}\n' \
      "$TERMINAL_JSON" > "$RUN_UNIX/config.json"
    ENGINE_ARGS+=(--engine-arg --config --engine-arg "\"$RUN_WIN\\config.json\"" --engine-arg --no-keychain) ;;
  pinyin)
    printf '{"inputLanguages": ["en", "zh"], "defaultInput": "en"}\n' > "$RUN_UNIX/config.json"
    ENGINE_ARGS+=(--engine-arg --config --engine-arg "\"$RUN_WIN\\config.json\"" --engine-arg --no-keychain) ;;
  ai)
    echo "== the stub provider (Scripts/stub-provider.py), on localhost =="
    python -I "$(cygpath -w "$TIP_UNIX/../Scripts/stub-provider.py")" --port-file "$RUN_WIN\\stub.port" --log "$RUN_WIN\\stub.log" \
      --key stub-key --lifetime 600 > "$RUN_UNIX/stub.out" 2>&1 &
    STUB_PID=$!
    for _ in $(seq 1 100); do [ -s "$RUN_UNIX/stub.port" ] && break; sleep 0.1; done
    PORT="$(cat "$RUN_UNIX/stub.port" 2>/dev/null)"
    [ -n "$PORT" ] || { echo "the stub provider didn't start:"; cat "$RUN_UNIX/stub.out"; exit 1; }
    echo "  http://127.0.0.1:$PORT (pid $STUB_PID)"
    printf '{"provider": "anthropic", "anthropic": {"baseURL": "http://127.0.0.1:%s", "model": "stub-model"}, "inputLanguages": ["en"], "outputLanguages": ["en"], "outputLanguage": "en", "rewriteStyles": [], "timeoutSeconds": 15}\n' \
      "$PORT" > "$RUN_UNIX/config.json"
    ENGINE_ARGS+=(--engine-arg --config --engine-arg "\"$RUN_WIN\\config.json\"" --engine-arg --no-keychain)
    # The stub's key, for the engine (keys from the environment only): the driver's environment is the engine's.
    SESSION_ENV="ANTHROPIC_API_KEY=stub-key" ;;
esac

echo "== run the driver in the user's session =="
# The driver starts the engine (test mode, scripted provider, system clock; or as for a user, with the run's arguments)
# itself, in the session. The engine's log and the DLL's diagnostic log (AIO_TIP_LOG, set by run-in-session.sh) go to
# build/test-logs.
ENGINE_LOG_WIN="$LOGDIR_WIN\\e2e-engine.log"
WHAT=(--scenario "$SCENARIO" --fixture "\"$FIXTURE_WIN\"")
[ -n "$PLAIN" ] && WHAT=(--scenario plain --plain "\"$PLAIN\"")
EXPECT=()
case "$MODE" in
  --host|--console|--webview2) [ -n "$INSTALLED" ] && EXPECT=(--expect-tip "\"$DLL\"") ;;
esac
SHOTS=()
[ "$SCENARIO" != "plain" ] && [ "$SCENARIO" != "terminal" ] && SHOTS=(--shots "\"$RUN_WIN\\shots\"")
TARGET=($MODE)
if [ "$MODE" = "--webview2" ]; then
  HOST_EXE="$TIP_UNIX/build/x64/Release/webview2host/webview2host.exe"
  if [ ! -f "$HOST_EXE" ]; then
    echo "== the WebView2 host (dotnet build) =="
    dotnet build "$(cygpath -w "$TIP_UNIX/test/webview2host/webview2host.csproj")" -c Release \
      -o "$(cygpath -w "$TIP_UNIX/build/x64/Release/webview2host")" --nologo -v:q || { echo "no WebView2 host"; exit 1; }
  fi
  mkdir -p "$RUN_UNIX/webview2"
  TARGET=(--webview2 "\"$(cygpath -w "$HOST_EXE")\"" "\"$RUN_WIN\\webview2\"")
fi
AIO_SESSION_ENV="$SESSION_ENV" bash test/run-in-session.sh e2e-driver "$DRIVER" --engine "\"$ENGINE_WIN\"" "${WHAT[@]}" \
    "${ENGINE_ARGS[@]}" "${SHOTS[@]}" --engine-log "\"$ENGINE_LOG_WIN\"" --langid "$LANGID" "${EXPECT[@]}" "${TARGET[@]}"
RC=$?
stop_stub
if [ "$SCENARIO" = "ai" ]; then
  echo "== what the stub provider was asked (never the key) =="
  sed 's/^/  /' "$RUN_UNIX/stub.log" 2>/dev/null || echo "  (nothing)"
fi
if ls "$RUN_UNIX/shots/"*.png >/dev/null 2>&1; then
  echo "== the candidate window, captured =="
  for png in "$RUN_UNIX/shots/"*.png; do echo "  $(cygpath -w "$png") ($(stat -c %s "$png") bytes)"; done
fi

echo
echo "== engine log =="
[ -f "$LOGDIR_UNIX/e2e-engine.log" ] && sed 's/^/  /' "$LOGDIR_UNIX/e2e-engine.log" || echo "  (none)"
echo "== the DLL's per-key round trips (from the diagnostic log) =="
grep -E "key (down|up): round trip" "$LOGDIR_UNIX/e2e-driver.diag.log" 2>/dev/null | sed 's/^/  /' || echo "  (none)"
if [ -n "$INSTALLED" ] && [ "$MODE" != "--host" ]; then
  echo "== the DLL Notepad used =="
  loaded="$(grep -E 'AllInOneTIP.dll in Notepad: ' "$LOGDIR_UNIX/e2e-driver.log" | head -1 | sed -E 's/.*AllInOneTIP.dll in Notepad: ([^;]*).*/\1/')"
  if grep -qF "$DLL" <<<"$loaded"; then
    echo "  the installed copy: $DLL"
  else
    echo "  NOT the installed copy: $loaded"
    echo "  (Notepad was already running with that DLL loaded; it loads the installed one once it restarts)"
  fi
fi

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
if [ -n "$INSTALLED" ]; then
  echo "== the user's engine, started again =="
  bash test/run-in-session.sh e2e-start-engine "$INSTALLED\\AllInOneIMESetup.exe" start-engine | grep -E "start-engine:" | sed 's/^/  /'
  [ "$RC" = 0 ] && echo "PASS (the installed copy)" || echo "FAIL (the installed copy)"
elif [ "$RC" = 0 ] && [ "$MODE" != "--probe" ]; then
  echo "PASS: the DLL stays registered. To add it to the keyboard list and try it (then remove it), with the"
  echo "installer's helper (Windows\\installer\\build.ps1 builds it), or install the MSI instead:"
  echo "  AllInOneIMESetup add-keyboard            # switch with Win+Space; remove-keyboard takes it out"
  echo "  regsvr32 /u /s \"$DLL\"                  # unregister the DLL"
else
  regsvr32 /u /s "$DLL" && echo "the DLL is unregistered again"
fi
exit $RC
