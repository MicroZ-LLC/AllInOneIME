#!/usr/bin/env bash
# Runs a test exe in the logged-on user's interactive session. An OpenSSH session is session 0, the services' session,
# with no interactive desktop: TSF has nothing to work with there, and the DLL's own guard (§2.1, §8) keeps it passive.
# So from session 0 this schedules the exe as a one-shot task in the user's session (schtasks /IT, at the limited,
# medium-integrity token an app has), waits for it, and collects its output from a file. From an interactive session
# it just runs the exe.
#
#   run-in-session.sh <name> <exe> [args...]
#
# <exe> and args are Windows paths. The output goes to build/test-logs/<name>.log (the DLL's diagnostic log to
# <name>.diag.log), the exit code to <name>.code; the log is printed and the exit status mirrored.
# AIO_TEST_USER overrides the user (default: $USERNAME), who must be logged on (see README). AIO_SESSION_ENV, lines of
# NAME=VALUE, is set for the exe (a scheduled task has the user's environment, not this shell's).
set -u
export MSYS_NO_PATHCONV=1
NAME="$1"; shift
EXE_WIN="$1"; shift
ARGS="$*"
USER_NAME="${AIO_TEST_USER:-${USERNAME:-$(whoami)}}"
TIP_UNIX="$(cd "$(dirname "$0")/.." && pwd)"
TIP_WIN="$(cygpath -w "$TIP_UNIX")"
LOGDIR_UNIX="$TIP_UNIX/build/test-logs"
mkdir -p "$LOGDIR_UNIX"
LOGDIR_WIN="$(cygpath -w "$LOGDIR_UNIX")"
TASK="AllInOneIME-test-$NAME"
BAT="$LOGDIR_UNIX/$NAME.bat"
BAT_WIN="$LOGDIR_WIN\\$NAME.bat"

rm -f "$LOGDIR_UNIX/$NAME.log" "$LOGDIR_UNIX/$NAME.code" "$LOGDIR_UNIX/$NAME.diag.log"
# A batch file (CRLF, for cmd) that runs the exe with its output redirected.
{
  printf '@echo off\r\n'
  printf 'cd /d "%s"\r\n' "$TIP_WIN"
  printf 'set AIO_TIP_LOG=%s\\%s.diag.log\r\n' "$LOGDIR_WIN" "$NAME"
  while IFS= read -r pair; do
    [ -n "$pair" ] && printf 'set "%s"\r\n' "$pair"
  done <<<"${AIO_SESSION_ENV:-}"
  printf '"%s" %s > "%s\\%s.log" 2>&1\r\n' "$EXE_WIN" "$ARGS" "$LOGDIR_WIN" "$NAME"
  printf 'echo %%ERRORLEVEL%% > "%s\\%s.code"\r\n' "$LOGDIR_WIN" "$NAME"
} > "$BAT"

SESSION="$(powershell -NoProfile -Command '(Get-Process -Id $PID).SessionId' 2>/dev/null | tr -d '\r\n ')"
if [ "${SESSION:-0}" != "0" ]; then
  cmd.exe /c "$BAT_WIN" >/dev/null 2>&1
else
  schtasks /Create /F /TN "$TASK" /TR "$BAT_WIN" /SC ONCE /ST 23:59 /IT /RL LIMITED /RU "$USER_NAME" >/tmp/aio-sch.out 2>&1 \
    || { echo "schtasks /Create failed:"; iconv -f GBK -t UTF-8 /tmp/aio-sch.out 2>/dev/null || cat /tmp/aio-sch.out; exit 3; }
  schtasks /Run /TN "$TASK" >/tmp/aio-sch.out 2>&1 \
    || { echo "schtasks /Run failed:"; iconv -f GBK -t UTF-8 /tmp/aio-sch.out 2>/dev/null || cat /tmp/aio-sch.out; schtasks /Delete /F /TN "$TASK" >/dev/null 2>&1; exit 3; }
  for _ in $(seq 1 180); do
    [ -f "$LOGDIR_UNIX/$NAME.code" ] && break
    sleep 1
  done
  sleep 1
  schtasks /Delete /F /TN "$TASK" >/dev/null 2>&1
fi

echo "----- $NAME.log -----"
if [ -f "$LOGDIR_UNIX/$NAME.log" ]; then cat "$LOGDIR_UNIX/$NAME.log"; else echo "(no log: did the task run? is $USER_NAME logged on?)"; fi
RC=$(tr -d ' \r\n' < "$LOGDIR_UNIX/$NAME.code" 2>/dev/null)
echo "----- exit code: ${RC:-<none>} -----"
[ "${RC:-1}" = "0" ]
