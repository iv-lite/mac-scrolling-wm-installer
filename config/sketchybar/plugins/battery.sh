#!/usr/bin/env bash
GREEN="0xffa3be8c"
YELLOW="0xffebcb8b"
ORANGE="0xffd08770"
RED="0xffbf616a"
LABEL="0xffe5e9f0"

info="$(pmset -g batt)"
percent="$(echo "$info" | grep -Eo '[0-9]+%' | cut -d% -f1)"
charging="$(echo "$info" | grep -c 'AC Power' || true)"

if [ -z "$percent" ]; then
  sketchybar --set "$NAME" icon="" label=""
  exit 0
fi

if [ "$percent" -ge 90 ]; then
  icon="" color="$GREEN"
elif [ "$percent" -ge 60 ]; then
  icon="" color="$GREEN"
elif [ "$percent" -ge 30 ]; then
  icon="" color="$YELLOW"
elif [ "$percent" -ge 10 ]; then
  icon="" color="$ORANGE"
else
  icon="" color="$RED"
fi

if [ "$charging" -gt 0 ]; then
  icon=""
fi

sketchybar --set "$NAME" icon="$icon" icon.color="$color" label="$percent%" label.color="$LABEL"