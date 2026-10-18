#!/bin/bash

# A Raycast Script Command, as Raycast reads it: AllInOneIME reads the same lines. `compact` is shown as a
# notice near the cursor (docs/extensions.md, "Raycast Script Commands").
#
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Word Count
# @raycast.mode compact
#
# Optional parameters:
# @raycast.icon 🔢
# @raycast.packageName Text
# @raycast.argument1 { "type": "text", "placeholder": "text" }
#
# Documentation:
# @raycast.description Counts the words and characters of the text.

words=$(printf '%s' "$1" | wc -w | tr -d ' ')
chars=$(printf '%s' "$1" | wc -m | tr -d ' ')
echo "$words words, $chars characters"
