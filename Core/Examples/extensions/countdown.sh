#!/bin/bash
# Shows its progress in the panel as it prints, and inserts nothing (`show`). Leave the text field and it
# goes on in the background, then notifies you.
#
# @allinoneime.schemaVersion 1
# @allinoneime.title Countdown
# @allinoneime.icon ⏳
# @allinoneime.output show
# @allinoneime.argument1 {"type": "text", "placeholder": "seconds", "optional": true}
# @allinoneime.timeout 70

seconds=${1:-5}
case "$seconds" in ''|*[!0-9]*) echo "Not a number of seconds: $seconds" >&2; exit 1 ;; esac
[ "$seconds" -le 60 ] || seconds=60
while [ "$seconds" -gt 0 ]; do
  echo "${seconds}…"
  sleep 1
  seconds=$((seconds - 1))
done
if [ "$ALLINONEIME_LANGUAGE" = zh ]; then echo "时间到！"; else echo "Time's up!"; fi
