#!/bin/bash
# A timer in the background: `@timer 10` starts it and you go on typing; a notification says when the
# minutes are up. The menu bar panel lists it meanwhile. Its result has a summary and a detail.
#
# @allinoneime.schemaVersion 1
# @allinoneime.title Timer
# @allinoneime.icon ⏲️
# @allinoneime.background true
# @allinoneime.argument1 {"type": "text", "placeholder": "minutes"}
# @allinoneime.timeout 36000

minutes=$1
case "$minutes" in ''|*[!0-9.]*) echo "Not a number of minutes: $minutes" >&2; exit 1 ;; esac
sleep "$(awk -v m="$minutes" 'BEGIN { printf "%d", m * 60 }')"
if [ "$ALLINONEIME_LANGUAGE" = zh ]; then
  printf '{"summary": "时间到", "detail": "%s 分钟的计时结束了"}\n' "$minutes"
else
  printf '{"summary": "Time is up", "detail": "Your %s-minute timer finished"}\n' "$minutes"
fi
