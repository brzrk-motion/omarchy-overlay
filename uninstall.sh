#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/bin/common.sh"

[[ -d "$STATE_DIR" ]] || die "Not installed. Run ./install.sh first."

purge=0
[[ "${1:-}" == "--purge-packages" ]] && purge=1
warn "Uninstall restores first-install snapshots and discards changes to managed files."

"$REPO_ROOT/bin/patch-loaders.py" remove
"$REPO_ROOT/bin/sync-skills.sh" remove
unstow_package starship
unstow_package brzrk

stop_added_executor
restore_managed_originals
restore_autostart_service_states

if (( purge )); then
  if [[ -f "$MANIFEST_DIR/pacman-added.txt" ]]; then
    mapfile -t pkgs < "$MANIFEST_DIR/pacman-added.txt"
    ((${#pkgs[@]})) && sudo pacman -Rns --noconfirm "${pkgs[@]}" || true
  fi
  if [[ -f "$MANIFEST_DIR/npm-added.txt" ]] && command -v npm >/dev/null 2>&1; then
    npm_prefix="$HOME/.local"
    [[ -f "$MANIFEST_DIR/npm-prefix" ]] && npm_prefix="$(<"$MANIFEST_DIR/npm-prefix")"
    npm uninstall --prefix="$npm_prefix" --global executor || true
  fi
fi

rm -rf "$STATE_DIR"

if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload >/dev/null 2>&1 || true
fi

log "Uninstall complete; pre-install user configuration restored."
