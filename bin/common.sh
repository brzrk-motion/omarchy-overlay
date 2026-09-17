#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/brzrk-omarchy"
ORIGINAL_DIR="$STATE_DIR/original"
MANIFEST_DIR="$STATE_DIR/manifest"
STOW_DIR="$REPO_ROOT/stow"
GENERATED_DIR="$REPO_ROOT/generated"

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
  local dst="$1" name="$2" marker src
  marker="$MANIFEST_DIR/${name}.state"
  src="$ORIGINAL_DIR/$name"
  [[ -f "$marker" ]] || return 0
  case "$(<"$marker")" in
    absent) rm -rf -- "$dst" ;;
    present)
      [[ -e "$src" || -L "$src" ]] || die "Missing snapshot for $dst"
      rm -rf -- "$dst"
      mkdir -p "$(dirname "$dst")"
      cp -a -- "$src" "$dst"
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
  for pkg in stow starship fish omarchy-fish git python ghostty chromium nodejs npm; do
    pacman_ensure "$pkg"
  done
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
  restore_original "$HOME/.agents/skills/ponytail" "skill-ponytail"
  restore_original "$HOME/.agents/skills/impeccable" "skill-impeccable"
  restore_original "$HOME/.executor" "executor-data"
  restore_original "$HOME/.config/systemd/user/executor.service" "executor-service"
}

stop_added_executor() {
  [[ -f "$MANIFEST_DIR/npm-added.txt" ]] || return 0
  command -v executor >/dev/null 2>&1 &&
    executor daemon stop >/dev/null 2>&1 || true
  command -v systemctl >/dev/null 2>&1 &&
    systemctl --user disable --now executor.service >/dev/null 2>&1 || true
  command -v systemctl >/dev/null 2>&1 &&
    systemctl --user daemon-reload >/dev/null 2>&1 || true
}

rollback_first_install() {
  local status=$?
  set +e
  trap - ERR
  warn "Install failed; restoring the pre-install state."

  "$REPO_ROOT/bin/patch-loaders.py" remove >/dev/null 2>&1
  if [[ -d "$GENERATED_DIR/skills" ]]; then
    stow --dir="$GENERATED_DIR" --target="$HOME" --no-folding --delete skills >/dev/null 2>&1
  fi
  unstow_package starship >/dev/null 2>&1
  unstow_package brzrk >/dev/null 2>&1
  stop_added_executor
  restore_managed_originals
  exit "$status"
}

recover_update() {
  local status=$?
  set +e
  trap - ERR
  warn "Update failed; restoring the managed overlay links and loaders."
  stow_package brzrk >/dev/null 2>&1
  stow_package starship >/dev/null 2>&1
  if [[ -d "$GENERATED_DIR/skills" ]]; then
    stow --dir="$GENERATED_DIR" --target="$HOME" --no-folding --restow skills >/dev/null 2>&1
  fi
  "$REPO_ROOT/bin/patch-loaders.py" apply >/dev/null 2>&1
  exit "$status"
}
