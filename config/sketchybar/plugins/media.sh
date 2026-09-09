#!/usr/bin/env bash
ICE="0xff88c0d0"
LABEL="0xffe5e9f0"
MUTED="0xff4c566a"

if ! command -v nowplaying-cli >/dev/null 2>&1; then
  sketchybar --set "$NAME" icon="" icon.color="$MUTED" label="" label.color="$MUTED"
  exit 0
fi

state="$(nowplaying-cli get state 2>/dev/null)"
title="$(nowplaying-cli get title 2>/dev/null)"
artist="$(nowplaying-cli get artist 2>/dev/null)"

if [ "$state" = "playing" ] && [ -n "$title" ]; then
  label="$title — $artist"
  if [ ${#label} -gt 40 ]; then
    label="${label:0:40}…"
  fi
  sketchybar --set "$NAME" icon="" icon.color="$ICE" label=" $label" label.color="$LABEL"
else
  sketchybar --set "$NAME" icon="" icon.color="$MUTED" label="" label.color="$MUTED"
fi