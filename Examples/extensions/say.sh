#!/bin/bash
# Says the text out loud. It asks first (`confirm`: the action key once shows "Run Say Aloud?", again runs it),
# and inserts nothing: what it prints last is a notice near the cursor (`silent`).
#
# @allinoneime.schemaVersion 1
# @allinoneime.title Say Aloud
# @allinoneime.icon 🔊
# @allinoneime.output silent
# @allinoneime.confirm true
# @allinoneime.argument1 {"type": "text", "placeholder": "what to say"}

say -- "$1"
if [ "$ALLINONEIME_LANGUAGE" = zh ]; then echo "说完了"; else echo "Said it"; fi
