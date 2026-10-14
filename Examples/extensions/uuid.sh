#!/bin/bash
# A new random UUID, inserted where you type. It takes no input: ⏎ on its name runs it.
#
# @allinoneime.schemaVersion 1
# @allinoneime.title New UUID
# @allinoneime.icon number
# @allinoneime.input none

uuidgen | tr '[:upper:]' '[:lower:]'
