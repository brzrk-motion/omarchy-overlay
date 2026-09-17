#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
source "$REPO_ROOT/deps.lock"

MODE="${1:-sync}"
SKILLS_MANIFEST="$MANIFEST_DIR/skills-pack.txt"
SKILLS_TARGET="$HOME/.agents/skills"

valid_skill_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$1" != "." && "$1" != ".." ]]
}

restore_pack_skills() {
  [[ -f "$SKILLS_MANIFEST" ]] || return 0

  while IFS= read -r skill; do
    [[ -n "$skill" ]] || continue
    valid_skill_name "$skill" || die "Invalid managed skill name: $skill"
    restore_original "$SKILLS_TARGET/$skill" "skill-$skill"
  done < "$SKILLS_MANIFEST"

  rm -f "$SKILLS_MANIFEST"
}

if [[ "$MODE" == remove ]]; then
  restore_pack_skills
  exit 0
elif [[ "$MODE" != sync ]]; then
  die "usage: sync-skills.sh [sync|remove]"
fi

ensure_state
stage="$(mktemp -d "$STATE_DIR/.skills-stage.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
stage_home="$stage/home"
mkdir -p "$stage_home"

log "Fetching managed skills pack with skills.sh"
fetched=0
for attempt in 1 2 3; do
  rm -rf -- "$stage_home"
  mkdir -p "$stage_home"
  if HOME="$stage_home" \
    DISABLE_TELEMETRY=1 \
    npx --yes "skills@$SKILLS_CLI_VERSION" add "$SKILLS_PACK_URL" \
      --skill '*' --agent codex --agent cursor --global --copy --yes; then
    fetched=1
    break
  fi
  warn "skills.sh pack fetch failed (attempt $attempt of 3)"
done
((fetched)) || die "Unable to fetch managed skills pack after 3 attempts"

stage_skills="$stage_home/.agents/skills"
[[ -d "$stage_skills" ]] || die "skills.sh did not produce a managed skills directory"

mapfile -t new_skills < <(
  find "$stage_skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort
)
((${#new_skills[@]})) || die "The managed skills pack returned no skills"

for skill in "${new_skills[@]}"; do
  valid_skill_name "$skill" || die "Invalid skill name returned by skills.sh: $skill"
  [[ -f "$stage_skills/$skill/SKILL.md" ]] || die "Managed skill is missing SKILL.md: $skill"
done

legacy_skills=()
# Migrate installations made by the former generated/Stow skill pipeline.
if [[ -d "$GENERATED_DIR/skills" ]]; then
  legacy_dir="$GENERATED_DIR/skills/.agents/skills"
  if [[ -d "$legacy_dir" ]]; then
    mapfile -t legacy_skills < <(
      find "$legacy_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort
    )
  fi
  stow --dir="$GENERATED_DIR" --target="$HOME" --no-folding --delete skills >/dev/null 2>&1 || true
  rm -rf "$GENERATED_DIR/skills" "$GENERATED_DIR/skills.lock"
fi

mapfile -t old_skills < <(
  {
    [[ -f "$SKILLS_MANIFEST" ]] && sed '/^[[:space:]]*$/d' "$SKILLS_MANIFEST"
    printf '%s\n' "${legacy_skills[@]}"
  } | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u
)

mkdir -p "$SKILLS_TARGET"
for skill in "${new_skills[@]}"; do
  backup_once "$SKILLS_TARGET/$skill" "skill-$skill"

  # Record ownership before replacing the target so first-install rollback can
  # restore every skill even if a later copy unexpectedly fails.
  grep -qxF "$skill" "$SKILLS_MANIFEST" 2>/dev/null || printf '%s\n' "$skill" >> "$SKILLS_MANIFEST"

  rm -rf -- "$SKILLS_TARGET/$skill"
  cp -a -- "$stage_skills/$skill" "$SKILLS_TARGET/$skill"
done

# If the maintainer removes a skill from the pack, stop managing it immediately
# and restore whatever occupied that name before BRZRK first claimed it.
for skill in "${old_skills[@]}"; do
  if ! printf '%s\n' "${new_skills[@]}" | grep -qxF "$skill"; then
    valid_skill_name "$skill" || die "Invalid managed skill name: $skill"
    restore_original "$SKILLS_TARGET/$skill" "skill-$skill"
  fi
done

manifest_tmp="$stage/skills-pack.txt"
printf '%s\n' "${new_skills[@]}" > "$manifest_tmp"
mv "$manifest_tmp" "$SKILLS_MANIFEST"

log "Managed ${#new_skills[@]} skills from $SKILLS_PACK_URL"
