#!/usr/bin/env bash
# Subcommands for the Tart test workflow.
# Intended to be sourced by tests/tart-test.sh after lib/common.sh.

usage() {
  cat <<EOF
Usage: ./tests/tart-test.sh <command>

  setup      Install tart+sshpass, clone the host-matched base image, tune resources
  up         Boot the VM (GUI by default; --no-graphics for headless) and wait for SSH
  install    Run install.sh inside the guest (via live host mount)
  access     Re-run the accessibility grant script in the guest
  login      Log out/in the GUI session to apply Spaces + menu-bar settings
  check      Query Rift state and installed formulae in the guest
  shot       Capture a screenshot into tests/screenshots/
  snapshot   Create 'bare' (fresh macOS) + 'provisioned' (after install) snapshots
  restore    Restore a snapshot: './tests/tart-test.sh restore bare'
  ssh        Open an interactive shell on the guest
  stop       Gracefully stop the VM
  delete     Stop and delete the VM entirely
  clean      Interactively remove the test VM, tart, sshpass, and base image
EOF
}

ensure_deps() {
  if [ "${TART_DEPS_OK:-}" = "1" ]; then return 0; fi
  if ! command -v brew >/dev/null 2>&1; then
    die "Homebrew is required — install it first (./install.sh can do this)"
  fi
  local need=""
  if ! command -v tart >/dev/null 2>&1; then need="$need cirruslabs/cli/tart"; fi
  if ! command -v sshpass >/dev/null 2>&1; then need="$need cirruslabs/cli/sshpass"; fi
  if [ -n "$need" ]; then
    note "Installing missing requirements:$need"
    brew install $need
  fi
  TART_DEPS_OK=1
}

cmd_setup() {
  ensure_deps
  local image
  image="$(base_image)"
  if ! vm_exists; then
    note "Cloning $image (first run downloads ~25 GB)..."
    tart clone "$image" "$VM"
  else
    ok "VM '$VM' already exists — skipping clone"
  fi
  note "Tuning resources (4 CPU / 8 GB)..."
  tart set "$VM" --cpus 4 --memory 8192 2>/dev/null || true
  ok "Setup done — run: ./tests/tart-test.sh up"
}

cmd_up() {
  local headless="${1:-}"
  if ! vm_exists; then die "VM '$VM' does not exist — run: ./tests/tart-test.sh setup"; fi
  if is_running; then
    note "VM '$VM' is already running ($(tart ip "$VM"))"
  else
    run_vm "$headless"
    wait_ssh
  fi
  echo ""
  ok "Connect anytime with:   ssh admin@$(vm_ip)"
}

cmd_install() {
  ensure_running
  note "Enabling passwordless sudo for 'admin' in guest..."
  guest_sudo "sh -c 'echo \"admin ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/100-admin && chmod 440 /etc/sudoers.d/100-admin'" || \
    warn "could not configure passwordless sudo — install may prompt for the admin password"
  note "Running install.sh inside the guest (live mount ${GUEST_DIR})..."
  guest "cd '${GUEST_DIR}' && ./install.sh"
  ok "install.sh finished in guest"
  warn "Re-run grants if Accessibility failed:  ./tests/tart-test.sh access"
  ask_cleanup
}

cmd_access() {
  ensure_running
  guest "bash '${GUEST_DIR}/scripts/grant-permissions.sh'" || true
  warn "If grants failed above, open the VM window and grant manually:"
  warn "System Settings → Privacy & Security → Accessibility → enable Rift, SketchyBar, Borders"
}

cmd_login() {
  ensure_running
  note "Restarting the login window to apply Spaces + menu-bar settings..."
  guest_sudo "killall loginwindow" || true
  sleep 15
  note "The GUI session is logging back in (auto-login)."
}

cmd_check() {
  ensure_running
  echo "── Rift workspaces ──"
  guest "rift-cli query workspaces" 2>&1 || true
  echo ""
  echo "── Installed formulae ──"
  guest "brew list --formula | grep -Ei 'rift|sketchybar|borders|jq|tccutil|nowplaying' || echo '(none found)'"
  echo ""
  echo "── SketchyBar items ──"
  guest "sketchybar --query bar 2>&1 | head -c 300 || true"
  ask_cleanup
}

ask_cleanup() {
  if [ ! -t 0 ]; then
    note "Test finished — clean up later with: ./tests/tart-test.sh clean"
    return 0
  fi
  echo ""
  local yn=""
  read -p "  Test finished. Clean up the test VM and tools now? [y/N] " yn
  case "$yn" in
    y|Y) cmd_clean;;
    *)   note "Kept everything — clean up later with: ./tests/tart-test.sh clean";;
  esac
}

cmd_clean() {
  local yn=""
  local has_tart="no"
  command -v tart >/dev/null 2>&1 && has_tart="yes"

  if [ "$has_tart" = "yes" ] && vm_exists 2>/dev/null; then
    stop_vm
    [ -t 0 ] && read -p "  Delete test VM '$VM' and its snapshots? [y/N] " yn || yn=""
    case "$yn" in
      y|Y) tart delete "$VM" && ok "test VM deleted";;
      *)   note "kept VM '$VM'";;
    esac
  fi

  if command -v tart >/dev/null 2>&1; then
    [ -t 0 ] && read -p "  Uninstall tart? [y/N] " yn || yn=""
    case "$yn" in
      y|Y) brew uninstall tart; ok "tart uninstalled";;
      *)   note "kept tart";;
    esac
  fi

  if command -v sshpass >/dev/null 2>&1; then
    [ -t 0 ] && read -p "  Uninstall sshpass? [y/N] " yn || yn=""
    case "$yn" in
      y|Y) brew uninstall sshpass; ok "sshpass uninstalled";;
      *)   note "kept sshpass";;
    esac
  fi

  if command -v tart >/dev/null 2>&1; then
    local image=""
    image="$(base_image)" 2>/dev/null || true
    [ -t 0 ] && read -p "  Also delete base image '$image' (~25 GB, re-download needed later)? [y/N] " yn || yn=""
    case "$yn" in
      y|Y) tart delete "$image" 2>/dev/null && ok "base image deleted" || warn "could not delete base image (does it exist?)";;
      *)   note "kept base image";;
    esac
  fi

  echo ""
  ok "Cleanup finished."
}

cmd_shot() {
  ensure_running
  local outdir="$ROOT/tests/screenshots"
  mkdir -p "$outdir"
  local out="$outdir/shot-$(date +%Y%m%d-%H%M%S).png"
  tart screenshot "$VM" "$out"
  ok "screenshot saved: $out"
}

cmd_snapshot() {
  stop_vm
  for snap in bare provisioned; do
    if tart snapshot "$VM" "$snap" 2>/dev/null; then
      ok "snapshot '$snap' created"
    else
      warn "snapshot '$snap' failed (may already exist)"
    fi
  done
}

cmd_restore() {
  local snap="${1:-bare}"
  if [ "$snap" != "bare" ] && [ "$snap" != "provisioned" ]; then die "snapshot must be 'bare' or 'provisioned'"; fi
  stop_vm
  tart restore "$VM" "$snap"
  ok "restored to '$snap' — run: ./tests/tart-test.sh up"
}

cmd_ssh() {
  ensure_running
  local ip=""
  ip="$(vm_ip)"
  exec sshpass -p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    admin@"$ip"
}

cmd_stop() {
  stop_vm
  ok "VM stopped"
}

cmd_delete() {
  stop_vm
  tart delete "$VM"
  ok "VM deleted"
}