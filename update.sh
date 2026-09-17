#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/bin/common.sh"

[[ -d "$STATE_DIR" ]] || die "Not installed. Run ./install.sh first."

if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO_ROOT" pull --ff-only
fi

ensure_packages

# Fetch/build first so a network failure leaves the active overlay untouched.
"$REPO_ROOT/bin/sync-skills.sh"

unstow_package starship
unstow_package brzrk
if [[ -d "$GENERATED_DIR/skills" ]]; then
  stow --dir="$GENERATED_DIR" --target="$HOME" --no-folding --delete skills
fi
"$REPO_ROOT/bin/patch-loaders.py" remove

stow_package brzrk
stow_package starship
"$REPO_ROOT/bin/patch-loaders.py" apply

stow --dir="$GENERATED_DIR" --target="$HOME" --no-folding --restow skills

"$REPO_ROOT/bin/configure-executor.sh"
"$REPO_ROOT/bin/configure-agents.py"
"$REPO_ROOT/bin/validate.sh"
log "Update complete"
