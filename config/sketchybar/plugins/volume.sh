#!/usr/bin/env bash
PURPLE="0xffb48ead"
LABEL="0xffe5e9f0"

VOLUME="$INFO"
if [ -z "$VOLUME" ]; then
  VOLUME="$(osascript -e 'output volume of (get volume settings)')"
fi

if [ "$VOLUME" -eq 0 ]; then
  icon=""
elif [ "$VOLUME" -lt 40 ]; then
  icon=""
elif [ "$VOLUME" -lt 70 ]; then
  icon=""
else
  icon=""
fi

sketchybar --set "$NAME" icon="$icon" icon.color="$PURPLE" label="$VOLUME%" label.color="$LABEL"