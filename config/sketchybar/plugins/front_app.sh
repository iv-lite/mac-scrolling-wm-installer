#!/usr/bin/env bash
# Shows the currently focused app name (from front_app_switched $INFO).
BLUE="0xff81a1c1"

sketchybar --set "$NAME" label="$INFO" label.color="$BLUE"