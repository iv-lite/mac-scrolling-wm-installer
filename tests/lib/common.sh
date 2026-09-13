#!/usr/bin/env bash
# Shared helpers for the preview test workflow.
# Intended to be sourced by tests/preview only.
#
# Detects the host OS and sources the matching backend:
#   Darwin -> backend_tart.sh  (Apple Silicon macOS host, Tart hypervisor)
#   Linux  -> backend_qemu.sh (x86_64 Linux host, QEMU/KVM + OpenCore)
# Every backend implements the same contract:
#   ensure_deps, cmd_setup, vm_exists, vm_is_running, vm_ip, vm_start,
#   vm_stop, vm_delete, sync_repo, backend_screenshot, backend_snapshot,
#   backend_restore, backend_clean

[ -n "${ROOT:-}" ] || { echo "error: ROOT not set — run via tests/preview" >&2; exit 1; }

GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; CYAN=$'\033[0;36m'; RED=$'\033[0;31m'; RESET=$'\033[0m'

note() { echo "  ${CYAN}→ $*${RESET}"; }
ok()   { echo "  ${GREEN}✓ $*${RESET}"; }
warn() { echo "  ${YELLOW}⚠ $*${RESET}"; }
die()  { echo "  ${RED}✗ $*${RESET}"; exit 1; }

# Host OS detection — used to pick the backend below.
HOST_OS="$(uname -s)"

case "$HOST_OS" in
  Darwin)
    source "$ROOT/tests/lib/backend_tart.sh"
    ;;
  Linux)
    [ "$(uname -m)" = "x86_64" ] || die "macOS guests are only possible on x86_64 Linux — ARM64 Linux is not supported"
    source "$ROOT/tests/lib/backend_qemu.sh"
    ;;
  *)
    die "unsupported host OS '$HOST_OS' (expected Darwin or Linux)"
    ;;
esac

# Generic SSH options shared by every backend. Backends extend the ssh/scp
# command lines via SSH_PORT_ARG (e.g. '-p <port>' for QEMU) and
# SCP_PORT_ARG (scp needs '-P <port>').
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

wait_ssh() {
  note "Waiting for guest SSH (up to 10 min)..."
  local tries=120 i=0 ip=""
  while [ "$i" -lt "$tries" ]; do
    ip="$(vm_ip)"
    if [ -n "$ip" ] && sshpass -p admin ssh $SSH_PORT_ARG $SSH_OPTS \
          admin@"$ip" true 2>/dev/null; then
      ok "guest is up at admin@$ip"
      return 0
    fi
    sleep 5
    i=$((i + 1))
  done
  die "guest did not become reachable over SSH in time"
}

ensure_running() {
  if ! vm_is_running; then
    warn "VM is not running — starting it"
    vm_start
    wait_ssh
  fi
}

guest() {
  ensure_running
  local ip=""
  ip="$(vm_ip)"
  sshpass -p admin ssh $SSH_PORT_ARG $SSH_OPTS admin@"$ip" "$@"
}

guest_sudo() {
  ensure_running
  local ip=""
  ip="$(vm_ip)"
  sshpass -p admin ssh $SSH_PORT_ARG $SSH_OPTS admin@"$ip" "echo admin | sudo -S $*"
}

scp_from_guest() {
  ensure_running
  local ip=""
  ip="$(vm_ip)"
  sshpass -p admin scp $SCP_PORT_ARG $SSH_OPTS "admin@$ip:$1" "$2"
}