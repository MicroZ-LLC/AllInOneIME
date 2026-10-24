#!/bin/bash
# `@bm swi`: the bookmarks whose title has the text. Each one is three rows, one for each row action: open it
# (`open`), copy its address (`copy`), or run this script again for its details (`run`: a second step, with
# ALLINONEIME_ACTION=run and the row's arg as $1). A last row is information only (`valid: false`). With
# ALLINONEIME_COMPLETION=load, the list its suggestions come from (below).

file=${ALLINONEIME_PREF_FILE:-$ALLINONEIME_EXTENSION_DIR/bookmarks.txt}
file=${file/#\~/$HOME}

json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

if [ "$ALLINONEIME_COMPLETION" = load ]; then
  # Suggestions (the command's `completion` in extension.json): every bookmark as an item to type, "bm." and its title
  # in small letters ("bm.swift", "bm.apple-developer"); a row puts in a Markdown link of it where the text field takes
  # one in the place of what was typed.
  items=""
  while IFS=$'\t' read -r title url; do
    [ -n "$title" ] || continue
    slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')
    t=$(json "$title"); u=$(json "$url")
    items+="${items:+,}{\"match\": \"bm.$slug\", \"title\": \"$t\", \"subtitle\": \"$u\", \"variables\": {\"title\": \"$t\", \"url\": \"$u\"}}"
  done < "$file"
  printf '{"items": [%s]}\n' "$items"
  exit
fi

if [ "$ALLINONEIME_ACTION" = run ]; then
  # The second step: one bookmark's details, as a summary with its detail.
  url=$(awk -F '\t' -v t="$1" '$1 == t { print $2 }' "$file")
  token=$([ -n "$ALLINONEIME_PREF_TOKEN" ] && echo "a checker token is set" || echo "no checker token")
  printf '{"summary": "%s", "detail": "%s · %s"}\n' "$(json "$url")" "$(json "$1")" "$token"
  exit
fi

query=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
items=""
count=0
while IFS=$'\t' read -r title url; do
  [ -n "$title" ] || continue
  lower=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')
  case "$lower" in *"$query"*) ;; *) continue ;; esac
  t=$(json "$title"); u=$(json "$url")
  items+="{\"title\": \"$t\", \"subtitle\": \"$u\", \"arg\": \"$u\", \"action\": \"open\"},"
  items+="{\"title\": \"Copy the address of $t\", \"arg\": \"$u\", \"action\": \"copy\"},"
  items+="{\"title\": \"Details of $t\", \"arg\": \"$t\", \"action\": \"run\"},"
  count=$((count + 1))
done < "$file"
items+="{\"title\": \"Bookmarks matching: $count\", \"subtitle\": \"$(json "$file")\", \"valid\": false}"
printf '{"items": [%s]}\n' "$items"
