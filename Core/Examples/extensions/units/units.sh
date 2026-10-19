#!/bin/bash
# The units @convert knows, shown in the panel.

echo list | awk -f "$ALLINONEIME_EXTENSION_DIR/lib/units.awk"
