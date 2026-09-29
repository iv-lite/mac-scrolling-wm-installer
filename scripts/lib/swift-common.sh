#!/usr/bin/env bash
# Shared Swift-daemon helpers for install-paneru / enable-services /
# repair-paneru / dev-swift-watch. Source-only (no side effects).
#   source "$SCRIPT_DIR/lib/swift-common.sh"
#
# Single source of truth for: label + identifier, bindir lookup, pq wrapper
# (PANERU_MACH_SERVICE pin), health polls, and launchd start/stop.
# `pq` reaches the daemon over its Mach XPC service. The installed plist
# pins PANERU_MACH_SERVICE to the Swift label (the daemon default since
# upstream 0d3c2ab; renamed to the iv-lite identity in d04db61), so prefer
# the pin; fall back to the bare invocation for daemons without it.

PANERU_SWIFT_LABEL="${PANERU_SWIFT_LABEL:-com.github.iv-lite.paneru-swift}"
PANERU_SWIFT_ID="${PANERU_SWIFT_ID:-com.github.iv-lite.paneru-swift}"
# Previous Swift label (pre-d04db61): one-time migration stops it and
# removes its plist/logs on install. The Rust label
# (com.github.karinushka.paneru, no suffix) is never matched.
PANERU_SWIFT_OLD_LABEL="${PANERU_SWIFT_OLD_LABEL:-com.github.karinushka.paneru.swift}"

# Find an installed binary by name: PATH first, then known bindirs.
# Usage: find_installed_bin paneru-swift  -> prints path or nothing.
find_installed_bin() {
	local name="$1" candidate
	candidate="$(command -v "$name" 2>/dev/null || true)"
	if [ -n "$candidate" ]; then
		echo "$candidate"
		return 0
	fi
	for candidate in "/opt/homebrew/bin/$name" "/usr/local/bin/$name" "$HOME/.local/bin/$name"; do
		if [ -x "$candidate" ]; then
			echo "$candidate"
			return 0
		fi
	done
	return 1
}

swift_bootstrapped() {
	launchctl print "gui/$(id -u)/$PANERU_SWIFT_LABEL" >/dev/null 2>&1
}

# pq wrapper with Mach-service pin + bare fallback (covers pre-0d3c2ab
# binaries defaulting to the base name, and pre-d04db61 binaries on the
# old karinushka.suffixed name). Needs PQ_BIN set.
swift_pq() {
	if [ -n "${PQ_BIN:-}" ]; then
		PANERU_MACH_SERVICE="$PANERU_SWIFT_LABEL" "$PQ_BIN" "$@" >/dev/null 2>&1 \
			|| "$PQ_BIN" "$@" >/dev/null 2>&1
	else
		return 1
	fi
}

# 1 when the Swift agent answers `pq state`, or (without pq) when the
# agent is bootstrapped and the process is alive. 0 otherwise.
swift_healthy() {
	if [ -n "${PQ_BIN:-}" ]; then
		swift_pq state
	else
		swift_bootstrapped && pgrep -qx paneru-swift >/dev/null 2>&1
	fi
}

# Wait up to $1 seconds (default 10) for `swift_healthy`. 0 = healthy.
swift_wait_healthy() {
	local tries="${1:-10}" i
	for i in $(seq 1 "$tries"); do
		if swift_healthy; then
			return 0
		fi
		sleep 1
	done
	return 1
}

# Stop and remove the previous Swift agent (pre-d04db61 label) so two
# Swift agents never overlap. Mirrors upstream install-service.sh: only
# the old Swift label is matched — the Rust agent is never touched.
swift_migrate_old_agent() {
	[ -n "${PANERU_SWIFT_OLD_LABEL:-}" ] || return 0
	[ "$PANERU_SWIFT_OLD_LABEL" != "$PANERU_SWIFT_LABEL" ] || return 0
	if launchctl print "gui/$(id -u)/$PANERU_SWIFT_OLD_LABEL" >/dev/null 2>&1; then
		launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/$PANERU_SWIFT_OLD_LABEL.plist" >/dev/null 2>&1 \
			|| launchctl kill SIGTERM "gui/$(id -u)/$PANERU_SWIFT_OLD_LABEL" >/dev/null 2>&1 || true
		launchctl disable "gui/$(id -u)/$PANERU_SWIFT_OLD_LABEL" >/dev/null 2>&1 || true
	fi
	rm -f "$HOME/Library/LaunchAgents/$PANERU_SWIFT_OLD_LABEL.plist"
	rm -f "/tmp/${PANERU_SWIFT_OLD_LABEL}_$(id -u).out.log" "/tmp/${PANERU_SWIFT_OLD_LABEL}_$(id -u).err.log"
}

# Start (or restart) the Swift agent from its plist: enable + kickstart
# when already bootstrapped, else bootstrap. 0 on launchctl success.
swift_start_agent() {
	local plist="$HOME/Library/LaunchAgents/$PANERU_SWIFT_LABEL.plist"
	[ -f "$plist" ] || return 1
	launchctl enable "gui/$(id -u)/$PANERU_SWIFT_LABEL" >/dev/null 2>&1 || true
	if swift_bootstrapped; then
		launchctl kickstart "gui/$(id -u)/$PANERU_SWIFT_LABEL" >/dev/null 2>&1
	else
		launchctl bootstrap "gui/$(id -u)" "$plist" >/dev/null 2>&1
	fi
}

# Stop the Swift agent without removing its plist. Same semantics as
# upstream swift-daemon/install-service.sh: bootout, else SIGTERM the job,
# then disable so it does not respawn under a Rust fallback.
swift_stop_agent() {
	launchctl bootout "gui/$(id -u)/$PANERU_SWIFT_LABEL" >/dev/null 2>&1 \
		|| launchctl kill SIGTERM "gui/$(id -u)/$PANERU_SWIFT_LABEL" >/dev/null 2>&1 || true
	launchctl disable "gui/$(id -u)/$PANERU_SWIFT_LABEL" >/dev/null 2>&1 || true
}
