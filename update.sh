#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/bin/common.sh"

[[ -d "$STATE_DIR" ]] || die "Not installed. Run ./install.sh first."

if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO_ROOT" pull --ff-only
fi

ensure_packages
trap recover_update ERR

# Stow's restow handles obsolete links without creating a delete-first gap.
stow_package brzrk
stow_package starship
"$REPO_ROOT/bin/patch-loaders.py" apply

record_autostart_service_states
"$REPO_ROOT/bin/configure-executor.sh"
ensure_autostart_services
"$REPO_ROOT/bin/configure-agents.py"
"$REPO_ROOT/bin/validate.sh" --skip-skills

# Keep this as the final mutating step. The isolated stage ensures a remote
# failure leaves both active configuration and previously installed skills intact.
"$REPO_ROOT/bin/sync-skills.sh"
"$REPO_ROOT/bin/validate.sh"
trap - ERR
log "Update complete"
