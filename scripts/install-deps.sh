#!/usr/bin/env bash
set -euo pipefail

GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
RED=$'\033[0;31m'
RESET=$'\033[0m'

note()  { echo "  ${CYAN}→ $*${RESET}"; }
ok()    { echo "  ${GREEN}✓ $*${RESET}"; }
warn()  { echo "  ${YELLOW}⚠ $*${RESET}"; }
fail()  { echo "  ${RED}✗ $*${RESET}"; }

# ─────────────────────────────────────────────────────────────
# Homebrew
# ─────────────────────────────────────────────────────────────
if ! command -v brew >/dev/null 2>&1; then
	note "Homebrew not found. Installing..."
	NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	if [ -x /opt/homebrew/bin/brew ]; then
		eval "$(/opt/homebrew/bin/brew shellenv)"
	elif [ -x /usr/local/bin/brew ]; then
		eval "$(/usr/local/bin/brew shellenv)"
	else
		fail "Homebrew installed but 'brew' not on PATH. Add it and re-run."
		exit 1
	fi
	ok "Homebrew installed"
else
	ok "Homebrew already installed"
fi

command -v brew >/dev/null 2>&1 || eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)"
command -v brew >/dev/null 2>&1 || eval "$(/usr/local/bin/brew shellenv 2>/dev/null || true)"

# ─────────────────────────────────────────────────────────────
# Core CLI deps
# ─────────────────────────────────────────────────────────────
note "Installing core CLI tools (jq, tccutil-rs, nowplaying-cli)..."
for pkg in jq; do
	if brew list "$pkg" >/dev/null 2>&1; then
		ok "$pkg already installed"
	else
		brew install "$pkg"
		ok "$pkg installed"
	fi
done

# tccutil-rs (user TCC db grants, no SIP disable needed)
if command -v tccutil-rs >/dev/null 2>&1; then
	ok "tccutil-rs already installed"
else
	note "Installing tccutil-rs from uinaf/tap..."
	brew tap uinaf/tap
	brew install tccutil-rs
	ok "tccutil-rs installed"
fi

# nowplaying-cli (media widget). Non-fatal: media widget silently disabled if missing.
if command -v nowplaying-cli >/dev/null 2>&1 || brew list nowplaying-cli >/dev/null 2>&1; then
	ok "nowplaying-cli already installed"
else
	if brew install nowplaying-cli; then
		ok "nowplaying-cli installed"
	else
		warn "nowplaying-cli install failed — media widget will show placeholder"
	fi
fi

# ─────────────────────────────────────────────────────────────
# Nerd Font (icons for SketchyBar)
# ─────────────────────────────────────────────────────────────
note "Installing Hack Nerd Font (SketchyBar icons)..."
if brew list --cask font-hack-nerd-font >/dev/null 2>&1; then
	ok "Hack Nerd Font already installed"
else
	brew install --cask font-hack-nerd-font
	ok "Hack Nerd Font installed"
fi

echo ""
ok "Dependencies ready"