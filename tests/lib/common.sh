#!/usr/bin/env bash
# Shared helpers for the Tart test workflow.
# Intended to be sourced by tests/tart-test.sh only.

[ -n "${ROOT:-}" ] || { echo "error: ROOT not set — run via tests/tart-test.sh" >&2; exit 1; }

VM="rift-test"
MOUNT_NAME="installer"
GUEST_DIR="/Volumes/My Shared Files/${MOUNT_NAME}"
GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; CYAN=$'\033[0;36m'; RED=$'\033[0;31m'; RESET=$'\033[0m'
SSHAUTH="-p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

note() { echo "  ${CYAN}→ $*${RESET}"; }
ok()   { echo "  ${GREEN}✓ $*${RESET}"; }
warn() { echo "  ${YELLOW}⚠ $*${RESET}"; }
die()  { echo "  ${RED}✗ $*${RESET}"; exit 1; }

base_image() {
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  case "$major" in
    26) echo "ghcr.io/cirruslabs/macos-tahoe-base:latest";;
    15) echo "ghcr.io/cirruslabs/macos-sequoia-base:latest";;
    14) echo "ghcr.io/cirruslabs/macos-sonoma-base:latest";;
    13) echo "ghcr.io/cirruslabs/macos-ventura-base:latest";;
    *)  die "cannot map host macOS major version '$major' to a Tart base image";;
  esac
}

is_running() {
  tart list 2>/dev/null | awk -v vm="$VM" '$1 ~ "^"vm"$" && $0 ~ /running/ { found=1 } END { exit !found }'
}

vm_exists() {
  tart list 2>/dev/null | awk -v vm="$VM" '$1 ~ "^"vm"$" { found=1 } END { exit !found }'
}

vm_ip() {
  tart ip "$VM" 2>/dev/null || echo ""
}

wait_ssh() {
  note "Waiting for guest SSH (up to 10 min)..."
  local tries=120 i=0 ip=""
  while [ "$i" -lt "$tries" ]; do
    ip="$(vm_ip)"
    if [ -n "$ip" ] && sshpass -p admin ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o ConnectTimeout=5 admin@"$ip" true 2>/dev/null; then
      ok "guest is up at admin@$ip"
      return 0
    fi
    sleep 5
    i=$((i + 1))
  done
  die "guest did not become reachable over SSH in time"
}

run_vm() {
  local extra=""
  if [ "${1:-}" = "--no-graphics" ]; then extra="--no-graphics"; fi
  if [ -n "$extra" ]; then warn "running headless — manual GUI grants will not be possible"; fi
  nohup tart run "$VM" --dir "${MOUNT_NAME}:${ROOT}" $extra >"$ROOT/tests/.tart-run.log" 2>&1 &
}

ensure_running() {
  if ! is_running; then
    warn "VM '$VM' is not running — starting it"
    run_vm
    wait_ssh
  fi
}

guest() {
  ensure_running
  local ip=""
  ip="$(vm_ip)"
  sshpass $SSHAUTH admin@"$ip" "$@"
}

guest_sudo() {
  ensure_running
  local ip=""
  ip="$(vm_ip)"
  sshpass -p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 admin@"$ip" "echo admin | sudo -S $*"
}

stop_vm() {
  if is_running; then
    note "Stopping '$VM'..."
    tart stop "$VM" || true
  fi
}