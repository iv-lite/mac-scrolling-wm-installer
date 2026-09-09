#!/usr/bin/env bash
ORANGE="0xffd08770"
LABEL="0xffe5e9f0"

usage="$(top -l 1 -n 0 -s 0 2>/dev/null | grep 'CPU usage' | sed 's/.*[^0-9]\([0-9][0-9]*\.[0-9][0-9]*\)% user.*/\1/')"

if [ -z "$usage" ]; then
  usage="$(top -l 1 -n 0 2>/dev/null | grep 'CPU usage' | awk -F'%' '{print $1}' | awk '{print $NF}')"
fi

if [ -z "$usage" ]; then
  sketchybar --set "$NAME" label="--"
  exit 0
fi

sketchybar --set "$NAME" icon="" icon.color="$ORANGE" label=" $(printf '%.0f' "$usage")%" label.color="$LABEL"