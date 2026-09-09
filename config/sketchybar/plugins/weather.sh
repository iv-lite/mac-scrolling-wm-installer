#!/usr/bin/env bash
YELLOW="0xffebcb8b"
LABEL="0xffe5e9f0"
MUTED="0xff4c566a"

data="$(curl -s --max-time 5 "https://wttr.in/?format=%C+%t" 2>/dev/null)"

if [ -z "$data" ]; then
  sketchybar --set "$NAME" icon="" icon.color="$MUTED" label="" label.color="$MUTED"
  exit 0
fi

condition="${data%% *}"
temp_and_rest="${data#* }"
temp="${temp_and_rest%% *}"

icon=""
case "$condition" in
  *Clear*)
    icon=""
    ;;
  *Sunny*)
    icon=""
    ;;
  *Partly*)
    icon=""
    ;;
  *Cloud*|*Overcast*)
    icon=""
    ;;
  *Fog*|*Mist*)
    icon=""
    ;;
  *Rain*|*Drizzle*)
    icon=""
    ;;
  *Thunder*)
    icon=""
    ;;
  *Snow*)
    icon=""
    ;;
esac

sketchybar --set "$NAME" icon="$icon" icon.color="$YELLOW" label=" $temp" label.color="$LABEL"