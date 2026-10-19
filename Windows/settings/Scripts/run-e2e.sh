#!/usr/bin/env bash
# The Settings app end to end (AllInOneIMESettings.UITests), in Git Bash, with the user logged on: builds the engine
# (debug), the app and the driver, then runs the driver in the user's interactive session (Windows/tip/test/
# run-in-session.sh: a window needs a desktop, which an SSH session doesn't have). The driver starts its own stand-in
# provider and its own test engine on a pipe of its own (through the app, as the app starts an engine that isn't
# running), so the installed engine, the user's config.json and their keys are never touched, and it presses no key:
# UI Automation's patterns only.
#
#   Windows/settings/Scripts/run-e2e.sh
#
# The report and the screenshots: Windows/settings/build/e2e/ (e2e-report.txt, e2e-shots/ as the window shows, PrintWindow;
# app-shots/ every section drawn by the app itself, light and dark, its lists open).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$(dirname "$HERE")"
WINDOWS="$(dirname "$SETTINGS")"
OUT="$SETTINGS/build/e2e"
export DOTNET_CLI_UI_LANGUAGE=en

(cd "$WINDOWS" && swift build --product AllInOneIMEEngine >/dev/null)
dotnet build "$SETTINGS/AllInOneIMESettings/AllInOneIMESettings.csproj" -c Debug -nologo -v:q
dotnet build "$SETTINGS/AllInOneIMESettings.UITests/AllInOneIMESettings.UITests.csproj" -c Debug -nologo -v:q

APP="$(find "$SETTINGS/AllInOneIMESettings/bin/Debug" -name AllInOneIMESettings.exe | head -1)"
DRIVER="$(find "$SETTINGS/AllInOneIMESettings.UITests/bin/Debug" -name AllInOneIMESettings.UITests.exe | head -1)"
ENGINE="$WINDOWS/.build/debug/AllInOneIMEEngine.exe"
PYTHON="${PYTHON:-$(python -c 'import sys; print(sys.executable)')}"
rm -rf "$OUT"
mkdir -p "$OUT"

# The text service's end-to-end test (another job's, in Notepad) guards every key on Notepad owning the foreground:
# this window isn't started while it runs.
while tasklist 2>/dev/null | grep -qi "e2edriver.exe"; do
  echo "waiting for the text service's end-to-end test to finish..."
  sleep 10
done

w() { cygpath -w "$1"; }
bash "$WINDOWS/tip/test/run-in-session.sh" settings-e2e "$(w "$DRIVER")" \
  --app "\"$(w "$APP")\"" --engine "\"$(w "$ENGINE")\"" --stub "\"$(w "$WINDOWS/Scripts/stub-provider.py")\"" \
  --python "\"$PYTHON\"" --out "\"$(w "$OUT")\"" >/dev/null || true

# run-in-session.sh waits 3 minutes; the screenshots take longer: until the driver says how it went.
CODE="$WINDOWS/tip/build/test-logs/settings-e2e.code"
for _ in $(seq 1 600); do
  [ -f "$CODE" ] && break
  sleep 1
done
cat "$OUT/e2e-report.txt"
[ "$(tr -d ' \r\n' < "$CODE" 2>/dev/null)" = "0" ]
