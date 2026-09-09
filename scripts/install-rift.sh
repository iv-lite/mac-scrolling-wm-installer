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
# Install Rift
# ─────────────────────────────────────────────────────────────
if command -v rift >/dev/null 2>&1; then
	ok "Rift already installed: $(rift --version 2>/dev/null || echo '')"
else
	note "Installing Rift via Homebrew..."
	brew tap acsandmann/tap
	brew install acsandmann/tap/rift
	ok "Rift installed"
fi

# ─────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────
mkdir -p ~/.config/rift

if [ -f ~/.config/rift/config.toml ]; then
	note "Existing config found at ~/.config/rift/config.toml — backing up"
	cp ~/.config/rift/config.toml ~/.config/rift/config.toml.bak
fi

cp "$REPO_ROOT/config/rift/config.toml" ~/.config/rift/config.toml
ok "Rift config installed to ~/.config/rift/config.toml"

# ─────────────────────────────────────────────────────────────
# launchd service (applies Accessibility before start)
# ─────────────────────────────────────────────────────────────
note "Installing Rift launchd service..."
rift service install
ok "Rift service installed"

warn "Rift will be started by enable-services.sh after permissions are granted."