#!/usr/bin/env bash
# Highlights the focused Rift workspace indicator.
# Triggered by 'rift_workspace_changed' (RIFT_WORKSPACE_ID env var, 0-based).

ACTIVE_BG="0xff88c0d0"
ACTIVE_FG="0xff2e3440"
INACTIVE_BG="0x00000000"
INACTIVE_FG="0xff4c566a"

if [ "$SENDER" = "rift_workspace_changed" ]; then
  SID="${NAME#space.}"
  ACTIVE_ID=$(( RIFT_WORKSPACE_ID + 1 ))
  if [ "$ACTIVE_ID" = "$SID" ]; then
    sketchybar --set "$NAME" background.color="$ACTIVE_BG" icon.color="$ACTIVE_FG"
  else
    sketchybar --set "$NAME" background.color="$INACTIVE_BG" icon.color="$INACTIVE_FG"
  fi
fi