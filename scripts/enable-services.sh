#!/usr/bin/env bash
set -euo pipefail

CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
RESET=$'\033[0m'

note() { echo "  ${CYAN}→ $*${RESET}"; }
ok()   { echo "  ${GREEN}✓ $*${RESET}"; }
warn() { echo "  ${YELLOW}⚠ $*${RESET}"; }

# ─────────────────────────────────────────────────────────────
# Rift (launchd service)
# ─────────────────────────────────────────────────────────────
if command -v rift >/dev/null 2>&1; then
	note "Starting Rift..."
	if rift service start; then
		ok "Rift running"
	else
		warn "Rift failed to start — verify Accessibility permission was granted, then run: rift service start"
	fi
fi

# ─────────────────────────────────────────────────────────────
# SketchyBar (brew services)
# ─────────────────────────────────────────────────────────────
if command -v sketchybar >/dev/null 2>&1; then
	note "Starting SketchyBar..."
	brew services start sketchybar >/dev/null 2>&1 || true
	ok "SketchyBar service started"
fi

# ─────────────────────────────────────────────────────────────
# JankyBorders (brew services)
# ─────────────────────────────────────────────────────────────
if command -v borders >/dev/null 2>&1; then
	note "Starting JankyBorders..."
	brew services start borders >/dev/null 2>&1 || true
	ok "JankyBorders service started"
fi

echo ""
ok "Services enabled"