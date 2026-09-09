#!/usr/bin/env bash
set -euo pipefail

CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
RESET=$'\033[0m'

note() { echo "  ${CYAN}→ $*${RESET}"; }
ok()   { echo "  ${GREEN}✓ $*${RESET}"; }
warn() { echo "  ${YELLOW}⚠ $*${RESET}"; }

# Enable "Displays have separate Spaces".
# Counterintuitive: spans-displays = false ⇔ separate Spaces ON (macOS default).
if [ "$(defaults read com.apple.spaces spans-displays 2>/dev/null)" != "0" ]; then
	note "Enabling 'Displays have separate Spaces'..."
	defaults write com.apple.spaces "spans-displays" -bool false
	ok "spans-displays set to false (separate Spaces)"
else
	ok "'Displays have separate Spaces' already enabled"
fi

# Hide the native menu bar — SketchyBar replaces it.
if [ "$(defaults read NSGlobalDomain _HIHideMenuBar 2>/dev/null)" != "1" ]; then
	note "Hiding native menu bar..."
	defaults write NSGlobalDomain _HIHideMenuBar -bool true
	defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool true
	ok "menu bar hidden"
else
	ok "menu bar already hidden"
fi

# Attempt to apply immediately (logout/login still recommended for the Spaces setting).
killall SystemUIServer 2>/dev/null || true
killall Finder 2>/dev/null || true

warn "A logout/login is still required for these settings to fully take effect."