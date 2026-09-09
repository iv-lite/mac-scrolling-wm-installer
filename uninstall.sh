#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && pwd)"

GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
RED=$'\033[0;31m'
RESET=$'\033[0m'

note() { echo "  ${CYAN}→ $*${RESET}"; }
ok()   { echo "  ${GREEN}✓ $*${RESET}"; }
warn() { echo "  ${YELLOW}⚠ $*${RESET}"; }

echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║          Niri-like macOS setup — uninstall    ║"
echo "  ╚══════════════════════════════════════════════╝"
echo ""
echo "  This will:"
echo "   • Stop/remove Rift, SketchyBar, JankyBorders services"
echo "   • Revoke Accessibility permissions"
echo "   • Move configs to ~/.config/backups (not deleted)"
echo "   • Uninstall brew packages: rift, sketchybar, borders,"
echo "     tccutil-rs, nowplaying-cli, jq, font-hack-nerd-font"
echo "   • Untap: acsandmann/tap, FelixKratz/formulae, uinaf/tap"
echo "   • Revert system defaults (separate Spaces, hidden menu bar)"
echo ""
read -r -p "  Continue? [y/N] " answer
if [ "${answer:-n}" != "y" ] && [ "${answer:-n}" != "Y" ]; then
	echo ""
	echo "  Aborted. Nothing was changed."
	exit 0
fi

# ─────────────────────────────────────────────────────────────
# 1. Stop & remove services
# ─────────────────────────────────────────────────────────────
echo ""
note "Stopping services..."

if command -v rift >/dev/null 2>&1; then
	if rift service stop >/dev/null 2>&1; then
		ok "Rift stopped"
	fi
	if rift service uninstall >/dev/null 2>&1; then
		ok "Rift service removed"
	fi
fi

if command -v sketchybar >/dev/null 2>&1; then
	brew services stop sketchybar >/dev/null 2>&1 || true
	ok "SketchyBar service stopped"
fi

if command -v borders >/dev/null 2>&1; then
	brew services stop borders >/dev/null 2>&1 || true
	ok "JankyBorders service stopped"
fi

# ─────────────────────────────────────────────────────────────
# 2. Revoke Accessibility permissions
# ─────────────────────────────────────────────────────────────
echo ""
note "Revoking Accessibility permissions..."
if command -v tccutil-rs >/dev/null 2>&1; then
	for bin in "$(command -v rift 2>/dev/null || true)" \
	           "$(command -v sketchybar 2>/dev/null || true)" \
	           "$(command -v borders 2>/dev/null || true)"; do
		if [ -n "$bin" ] && [ -x "$bin" ]; then
			tccutil-rs revoke --user Accessibility "$bin" >/dev/null 2>&1 || true
		fi
	done
	ok "Accessibility grants revoked (best-effort)"
else
	warn "tccutil-rs not installed — skip revoking (also fine)"
fi

# ─────────────────────────────────────────────────────────────
# 3. Remove configs (moved to backup, not destroyed)
# ─────────────────────────────────────────────────────────────
echo ""
note "Removing configs..."

BACKUP_DIR="$HOME/.config/backups/uninstall-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

for dir in ~/.config/rift ~/.config/sketchybar ~/.config/borders; do
	if [ -d "$dir" ]; then
		mv "$dir" "$BACKUP_DIR/"
		ok "Moved $dir → $BACKUP_DIR/$(basename "$dir")"
	else
		warn "$dir not found — skipping"
	fi
done

# Clean up backup dir if nothing was moved
if [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
	rmdir "$BACKUP_DIR" 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────
# 4. Uninstall brew packages + untaps
# ─────────────────────────────────────────────────────────────
echo ""
note "Uninstalling brew packages..."

if command -v brew >/dev/null 2>&1; then
	brew uninstall rift >/dev/null 2>&1 && ok "Uninstalled rift" || warn "rift not installed — skipping"
	brew uninstall sketchybar >/dev/null 2>&1 && ok "Uninstalled sketchybar" || warn "sketchybar not installed — skipping"
	brew uninstall borders >/dev/null 2>&1 && ok "Uninstalled borders" || warn "borders not installed — skipping"
	brew uninstall tccutil-rs >/dev/null 2>&1 && ok "Uninstalled tccutil-rs" || warn "tccutil-rs not installed — skipping"
	brew uninstall nowplaying-cli >/dev/null 2>&1 && ok "Uninstalled nowplaying-cli" || warn "nowplaying-cli not installed — skipping"
	brew uninstall jq >/dev/null 2>&1 && ok "Uninstalled jq" || warn "jq not installed — skipping"
	brew uninstall --cask font-hack-nerd-font >/dev/null 2>&1 && ok "Uninstalled font-hack-nerd-font" || warn "font-hack-nerd-font not installed — skipping"

	brew untap acsandmann/tap >/dev/null 2>&1 || true
	brew untap FelixKratz/formulae >/dev/null 2>&1 || true
	brew untap uinaf/tap >/dev/null 2>&1 || true
	ok "Brew taps removed (best-effort)"
else
	warn "brew not found — skipping package removal"
fi

# ─────────────────────────────────────────────────────────────
# 5. Revert system defaults
# ─────────────────────────────────────────────────────────────
echo ""
note "Reverting system defaults..."

# "Displays have separate Spaces" off (spaces span all displays)
defaults write com.apple.spaces "spans-displays" -bool true 2>/dev/null || true
# Restore visible menu bar
defaults delete NSGlobalDomain _HIHideMenuBar 2>/dev/null || true
defaults delete NSGlobalDomain AppleMenuBarVisibleInFullscreen 2>/dev/null || true
ok "System defaults reverted"

killall SystemUIServer 2>/dev/null || true
killall Finder 2>/dev/null || true

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────
echo ""
echo "  ${GREEN}══════════════════════════════════════════════${RESET}"
echo "  ${GREEN}  Uninstall complete.${RESET}"
echo "  ${GREEN}══════════════════════════════════════════════${RESET}"
echo ""
warn "A logout/login is advised for settings to fully revert."
echo ""
if [ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
	echo "  Configs backed up at: $BACKUP_DIR"
	echo "  (copy back to ~/.config to restore)"
fi