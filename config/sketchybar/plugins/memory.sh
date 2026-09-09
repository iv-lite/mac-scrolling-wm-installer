#!/usr/bin/env bash
RED="0xffbf616a"
LABEL="0xffe5e9f0"

total_bytes="$(sysctl -n hw.memsize)"
page_size="$(sysctl -n hw.pagesize)"

# vm_stat reports page counts with a trailing dot; strip to digits only.
free_p="$(vm_stat | awk '/Pages free/ {print $3}' | tr -cd '0-9')"
active_p="$(vm_stat | awk '/Pages active/ {print $3}' | tr -cd '0-9')"
wired_p="$(vm_stat | awk '/Pages wired down/ {print $4}' | tr -cd '0-9')"
comp_p="$(vm_stat | awk '/Pages occupied by compressor/ {print $5}' | tr -cd '0-9')"

if [ -z "$free_p" ]; then
  sketchybar --set "$NAME" label="--"
  exit 0
fi

used_bytes=$(( (active_p + wired_p + comp_p) * page_size ))
pct=$(( used_bytes * 100 / total_bytes ))

sketchybar --set "$NAME" icon="" icon.color="$RED" label=" $pct%" label.color="$LABEL"