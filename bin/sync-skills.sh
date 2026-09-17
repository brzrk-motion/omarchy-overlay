#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/brzrk-omarchy/skills"
STAGE="$GENERATED_DIR/.skills-stage"
DEST="$STAGE/.agents/skills"
rm -rf "$STAGE"
mkdir -p "$CACHE" "$DEST"

sync_repo() {
  local url="$1" dir="$2"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" fetch --depth 1 origin main
    git -C "$dir" reset --hard origin/main
  else
    rm -rf "$dir"
    git clone --depth 1 --branch main "$url" "$dir"
  fi
}

sync_repo https://github.com/DietrichGebert/ponytail.git "$CACHE/ponytail"
cp -a "$CACHE/ponytail/skills/ponytail" "$DEST/ponytail"

sync_repo https://github.com/pbakaus/impeccable.git "$CACHE/impeccable"
cp -a "$CACHE/impeccable/.agents/skills/impeccable" "$DEST/impeccable"

rm -rf "$GENERATED_DIR/skills"
mv "$STAGE" "$GENERATED_DIR/skills"

{
  printf 'ponytail=%s\n' "$(git -C "$CACHE/ponytail" rev-parse HEAD)"
  printf 'impeccable=%s\n' "$(git -C "$CACHE/impeccable" rev-parse HEAD)"
} > "$GENERATED_DIR/skills.lock"
