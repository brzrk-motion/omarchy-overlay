#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/bin/common.sh"

[[ -d "$STATE_DIR" ]] || die "Not installed. Run ./install.sh first."

if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO_ROOT" pull --ff-only
fi

ensure_packages
trap recover_update ERR

stow_overlay
"$REPO_ROOT/bin/patch-user-files.py" apply

record_autostart_service_states
"$REPO_ROOT/bin/configure-executor.sh"
ensure_autostart_services
"$REPO_ROOT/bin/validate.sh" --skip-skills

# Keep this as the final mutating step so a remote failure leaves the overlay intact.
install_skills_pack
"$REPO_ROOT/bin/validate.sh"
trap - ERR
log "Update complete"
