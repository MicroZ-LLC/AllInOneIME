#!/bin/bash
# `@convert 10 km`: the amount in the other units of its kind, as you type. The bundle's `precision`
# preference arrives as ALLINONEIME_PREF_PRECISION; the table is shared with @unitlist (lib/).

printf '%s\n' "$1" | awk -v precision="${ALLINONEIME_PREF_PRECISION:-2}" -f "$ALLINONEIME_EXTENSION_DIR/lib/units.awk"
