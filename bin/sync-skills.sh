#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/brzrk-omarchy/skills"
STAGE="$GENERATED_DIR/.skills-stage"
DEST="$STAGE/.agents/skills"
source "$REPO_ROOT/skills.lock"
[[ "${PONYTAIL_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || die "Invalid PONYTAIL_COMMIT in skills.lock"
[[ "${IMPECCABLE_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || die "Invalid IMPECCABLE_COMMIT in skills.lock"
rm -rf "$STAGE"
mkdir -p "$CACHE" "$DEST"

sync_repo() {
  local url="$1" dir="$2" ref="$3"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" cat-file -e "$ref^{commit}" 2>/dev/null ||
      git -C "$dir" fetch --depth 1 origin "$ref"
  else
    rm -rf "$dir"
    git clone --depth 1 --no-checkout "$url" "$dir"
    git -C "$dir" fetch --depth 1 origin "$ref"
  fi
  git -C "$dir" checkout --detach --force "$ref"
}

sync_repo https://github.com/DietrichGebert/ponytail.git "$CACHE/ponytail" "$PONYTAIL_COMMIT"
cp -a "$CACHE/ponytail/skills/ponytail" "$DEST/ponytail"

sync_repo https://github.com/pbakaus/impeccable.git "$CACHE/impeccable" "$IMPECCABLE_COMMIT"
cp -a "$CACHE/impeccable/.agents/skills/impeccable" "$DEST/impeccable"

rm -rf "$GENERATED_DIR/skills"
mv "$STAGE" "$GENERATED_DIR/skills"

{
  printf 'ponytail=%s\n' "$PONYTAIL_COMMIT"
  printf 'impeccable=%s\n' "$IMPECCABLE_COMMIT"
} > "$GENERATED_DIR/skills.lock"
