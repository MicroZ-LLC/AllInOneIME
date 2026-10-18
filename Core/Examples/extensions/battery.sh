#!/bin/bash
# The battery's charge beside its name in the command list (a `status`, every minute); running it shows
# the details.
#
# @allinoneime.schemaVersion 1
# @allinoneime.title Battery
# @allinoneime.icon battery.75percent
# @allinoneime.input none
# @allinoneime.output show
# @allinoneime.status self
# @allinoneime.statusRefresh 1m

info=$(pmset -g batt)
percent=$(printf '%s\n' "$info" | grep -Eo '[0-9]+%' | head -n 1)
if [ -n "$ALLINONEIME_STATUS" ]; then
  echo "${percent:-AC}"
else
  printf '%s\n' "$info"
fi
