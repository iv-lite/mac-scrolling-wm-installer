#!/usr/bin/env bash
ICON_COLOR="0xff88c0d0"
LABEL_COLOR="0xffe5e9f0"

sketchybar --set "$NAME" \
  icon="" \
  label="$(date '+%a %d %b  %H:%M')" \
  icon.color="$ICON_COLOR" \
  label.color="$LABEL_COLOR"