#!/usr/bin/env bash
# Shortcut cheat sheet — cycles: collapsed -> page 1 -> page 2 -> collapsed.
# Triggered by Rift binding Cmd+Option+K and by clicking the item.
# Note: '+' splits a label into separate chips (part of SketchyBar syntax),
# so modifiers are written with spaces, never '+'.

case "$SENDER" in
  cheatsheet_toggle) ;;
  *) exit 0 ;;
esac

STOP="${CONFIG_DIR:-$HOME/.config/sketchybar}/.cheatsheet"
PAGE=0
if [ -f "$STOP" ]; then
  PAGE=$(cat "$STOP" 2>/dev/null || echo 0)
fi

case "$PAGE" in
  0)
    sketchybar --set "$NAME" label="Alt Arrows focus + Alt Shift Arrows move + Alt Ctrl Arrows resize + Alt 1-9 ws + Alt Shift 1-9 tows + Cmd Alt Arrows display + Cmd Alt Shift Arrows todisp + Cmd Ctrl T ghostty" \
      label.background.drawing=on
    printf '%s' 1 > "$STOP"
    ;;
  1)
    sketchybar --set "$NAME" label="Alt Z tile + Alt F fullscreen + Alt Shift F fillgaps + Alt V float + Alt Shift Space floatfocus + Alt Q close + Alt W stack + Alt / orient + Alt [ ] strip + Alt Shift R reload" \
      label.background.drawing=on
    printf '%s' 2 > "$STOP"
    ;;
  2)
    sketchybar --set "$NAME" label=" " \
      label.background.drawing=off
    rm -f "$STOP"
    ;;
esac