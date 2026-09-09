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
echo "   • Uninstall brew packages (you'll choose which to keep)"
echo "     rift, sketchybar, borders, tccutil-rs, jq, nowplaying-cli,"
echo "     ghostty, font-hack-nerd-font"
echo "   • Untap repos no longer needed (acsandmann/tap,"
echo "     FelixKratz/formulae, uinaf/tap)"
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
# 4. Uninstall brew packages + untaps (interactive keep menu)
# ─────────────────────────────────────────────────────────────
if command -v brew >/dev/null 2>&1; then
	echo ""
	note "Reviewing installed brew packages..."

	# Installed-package catalog: name, type, originating tap (if any)
	declare -a pkg_names pkg_types pkg_taps
	n=0
	add_pkg() {
		local name="$1" type="$2" tap="${3:-}"
		if brew list --"$type" "$name" >/dev/null 2>&1; then
			pkg_names[$n]="$name"
			pkg_types[$n]="$type"
			pkg_taps[$n]="$tap"
			n=$(( n + 1 ))
		fi
	}

	add_pkg rift            formula acsandmann/tap
	add_pkg sketchybar      formula FelixKratz/formulae
	add_pkg borders         formula FelixKratz/formulae
	add_pkg tccutil-rs      formula uinaf/tap
	add_pkg nowplaying-cli  formula
	add_pkg jq              formula
	add_pkg ghostty         cask
	add_pkg font-hack-nerd-font cask

	if [ "$n" -eq 0 ]; then
		warn "No packages from this setup are installed — nothing to uninstall."
	else
		echo ""
		echo "  Installed packages from this setup:"
		i=0
		while [ "$i" -lt "$n" ]; do
			echo "    [$(( i + 1 ))] ${pkg_names[$i]}"
			i=$(( i + 1 ))
		done
		echo ""
		echo "  Enter the numbers you want to KEEP (space-separated,"
		read -r -p '  e.g. "3 6"), or press Enter to remove all: ' keep_answer

		# Normalize the answer into a guarded space-delimited set: " 1 3 "
		keep_set=""
		for num in ${keep_answer:-}; do
			case "$num" in
				''|*[!0-9]*) continue ;;
			esac
			if [ "$num" -ge 1 ] && [ "$num" -le "$n" ]; then
				keep_set="$keep_set $num"
			fi
		done
		keep_set=" $keep_set "

		echo ""
		i=0
		remove_taps=""
		while [ "$i" -lt "$n" ]; do
			num=$(( i + 1 ))
			name="${pkg_names[$i]}"
			type="${pkg_types[$i]}"
			tap="${pkg_taps[$i]}"
			if [[ " $keep_set " == *" $num "* ]]; then
				ok "Keeping $name"
			else
				if brew uninstall --"$type" "$name" >/dev/null 2>&1; then
					ok "Uninstalled $name"
				else
					warn "$name could not be uninstalled (best-effort)"
				fi
				if [ -n "$tap" ]; then
					case "$remove_taps" in
						*" $tap "*) ;;
						*) remove_taps="$remove_taps $tap " ;;
					esac
				fi
			fi
			i=$(( i + 1 ))
		done

		# Only untap repos whose packages were actually removed
		if [ -n "$remove_taps" ]; then
			for tap in $remove_taps; do
				brew untap "$tap" >/dev/null 2>&1 || true
			done
			ok "Brew taps removed (best-effort)"
		fi
	fi
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