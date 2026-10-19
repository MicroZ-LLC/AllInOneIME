#!/usr/bin/env bash
# The installer's test, without a human: a silent install, the checks, an upgrade over it, the e2e harness against real
# Notepad through the installed copy (English, @improve with the test provider, pinyin through librime and the candidate
# window, a real AI request to a stub provider on localhost), a silent uninstall and its checks; then, if everything
# passed, the package installed again for the user to try.
#
#   bash Windows/installer/test/run-install-test.sh [--keep-uninstalled]
#
# From an elevated shell (an administrator's SSH session), with the user logged on: the steps that need the desktop
# (TSF, the e2e driver) run in the user's session as one-shot scheduled tasks (Windows/tip/test/run-in-session.sh).
# It needs the package (Windows/installer/build.ps1) and the tip's Release test programs (Windows/tip/build.cmd).
#
# What it never does: change the user's default input method or switch their session's input method (it checks the
# session's before and after, and puts it back if it ever changed); type anywhere but the driver's own document. What
# it records first and puts back if it changed: the user's language list (Set-WinUserLanguageList from the record),
# and HKCU\Keyboard Layout\Preload.
#
# Its records and logs go to Windows/installer/build/test-state/ and test-logs/.
set -u
export MSYS_NO_PATHCONV=1
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$(cd "$HERE/.." && pwd)"
TIP="$(cd "$INSTALLER/../tip" && pwd)"
BUILD="$INSTALLER/build"
STATE="$BUILD/test-state"
LOGS="$BUILD/test-logs"
mkdir -p "$STATE" "$LOGS"
KEEP_UNINSTALLED=""
[ "${1:-}" = "--keep-uninstalled" ] && KEEP_UNINSTALLED=1

CLSID='{DBB94280-C4C2-4C91-816F-79BB471AFE56}'
PROFILE='{5BD6752B-379B-4ECD-9B1B-0819CBE55171}'
PASSES=0
FAILS=0
WARNS=0
pass() { PASSES=$((PASSES + 1)); echo "  [ok] $*"; }
fail() { FAILS=$((FAILS + 1)); echo "  [FAIL] $*"; }
warn() { WARNS=$((WARNS + 1)); echo "  [warn] $*"; }
check() { local what="$1"; shift; if "$@"; then pass "$what"; else fail "$what"; fi; }
win() { cygpath -w "$1"; }

MSI="$(ls -t "$BUILD"/AllInOneIME-*-x64.msi 2>/dev/null | head -1)"
[ -n "$MSI" ] || { echo "no package: powershell -ExecutionPolicy Bypass -File Windows\\installer\\build.ps1"; exit 1; }
VERSION="$(basename "$MSI" | sed -E 's/AllInOneIME-(.*)-x64.msi/\1/')"
INSTALL_DIR_WIN="C:\\Program Files\\AllInOneIME\\$VERSION"
INSTALL_DIR="$(cygpath -u "$INSTALL_DIR_WIN")"
SETUP="$INSTALL_DIR/AllInOneIMESetup.exe"
TSFSTATE="$(win "$TIP/build/x64/Release/tsfstate.exe")"
[ -f "$TIP/build/x64/Release/e2edriver.exe" ] || { echo "no e2e driver: Windows\\tip\\build.cmd Release"; exit 1; }

snapshot() { powershell -NoProfile -ExecutionPolicy Bypass -File "$(win "$HERE/snapshot.ps1")" -Out "$(win "$STATE/$1")" >/dev/null 2>&1; }
session_im() { # the session's active input method, as tsfstate sees it in the user's session
  bash "$TIP/test/run-in-session.sh" "install-tsfstate-$1" "$TSFSTATE" >/dev/null 2>&1
  grep -E '^active:' "$TIP/build/test-logs/install-tsfstate-$1.log" | tr -d '\r'
}
in_session() { local name="$1"; shift; bash "$TIP/test/run-in-session.sh" "$name" "$@" | grep -vE '^----- ' | tr -d '\r'; }
msi() { # msiexec, waited for; its exit code (0, or 3010: done, a restart finishes it)
  local log="$1"; shift
  msiexec "$@" /qn /norestart /l*v "$(win "$LOGS/$log")"
  local rc=$?
  echo "  msiexec $1 -> $rc (log: $LOGS/$log)"
  [ "$rc" = 0 ] || [ "$rc" = 3010 ]
}
same() { diff -q "$STATE/$1/$3" "$STATE/$2/$3" >/dev/null; }
show_diff() { diff "$STATE/$1/$3" "$STATE/$2/$3" | sed 's/^/      /' | head -20; }

echo "AllInOneIME $VERSION: $MSI"

# ---- 0. a clean start ----
echo "== 0. before"
snapshot pre
for code in $(sed -nE 's/^installed: (\{[^}]*\}).*/\1/p' "$STATE/pre/ours.txt"); do
  echo "  AllInOneIME is installed ($code): uninstalled first, for a clean record"
  msiexec /x "$code" /qn /norestart /l*v "$(win "$LOGS/pre-uninstall.log")"
  snapshot pre
done
if [ -s "$STATE/pre/ours.txt" ]; then
  echo "  something of AllInOneIME's is here already (a build registered with regsvr32?): remove it first"
  sed 's/^/    /' "$STATE/pre/ours.txt"
  exit 1
fi
rm -rf "$STATE/before"; mv "$STATE/pre" "$STATE/before"
IM_BEFORE="$(session_im before)"
echo "  the session's input method: ${IM_BEFORE:-unknown}"
echo "  the user's language list:"; sed 's/^/    /' "$STATE/before/languages.txt"
# The user's data: AllInOneIME's folder in %APPDATA%. A marker in it (the folder made for it, if there is none) must
# survive the uninstall.
DATA="$(cygpath -u "$APPDATA")/AllInOneIME"
MADE_DATA=""
[ -d "$DATA" ] || { mkdir -p "$DATA"; MADE_DATA=1; }
MARKER="$DATA/install-test-marker.txt"
echo "the installer's test checks that an uninstall leaves this folder alone" > "$MARKER"

verify_installed() { # $1: the snapshot's name
  local s="$1"
  echo "  -- files"
  check "the DLL, the engine and the helper in $INSTALL_DIR_WIN" \
    test -f "$INSTALL_DIR/AllInOneTIP.dll" -a -f "$INSTALL_DIR/AllInOneIMEEngine.exe" -a -f "$SETUP"
  check "the command line (allinoneime-cli.exe)" test -f "$INSTALL_DIR/allinoneime-cli.exe"
  check "librime (rime.dll) beside the engine" test -f "$INSTALL_DIR/rime.dll"
  local data; data="$(find "$INSTALL_DIR/rime-data" -type f 2>/dev/null | wc -l)"
  check "rime-ice's data in rime-data ($data files, the prebuilt dictionaries among them)" \
    test -f "$INSTALL_DIR/rime-data/build/rime_ice.table.bin" -a -f "$INSTALL_DIR/rime-data/rime_ice.schema.yaml"
  check "the command line runs on the runtime installed beside it" \
    grep -q '^usage: allinoneime-cli set-provider' <("$INSTALL_DIR/allinoneime-cli.exe" set-provider --help 2>&1 | tr -d '\r')
  local runtime; runtime="$(ls "$INSTALL_DIR" | grep -ciE '^(swift|Foundation|_Foundation|dispatch|BlocksRuntime|vcruntime|msvcp).*\.dll$')"
  check "the Swift and VC++ runtime next to the engine ($runtime DLLs)" test "$runtime" -ge 15
  echo "  -- the machine's registration"
  local status; status="$("$SETUP" status | tr -d '\r')"
  check "the COM server is the installed DLL" grep -qxF "com-server: $INSTALL_DIR_WIN\\AllInOneTIP.dll" <<<"$status"
  check "HKLM\\Software\\AllInOneIME names the engine" \
    grep -qxF "engine-path: $INSTALL_DIR_WIN\\AllInOneIMEEngine.exe" <<<"$status"
  check "the Run entry starts the engine at logon" \
    grep -qxF "run-at-logon: \"$INSTALL_DIR_WIN\\AllInOneIMEEngine.exe\"" <<<"$status"
  check "the en-US and zh-CN profiles are registered" \
    test "$(grep -cE '^profile (0409|0804): registered$' <<<"$status")" = 2
  local categories
  categories="$(reg query "HKLM\\Software\\Microsoft\\CTF\\TIP\\$CLSID\\Category\\Item\\$CLSID" 2>/dev/null | grep -cF "$CLSID\\{")"
  check "the 5 categories are registered ($categories)" test "$categories" = 5
  echo "  -- in the user's session"
  local session; session="$(in_session "install-status-$s" "$INSTALL_DIR_WIN\\AllInOneIMESetup.exe" status)"
  check "TSF enumerates both profiles, enabled" \
    test "$(grep -cE '^tsf (0409|0804): enumerated, enabled$' <<<"$session")" = 2
  echo "  -- the user's language list"
  snapshot "$s"
  local entry; entry="$(grep -F "$CLSID$PROFILE" "$STATE/$s/languages.txt")"
  check "AllInOneIME is in it: ${entry%%:*} (${entry#*: })" test -n "$entry"
  # Nothing else in it changed: with our entry taken out, the list is the recorded one.
  local ours; ours="$(sed 's/[{}]/\\&/g' <<<"$CLSID$PROFILE")"
  sed -E "s/, [0-9A-F]{4}:$ours//; s/: [0-9A-F]{4}:$ours(, )?/: /" "$STATE/$s/languages.txt" \
    > "$STATE/$s/languages-without-ours.txt"
  check "the rest of the list is as recorded" diff -q "$STATE/before/languages.txt" "$STATE/$s/languages-without-ours.txt"
  check "the default input method is as recorded" same before "$s" default.txt
  check "HKCU\\Keyboard Layout is as recorded" same before "$s" hkcu-keyboard-layout.txt || show_diff before "$s" hkcu-keyboard-layout.txt
  local im; im="$(session_im "$s")"
  check "the session's input method is as recorded" test "$im" = "$IM_BEFORE"
}

# ---- 1. install ----
echo "== 1. a silent install"
check "msiexec /i /qn" msi install.log /i "$(win "$MSI")"
verify_installed installed

echo "  -- the engine, as the Run entry starts it at logon"
in_session install-start-engine "$INSTALL_DIR_WIN\\AllInOneIMESetup.exe" start-engine | sed 's/^/    /'
sleep 1
# The installed copy's (another engine, a build's, may be running in another session).
engine="$(INSTALLED_ENGINE="$INSTALL_DIR_WIN\AllInOneIMEEngine.exe" powershell -NoProfile -Command '
  $p = Get-Process AllInOneIMEEngine -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $env:INSTALLED_ENGINE } | Select-Object -First 1
  if ($p) {
    $core = ($p.Modules | Where-Object { $_.ModuleName -eq "swiftCore.dll" }).FileName
    "session=" + $p.SessionId + " window=" + $p.MainWindowHandle + " path=" + $p.Path + " swiftCore=" + $core
  }' 2>/dev/null | tr -d '\r')"
echo "    $engine"
check "it runs in the user's session" grep -q 'session=[1-9]' <<<"$engine"
check "it has no window (no console at logon)" grep -q 'window=0 ' <<<"$engine"
check "it runs on the runtime installed next to it" grep -qF "swiftCore=$INSTALL_DIR_WIN\\swiftCore.dll" <<<"$engine"

# ---- 2. an upgrade over it (a package of the same version, another product code) ----
echo "== 2. an upgrade over it"
UPGRADE="$BUILD/test-upgrade.msi"
powershell -NoProfile -ExecutionPolicy Bypass -File "$(win "$INSTALLER/build.ps1")" -SkipBuild -Output "$(win "$UPGRADE")" \
  > "$LOGS/upgrade-build.log" 2>&1
check "a second package built" test -f "$UPGRADE"
check "msiexec /i /qn (the upgrade)" msi upgrade.log /i "$(win "$UPGRADE")"
verify_installed upgraded
check "one AllInOneIME installed, the upgrade's" test "$(grep -c '^installed: ' "$STATE/upgraded/ours.txt")" = 1

# ---- 3. the e2e harness, through the installed copy ----
echo "== 3. typing through the installed copy"
e2e() { # $1: name; the rest: run-e2e.sh's arguments
  local name="$1"; shift
  bash "$TIP/test/run-e2e.sh" --installed "$@" > "$LOGS/e2e-$name.log" 2>&1
  local rc=$?
  cp "$TIP/build/test-logs/e2e-driver.log" "$LOGS/e2e-$name.driver.log" 2>/dev/null
  cp "$TIP/build/test-logs/e2e-engine.log" "$LOGS/e2e-$name.engine.log" 2>/dev/null
  for shots in "$TIP"/build/test-logs/e2e-run-*/shots; do
    ls "$shots"/*.png >/dev/null 2>&1 || continue
    mkdir -p "$LOGS/e2e-$name-shots" && cp "$shots"/*.png "$LOGS/e2e-$name-shots/"
    rm -f "$shots"/*.png
  done
  grep -E '\[(ok|FAIL)\]|document:|AllInOneTIP.dll in Notepad|TIP loaded here|captured:' "$TIP/build/test-logs/e2e-driver.log" |
    tr -d '\r' | sed -E 's/^[0-9:.]+ +/    /'
  return $rc
}
check "the installed DLL and engine in a new process (an EDIT control, the driver's)" e2e host --host
check "real Notepad, English through the engine as it runs for a user: \"Hello world. 123\"" \
  e2e notepad-plain --notepad --plain "Hello world. 123"
check "real Notepad, @improve with the test provider: \"hi Hello.\"" e2e notepad-improve --notepad
check "real Notepad, pinyin through librime: Shift, \"nihao\", Space, \"nihao\", 1 give \"你好你好\", the candidate window up" \
  e2e notepad-pinyin --notepad --pinyin
check "real Notepad, a real AI request (the Claude API's format, a stub on localhost): \"@improve hello\", 1 give \"Hello there.\"" \
  e2e notepad-ai --notepad --ai
if grep -qF "AllInOneTIP.dll in Notepad: $INSTALL_DIR_WIN\\AllInOneTIP.dll" "$LOGS/e2e-notepad-improve.driver.log"; then
  pass "Notepad used the installed DLL"
else
  warn "Notepad used $(grep -m1 -oE 'AllInOneTIP.dll in Notepad: [^;]*' "$LOGS/e2e-notepad-improve.driver.log" | sed 's/.*: //'):" \
    "it was running before the install and keeps the DLL it had loaded until it restarts"
fi
IM_AFTER_E2E="$(session_im after-e2e)"
check "the session's input method is as recorded" test "$IM_AFTER_E2E" = "$IM_BEFORE"

# ---- 4. uninstall ----
echo "== 4. a silent uninstall"
PENDING_BEFORE="$(reg query 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' /v PendingFileRenameOperations 2>/dev/null | tr '*' '\n' | grep -c 'Config.Msi')"
CODE="$(sed -nE 's/^installed: (\{[^}]*\}).*/\1/p' "$STATE/upgraded/ours.txt" | head -1)"
check "msiexec /x /qn ($CODE)" msi uninstall.log /x "$CODE"
snapshot uninstalled
check "nothing of AllInOneIME's left: keys, Run entry, files, folder" test ! -s "$STATE/uninstalled/ours.txt" ||
  sed 's/^/      /' "$STATE/uninstalled/ours.txt"
PENDING_AFTER="$(reg query 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' /v PendingFileRenameOperations 2>/dev/null | tr '*' '\n' | grep -c 'Config.Msi')"
if [ "$PENDING_AFTER" -gt "$PENDING_BEFORE" ]; then
  echo "  (files in use, as the DLL is in apps that used it, were moved to Config.Msi and go at the next restart:" \
    "$((PENDING_AFTER - PENDING_BEFORE)))"
fi
check "the user's language list is as recorded" same before uninstalled languages.txt || show_diff before uninstalled languages.txt
check "the default input method is as recorded" same before uninstalled default.txt
check "HKCU\\...\\User Profile is as recorded" same before uninstalled hkcu-user-profile.txt ||
  show_diff before uninstalled hkcu-user-profile.txt
check "HKCU\\...\\User Profile System Backup is as recorded" same before uninstalled hkcu-user-profile-backup.txt
check "HKCU\\Keyboard Layout is as recorded" same before uninstalled hkcu-keyboard-layout.txt ||
  show_diff before uninstalled hkcu-keyboard-layout.txt
check "TSF's order of the user's input methods is as recorded" \
  diff -q <(grep -F 'SortOrder' "$STATE/before/hkcu-ctf.txt") <(grep -F 'SortOrder' "$STATE/uninstalled/hkcu-ctf.txt")
check "the user's data is still there" test -f "$MARKER"
IM_AFTER="$(session_im uninstalled)"
check "the session's input method is as recorded" test "$IM_AFTER" = "$IM_BEFORE"

# ---- 5. what the user had, back (only if it changed) ----
if ! same before uninstalled languages.txt; then
  echo "== the language list changed: restoring it from the record"
  powershell -NoProfile -Command "Set-WinUserLanguageList (Import-Clixml '$(win "$STATE/before/languages.xml")') -Force" 2>&1 | sed 's/^/  /'
  snapshot restored
  check "the user's language list is as recorded again" same before restored languages.txt
fi
if ! same before uninstalled hkcu-keyboard-layout.txt; then
  echo "== HKCU\\Keyboard Layout\\Preload changed: restoring it from the record"
  reg delete 'HKCU\Keyboard Layout\Preload' /va /f >/dev/null 2>&1
  reg import "$(win "$STATE/before/preload.reg")" >/dev/null 2>&1
  snapshot restored
  check "HKCU\\Keyboard Layout is as recorded again" same before restored hkcu-keyboard-layout.txt
fi
if [ -n "$IM_BEFORE" ] && [ "$IM_AFTER" != "$IM_BEFORE" ]; then
  lang=$(sed -E 's/.*lang (0x[0-9a-f]+).*/\1/' <<<"$IM_BEFORE")
  clsid=$(sed -E 's/.*clsid (\{[^}]*\}).*/\1/' <<<"$IM_BEFORE")
  profile=$(sed -E 's/.*profile (\{[^}]*\}).*/\1/' <<<"$IM_BEFORE")
  in_session install-tsfstate-restore "$TSFSTATE" --restore "$lang" "$clsid" "$profile" | grep -E "active now"
fi
rm -f "$MARKER"
[ -n "$MADE_DATA" ] && rmdir "$DATA" 2>/dev/null

echo
echo "== $PASSES passed, $FAILS failed, $WARNS warnings"
if [ "$FAILS" = 0 ] && [ -z "$KEEP_UNINSTALLED" ]; then
  echo "== 6. installed again, for the user to try"
  if msi final-install.log /i "$(win "$MSI")"; then
    in_session install-final-start "$INSTALL_DIR_WIN\\AllInOneIMESetup.exe" start-engine | sed 's/^/  /'
    in_session install-final-status "$INSTALL_DIR_WIN\\AllInOneIMESetup.exe" status | sed 's/^/  /'
    snapshot final
    same before final hkcu-keyboard-layout.txt || echo "  HKCU\\Keyboard Layout differs from the record"
  fi
fi
[ "$FAILS" = 0 ]
