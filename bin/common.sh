#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/brzrk-omarchy"
ORIGINAL_DIR="$STATE_DIR/original"
MANIFEST_DIR="$STATE_DIR/manifest"
STOW_DIR="$REPO_ROOT/stow"
GENERATED_DIR="$REPO_ROOT/generated"
EXECUTOR_UNIT="sh.executor.daemon.service"

log()  { printf '\033[1;36m[brzrk]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[brzrk]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[brzrk]\033[0m %s\n' "$*" >&2; exit 1; }

ensure_state() { mkdir -p "$ORIGINAL_DIR" "$MANIFEST_DIR"; }

backup_once() {
  local src="$1" name="$2" marker dst
  ensure_state
  marker="$MANIFEST_DIR/${name}.state"
  dst="$ORIGINAL_DIR/$name"
  [[ -e "$marker" ]] && return 0
  if [[ -e "$src" || -L "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -a -- "$src" "$dst"
    printf 'present\n' > "$marker"
  else
    printf 'absent\n' > "$marker"
  fi
}

restore_original() {
  local dst="$1" name="$2" marker src tmp
  marker="$MANIFEST_DIR/${name}.state"
  src="$ORIGINAL_DIR/$name"
  [[ -f "$marker" ]] || return 0
  case "$(<"$marker")" in
    absent) rm -rf -- "$dst" ;;
    present)
      [[ -e "$src" || -L "$src" ]] || die "Missing snapshot for $dst"
      mkdir -p "$(dirname "$dst")"
      if [[ -f "$src" && ! -L "$src" ]]; then
        tmp="$(mktemp "$(dirname "$dst")/.${name}.restore.XXXXXX")"
        cp -a -- "$src" "$tmp"
        mv -f -- "$tmp" "$dst"
      else
        rm -rf -- "$dst"
        cp -a -- "$src" "$dst"
      fi
      ;;
    *) die "Invalid snapshot marker: $marker" ;;
  esac
}

stow_package() {
  stow --dir="$STOW_DIR" --target="$HOME" --no-folding --restow "$1"
}
unstow_package() {
  [[ -d "$STOW_DIR/$1" ]] || return 0
  stow --dir="$STOW_DIR" --target="$HOME" --no-folding --delete "$1"
}

record_new_package() {
  local pkg="$1"
  ensure_state
  grep -qxF "$pkg" "$MANIFEST_DIR/pacman-added.txt" 2>/dev/null ||
    printf '%s\n' "$pkg" >> "$MANIFEST_DIR/pacman-added.txt"
}

pacman_ensure() {
  local pkg="$1"
  pacman -Q "$pkg" >/dev/null 2>&1 && return 0
  sudo pacman -S --needed --noconfirm "$pkg"
  record_new_package "$pkg"
}

ensure_packages() {
  for pkg in stow starship fish omarchy-fish git python ghostty chromium nodejs npm docker tailscale; do
    pacman_ensure "$pkg"
  done
}

service_is_enabled() {
  local scope="$1" unit="$2"
  if [[ "$scope" == user ]]; then
    systemctl --user is-enabled --quiet "$unit"
  else
    systemctl is-enabled --quiet "$unit"
  fi
}

service_is_active() {
  local scope="$1" unit="$2"
  if [[ "$scope" == user ]]; then
    systemctl --user is-active --quiet "$unit"
  else
    systemctl is-active --quiet "$unit"
  fi
}

record_service_state_once() {
  local scope="$1" unit="$2" name="$3" state_file
  state_file="$MANIFEST_DIR/${name}.service-state"
  [[ -e "$state_file" ]] && return 0

  local enabled=0 active=0
  service_is_enabled "$scope" "$unit" && enabled=1
  service_is_active "$scope" "$unit" && active=1
  printf 'enabled=%s\nactive=%s\n' "$enabled" "$active" > "$state_file"
}

record_autostart_service_states() {
  command -v systemctl >/dev/null 2>&1 || die "systemd is required for managed autostart services."
  ensure_state
  record_service_state_once user "$EXECUTOR_UNIT" executor
  record_service_state_once system docker.service docker
  record_service_state_once system tailscaled.service tailscaled
}

ensure_autostart_services() {
  log "Enabling Executor, Docker, and Tailscale autostart"
  systemctl --user daemon-reload
  systemctl --user enable --now "$EXECUTOR_UNIT"
  sudo systemctl enable --now docker.service tailscaled.service
}

restore_service_state() {
  local scope="$1" unit="$2" name="$3" state_file enabled active enable_action active_action
  state_file="$MANIFEST_DIR/${name}.service-state"
  [[ -f "$state_file" ]] || return 0

  enabled="$(sed -n 's/^enabled=//p' "$state_file")"
  active="$(sed -n 's/^active=//p' "$state_file")"
  [[ "$enabled" == 0 || "$enabled" == 1 ]] || die "Invalid enabled state for $unit"
  [[ "$active" == 0 || "$active" == 1 ]] || die "Invalid active state for $unit"
  [[ "$enabled" == 1 ]] && enable_action=enable || enable_action=disable
  [[ "$active" == 1 ]] && active_action=start || active_action=stop

  if [[ "$scope" == user ]]; then
    systemctl --user "$enable_action" "$unit" >/dev/null 2>&1 || true
    systemctl --user "$active_action" "$unit" >/dev/null 2>&1 || true
  else
    sudo systemctl "$enable_action" "$unit" >/dev/null 2>&1 || true
    sudo systemctl "$active_action" "$unit" >/dev/null 2>&1 || true
  fi
}

restore_autostart_service_states() {
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  restore_service_state user "$EXECUTOR_UNIT" executor
  restore_service_state system docker.service docker
  restore_service_state system tailscaled.service tailscaled
}

assert_not_login_fish() {
  local login_shell
  login_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ "$login_shell" == *"/fish" ]]; then
    warn "Login shell is already Fish ($login_shell). BRZRK will not change it."
  fi
}

restore_managed_originals() {
  restore_original "$HOME/.config/hypr/hyprland.lua" "hyprland.lua"
  restore_original "$HOME/.config/ghostty/config.ghostty" "ghostty-config.ghostty"
  restore_original "$HOME/.config/ghostty/config" "ghostty-config"
  restore_original "$HOME/.config/starship.toml" "starship.toml"
  restore_original "$HOME/.codex/config.toml" "codex-config.toml"
  restore_original "$HOME/.cursor/mcp.json" "cursor-mcp.json"
  restore_original "$HOME/.executor" "executor-data"
  restore_original "$HOME/.config/systemd/user/$EXECUTOR_UNIT" "executor-service"
}

stop_added_executor() {
  [[ -f "$MANIFEST_DIR/npm-added.txt" ]] || return 0
  command -v executor >/dev/null 2>&1 &&
    executor daemon stop >/dev/null 2>&1 || true
  command -v systemctl >/dev/null 2>&1 &&
    systemctl --user disable --now "$EXECUTOR_UNIT" >/dev/null 2>&1 || true
  command -v systemctl >/dev/null 2>&1 &&
    systemctl --user daemon-reload >/dev/null 2>&1 || true
}

rollback_first_install() {
  local status=$?
  set +e
  trap - ERR
  warn "Install failed; restoring the pre-install state."

  "$REPO_ROOT/bin/patch-loaders.py" remove >/dev/null 2>&1
  "$REPO_ROOT/bin/sync-skills.sh" remove >/dev/null 2>&1
  unstow_package starship >/dev/null 2>&1
  unstow_package brzrk >/dev/null 2>&1
  stop_added_executor
  restore_managed_originals
  restore_autostart_service_states
  exit "$status"
}

recover_update() {
  local status=$?
  set +e
  trap - ERR
  warn "Update failed; restoring the managed overlay links and loaders."
  stow_package brzrk >/dev/null 2>&1
  stow_package starship >/dev/null 2>&1
  "$REPO_ROOT/bin/patch-loaders.py" apply >/dev/null 2>&1
  exit "$status"
}
