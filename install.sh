#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/bin/common.sh"

[[ ! -d "$STATE_DIR" ]] || die "Already installed or an interrupted install exists; run ./uninstall.sh first."
assert_not_login_fish

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

# Project owns this target while installed; original is already snapshotted.
rm -f "$HOME/.config/starship.toml"
stow_package brzrk
stow_package starship
"$REPO_ROOT/bin/patch-loaders.py" apply

"$REPO_ROOT/bin/configure-executor.sh"
ensure_autostart_services
"$REPO_ROOT/bin/configure-agents.py"

assert_not_login_fish
"$REPO_ROOT/bin/validate.sh" --skip-skills

# Skills are intentionally last so a remote quota failure cannot roll back an
# otherwise complete workstation configuration. Updates retry pending skills.
if ! "$REPO_ROOT/bin/sync-skills.sh"; then
  trap - ERR
  warn "Configuration install complete, but managed skills are pending."
  log "Run ./update.sh after the skills.sh request limit resets."
  exit 0
fi

"$REPO_ROOT/bin/validate.sh"
trap - ERR
log "Install complete"
