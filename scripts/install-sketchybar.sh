#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
RESET=$'\033[0m'

note() { echo "  ${CYAN}→ $*${RESET}"; }
ok()   { echo "  ${GREEN}✓ $*${RESET}"; }
warn() { echo "  ${YELLOW}⚠ $*${RESET}"; }

# ─────────────────────────────────────────────────────────────
# Install SketchyBar
# ─────────────────────────────────────────────────────────────
if command -v sketchybar >/dev/null 2>&1; then
	ok "SketchyBar already installed"
else
	note "Installing SketchyBar via Homebrew..."
	brew tap FelixKratz/formulae
	brew install sketchybar
	ok "SketchyBar installed"
fi

# ─────────────────────────────────────────────────────────────
# Config + plugins
# ─────────────────────────────────────────────────────────────
mkdir -p ~/.config/sketchybar/plugins

if [ -f ~/.config/sketchybar/sketchybarrc ]; then
	note "Existing sketchybarrc found — backing up"
	cp ~/.config/sketchybar/sketchybarrc ~/.config/sketchybar/sketchybarrc.bak
fi

cp "$REPO_ROOT/config/sketchybar/sketchybarrc" ~/.config/sketchybar/sketchybarrc
cp "$REPO_ROOT"/config/sketchybar/plugins/*.sh ~/.config/sketchybar/plugins/
chmod +x ~/.config/sketchybar/plugins/*.sh
ok "SketchyBar config + plugins installed (~/.config/sketchybar)"

warn "Do not run 'brew services start sketchybar' yet — enable-services.sh will do it."