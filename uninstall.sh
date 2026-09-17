#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/bin/common.sh"

[[ -d "$STATE_DIR" ]] || die "Not installed. Run ./install.sh first."

purge=0
[[ "${1:-}" == "--purge-packages" ]] && purge=1

"$REPO_ROOT/bin/patch-loaders.py" remove
if [[ -d "$GENERATED_DIR/skills" ]]; then
  stow --dir="$GENERATED_DIR" --target="$HOME" --no-folding --delete skills
fi
unstow_package starship
unstow_package brzrk

restore_original "$HOME/.config/hypr/hyprland.lua" "hyprland.lua"
restore_original "$HOME/.config/ghostty/config.ghostty" "ghostty-config.ghostty"
restore_original "$HOME/.config/ghostty/config" "ghostty-config"
restore_original "$HOME/.config/starship.toml" "starship.toml"
restore_original "$HOME/.codex/config.toml" "codex-config.toml"
restore_original "$HOME/.cursor/mcp.json" "cursor-mcp.json"
restore_original "$HOME/.agents/skills/ponytail" "skill-ponytail"
restore_original "$HOME/.agents/skills/impeccable" "skill-impeccable"
if [[ -f "$MANIFEST_DIR/npm-added.txt" ]] && command -v executor >/dev/null 2>&1; then
  executor daemon stop >/dev/null 2>&1 || true
fi
if [[ -f "$MANIFEST_DIR/npm-added.txt" ]] && command -v systemctl >/dev/null 2>&1; then
  systemctl --user disable --now executor.service >/dev/null 2>&1 || true
fi
restore_original "$HOME/.executor" "executor-data"
restore_original "$HOME/.config/systemd/user/executor.service" "executor-service"
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

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
