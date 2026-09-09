#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && pwd)"

GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
RED=$'\033[0;31m'
RESET=$'\033[0m'

run_step() {
	local name="$1"
	echo ""
	echo "──────────────────────────────────────────────"
	echo "  ${CYAN}▶ ${name}${RESET}"
	echo "──────────────────────────────────────────────"
	bash "$REPO_ROOT/scripts/$name.sh"
	local status=$?
	if [ $status -ne 0 ]; then
		echo ""
		echo "  ${RED}✗ '$name' failed (exit $status).${RESET}"
		exit 1
	fi
	echo "  ${GREEN}✓ done${RESET}"
}

echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║   Rift + SketchyBar + JankyBorders installer ║"
echo "  ║            niri-like macOS setup              ║"
echo "  ╚══════════════════════════════════════════════╝"

run_step install-deps
run_step configure-system
run_step install-rift
run_step install-sketchybar
run_step install-borders
run_step grant-permissions
run_step enable-services

echo ""
echo "  ${GREEN}══════════════════════════════════════════════${RESET}"
echo "  ${GREEN}  Installation complete!${RESET}"
echo "  ${GREEN}══════════════════════════════════════════════${RESET}"
echo ""
echo "  ${YELLOW}⚠ A logout/login is required for these to take effect:${RESET}"
echo "     - Displays have separate Spaces"
echo "     - Hidden native menu bar (SketchyBar replaces it)"
echo ""
echo "  ${YELLOW}⚠ After the next login:${RESET}"
echo "     - Rift tiles every Space automatically (press Option+Z to",
echo "       toggle tiling on a Space if you ever want it unmanaged)"
echo "     - If accessibility grants failed above, grant them manually:"
echo "       System Settings → Privacy & Security → Accessibility"
echo ""
echo "  ${CYAN}Usage:${RESET}"
echo "     Option+Arrows        move focus between windows"
echo "     Option+Shift+Arrows  move windows"
echo "     Option+1..9          switch Rift workspace"
echo "     Option+Shift+1..9    move window to workspace"
echo "     Ctrl+Left/Right      switch macOS Spaces (system default)"
echo "     Cmd+Option+Arrows    focus display"
echo "     Cmd+Option+Shift+Arrows  move window to display"
echo "     Option+F             toggle fullscreen"
echo "     Option+V             toggle floating"
echo "     Option+Q             close window"
echo "     Ctrl+Cmd+T           open Ghostty"
echo ""
echo "  Log out now, then back in (Cmd+Shift+Q)."