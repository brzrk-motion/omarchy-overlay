#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
