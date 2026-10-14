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

# macOS's default voice speaks only its own language: Chinese, Korean, Japanese or Hindi text gets a voice of
# that language (the first one installed), anything else the default voice.
locale=$(printf %s "$1" | perl -CS -ne 'print /[\p{Hiragana}\p{Katakana}]/ ? "ja_JP" : /\p{Han}/ ? "zh_CN"
    : /\p{Hangul}/ ? "ko_KR" : /\p{Devanagari}/ ? "hi_IN" : ""')
voice=
[ -n "$locale" ] && voice=$(say -v '?' | sed -nE "s/^(.*[^ ]) +$locale +#.*/\1/p" | head -1)
if [ -n "$voice" ]; then say -v "$voice" -- "$1"; else say -- "$1"; fi
if [ "$ALLINONEIME_LANGUAGE" = zh ]; then echo "说完了"; else echo "Said it"; fi
