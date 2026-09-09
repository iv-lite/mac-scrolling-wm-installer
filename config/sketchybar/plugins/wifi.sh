#!/usr/bin/env bash
CYAN="0xff8fbcbb"
LABEL="0xffe5e9f0"
OFF="0xff4c566a"

ssid=""
if device="$(networksetup -listallhardwareports 2>/dev/null | awk -F': ' '
    tolower($1) ~ /wi-fi/ { print $2; exit }')"; then
  ssid="$(networksetup -getairportnetwork "$device" 2>/dev/null | awk -F': ' '{print $2; exit}')"
fi

if [ -z "$ssid" ]; then
  sketchybar --set "$NAME" icon="" icon.color="$OFF" label="Off" label.color="$OFF"
else
  sketchybar --set "$NAME" icon="" icon.color="$CYAN" label="$ssid" label.color="$LABEL"
fi