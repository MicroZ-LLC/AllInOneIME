#!/bin/bash
# The time in cities around the world, as you type a city: pick one to insert it. A `list` that runs
# again every 30 seconds while it's shown, so the times stay current.
#
# @allinoneime.schemaVersion 1
# @allinoneime.title World Clock
# @allinoneime.description The time in cities around the world
# @allinoneime.icon 🕒
# @allinoneime.output list
# @allinoneime.argument1 {"type": "text", "placeholder": "city", "optional": true}
# @allinoneime.keywords time, timezone
# @allinoneime.queryDelay 100

query=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
items=""
for entry in London:Europe/London Paris:Europe/Paris Berlin:Europe/Berlin Dubai:Asia/Dubai Mumbai:Asia/Kolkata \
             Singapore:Asia/Singapore Shanghai:Asia/Shanghai Tokyo:Asia/Tokyo Sydney:Australia/Sydney \
             Sao_Paulo:America/Sao_Paulo New_York:America/New_York San_Francisco:America/Los_Angeles; do
  city=${entry%%:*}
  city=${city//_/ }
  zone=${entry#*:}
  lower=$(printf '%s' "$city" | tr '[:upper:]' '[:lower:]')
  case "$lower" in *"$query"*) ;; *) continue ;; esac
  time=$(TZ=$zone date +%H:%M)
  day=$(TZ=$zone date +%a)
  items+="{\"title\": \"$city  $time\", \"subtitle\": \"$day · $zone\", \"arg\": \"$time ($city)\", \"text\": {\"copy\": \"$time\"}},"
done
[ -n "$items" ] || items='{"title": "No city matches", "subtitle": "Try London, Tokyo or New York", "valid": false},'
printf '{"rerun": 30, "items": [%s]}\n' "${items%,}"
