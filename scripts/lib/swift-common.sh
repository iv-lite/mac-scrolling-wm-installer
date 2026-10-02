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

# Identity stamp for the installed Swift daemon (identifier + cdhash +
# path). A drift since the last install means the TCC identity changed
# (ad-hoc rebuild, renamed identifier, moved path) and any
# string-matched TCC row can no longer be trusted — grant-permissions
# forces the grant flow instead of reporting "already present".
PANERU_SWIFT_STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/paneru/swift-install-identity"

# CDHash of a binary (empty when codesign is missing/refuses). Needs
# -dvvv: plain -dv omits the hash on current toolchains.
swift_cdhash() {
	local bin="$1"
	codesign -dvvv "$bin" 2>&1 | grep -oE '^CDHash=[0-9a-f]+' | cut -d= -f2 | head -1 || true
}

# Designated-requirement identifier of a binary (empty when unavailable).
swift_designated_id() {
	local bin="$1"
	codesign -dv "$bin" 2>&1 | grep -oE 'Identifier=[^ ]+' | cut -d= -f2 | head -1 || true
}

# 0 when the binary's code signature verifies (ad-hoc included — it
# satisfies its own designated requirement); 1 when codesign reports a
# trust/format failure such as CSSMERR_TP_NOT_TRUSTED. That failure means
# the signing certificate is gone/untrusted, so the TCC identity the
# grant was cut for no longer resolves and the grant is dead even though
# a string-matched row still lists the binary.
swift_signature_trusted() {
	local bin="$1" out
	[ -n "$bin" ] && [ -e "$bin" ] || return 1
	command -v codesign >/dev/null 2>&1 || return 1
	if ! out="$(codesign --verify --verbose=2 "$bin" 2>&1)"; then
		return 1
	fi
	printf '%s' "$out" | grep -qE "CSSMERR|not signed|invalid signature" && return 1
	return 0
}

# Signing authority of a binary (self-signed cert name, Developer ID,
# or empty when ad-hoc/unsigned): cert rotation keeps cdhash but voids
# the grant, so the stamp tracks this too.
swift_cert() {
	local bin="$1"
	codesign -dvvv "$bin" 2>&1 | grep -oE '^Authority=.*' | head -1 | cut -d= -f2- || true
}

# Record the installed identity (called by install-paneru after sign+copy).
swift_write_stamp() {
	local bin="$1"
	mkdir -p "$(dirname "$PANERU_SWIFT_STAMP")" 2>/dev/null || true
	printf '%s\n%s\n%s\n%s\n' "$PANERU_SWIFT_ID" "$(swift_cdhash "$bin")" "$bin" "$(swift_cert "$bin")" > "$PANERU_SWIFT_STAMP"
}

# Stamp field N (1-based): 1 identifier, 2 cdhash, 3 path, 4 authority.
# Empty when missing.
swift_stamp_field() {
	local n="$1"
	[ -f "$PANERU_SWIFT_STAMP" ] || return 1
	sed -n "${n}p" "$PANERU_SWIFT_STAMP" | head -1 || true
}

# 0 when the installed binary drifted from the stamp (or no stamp
# exists yet): identifier, cdhash, path, or signing authority changed —
# existing TCC rows cannot be trusted and the grant flow must run
# unconditionally.
swift_stamp_drifted() {
	local bin="$1"
	[ -f "$PANERU_SWIFT_STAMP" ] || return 0
	[ "$(swift_stamp_field 1)" = "$PANERU_SWIFT_ID" ] || return 0
	[ -n "$(swift_cdhash "$bin")" ] || return 0
	[ "$(swift_stamp_field 2)" = "$(swift_cdhash "$bin")" ] || return 0
	[ "$(swift_stamp_field 3)" = "$bin" ] || return 0
	[ "$(swift_stamp_field 4)" = "$(swift_cert "$bin")" ] || return 0
	return 1
}

# Prove the Swift daemon's AX write path: answers queries AND shows no
# write denial since the check started. Prints one verdict line.
# Usage: swift_ax_proven [wait_secs]  ->  0 proven, 1 broken.
# A healthy-but-idle daemon (no managed windows, nothing written) proves
# by silence + stable identity; a stale ad-hoc rebuild can never reach
# here (install-paneru refuses it, grant-permissions forces re-grant).
swift_ax_proven() {
	local wait_secs="${1:-15}" log start_size i
	log="/tmp/${PANERU_SWIFT_LABEL}_$(id -u).out.log"
	if [ ! -f "$log" ]; then
		echo "no daemon log yet ($log)"
		return 1
	fi
	if command -v stat >/dev/null 2>&1; then
		start_size=$(stat -f%z "$log" 2>/dev/null || stat -c%s "$log" 2>/dev/null || echo 0)
	else
		start_size=0
	fi
	for i in $(seq 1 "$wait_secs"); do
		if tail -c "+$((start_size + 1))" "$log" 2>/dev/null | grep -qE "reposition denied|resize denied|GRANT LOST|SYSTEMIC denial"; then
			echo "daemon log shows denied AX writes (grant doesn't apply to this binary)"
			return 1
		fi
		if swift_healthy; then
			echo "daemon answers queries with no denied AX writes in the window"
			return 0
		fi
		sleep 1
	done
	echo "daemon not answering queries"
	return 1
}

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
