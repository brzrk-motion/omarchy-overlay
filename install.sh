#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/bin/common.sh"

ensure_state
assert_not_login_fish

ensure_packages

backup_once "$HOME/.config/hypr/hyprland.lua" "hyprland.lua"
backup_once "$HOME/.config/ghostty/config.ghostty" "ghostty-config.ghostty"
backup_once "$HOME/.config/ghostty/config" "ghostty-config"
backup_once "$HOME/.config/starship.toml" "starship.toml"
backup_once "$HOME/.codex/config.toml" "codex-config.toml"
backup_once "$HOME/.cursor/mcp.json" "cursor-mcp.json"
backup_once "$HOME/.agents/skills/ponytail" "skill-ponytail"
backup_once "$HOME/.agents/skills/impeccable" "skill-impeccable"
backup_once "$HOME/.executor" "executor-data"
backup_once "$HOME/.config/systemd/user/executor.service" "executor-service"

# Fetch/build generated skills before touching active links or loader files.
"$REPO_ROOT/bin/sync-skills.sh"

# Project owns this target while installed; original is already snapshotted.
rm -f "$HOME/.config/starship.toml"
# These targets are snapshotted above so Stow can install cleanly over existing
# user copies and uninstall can restore them.
rm -rf "$HOME/.agents/skills/ponytail" "$HOME/.agents/skills/impeccable"

stow_package brzrk
stow_package starship
"$REPO_ROOT/bin/patch-loaders.py" apply

stow --dir="$GENERATED_DIR" --target="$HOME" --no-folding --restow skills

"$REPO_ROOT/bin/configure-executor.sh"
"$REPO_ROOT/bin/configure-agents.py"

assert_not_login_fish
"$REPO_ROOT/bin/validate.sh"
log "Install complete"
