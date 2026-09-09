#!/usr/bin/env bash
BLUE="0xff81a1c1"
LABEL="0xffe5e9f0"

pct="$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')"

if [ -z "$pct" ]; then
  sketchybar --set "$NAME" label="--"
  exit 0
fi

sketchybar --set "$NAME" icon="" icon.color="$BLUE" label=" $pct%" label.color="$LABEL"