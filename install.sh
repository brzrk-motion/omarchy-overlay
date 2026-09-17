#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/bin/common.sh"

[[ ! -d "$STATE_DIR" ]] || die "Already installed or an interrupted install exists; run ./uninstall.sh first."
warn_if_login_fish

ensure_packages
ensure_state
trap rollback_first_install ERR

backup_once "$HOME/.config/hypr/hyprland.lua" "hyprland.lua"
backup_once "$HOME/.config/ghostty/config.ghostty" "ghostty-config.ghostty"
backup_once "$HOME/.config/ghostty/config" "ghostty-config"
backup_once "$HOME/.config/starship.toml" "starship.toml"
backup_once "$HOME/.codex/config.toml" "codex-config.toml"
backup_once "$HOME/.cursor/mcp.json" "cursor-mcp.json"
backup_once "$HOME/.executor" "executor-data"
backup_once "$HOME/.config/systemd/user/$EXECUTOR_UNIT" "executor-service"
record_autostart_service_states

stow_overlay
"$REPO_ROOT/bin/patch-user-files.py" apply

"$REPO_ROOT/bin/configure-executor.sh"
ensure_autostart_services

warn_if_login_fish
"$REPO_ROOT/bin/validate.sh" --skip-skills

# Skills are last so a remote quota failure cannot roll back an otherwise
# complete workstation configuration. Updates retry pending skills.
if ! install_skills_pack; then
  trap - ERR
  warn "Configuration install complete, but the skills pack is pending."
  log "Run ./update.sh after the skills.sh request limit resets."
  exit 0
fi

"$REPO_ROOT/bin/validate.sh"
trap - ERR
log "Install complete"
