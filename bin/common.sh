#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/brzrk-omarchy"
ORIGINAL_DIR="$STATE_DIR/original"
MANIFEST_DIR="$STATE_DIR/manifest"
STOW_DIR="$REPO_ROOT/stow"
EXECUTOR_UNIT="sh.executor.daemon.service"

log()  { printf '\033[1;36m[brzrk]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[brzrk]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[brzrk]\033[0m %s\n' "$*" >&2; exit 1; }

ensure_state() { mkdir -p "$ORIGINAL_DIR" "$MANIFEST_DIR"; }

backup_once() {
  local src="$1" name="$2" marker dst
  ensure_state
  marker="$MANIFEST_DIR/${name}.state"
  dst="$ORIGINAL_DIR/$name"
  [[ -e "$marker" ]] && return 0
  if [[ -e "$src" || -L "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -a -- "$src" "$dst"
    printf 'present\n' > "$marker"
  else
    printf 'absent\n' > "$marker"
  fi
}

restore_original() {
  local dst="$1" name="$2" marker src tmp
  marker="$MANIFEST_DIR/${name}.state"
  src="$ORIGINAL_DIR/$name"
  [[ -f "$marker" ]] || return 0
  case "$(<"$marker")" in
    absent) rm -rf -- "$dst" ;;
    present)
      [[ -e "$src" || -L "$src" ]] || die "Missing snapshot for $dst"
      mkdir -p "$(dirname "$dst")"
      if [[ -f "$src" && ! -L "$src" ]]; then
        tmp="$(mktemp "$(dirname "$dst")/.${name}.restore.XXXXXX")"
        cp -a -- "$src" "$tmp"
        mv -f -- "$tmp" "$dst"
      else
        rm -rf -- "$dst"
        cp -a -- "$src" "$dst"
      fi
      ;;
    *) die "Invalid snapshot marker: $marker" ;;
  esac
}

stow_package() {
  stow --dir="$STOW_DIR" --target="$HOME" --no-folding --restow "$1"
}
unstow_package() {
  [[ -d "$STOW_DIR/$1" ]] || return 0
  stow --dir="$STOW_DIR" --target="$HOME" --no-folding --delete "$1"
}

drop_legacy_stow_links() {
  local path
  for path in \
    "$HOME/.config/brzrk-omarchy/hypr/init.lua" \
    "$HOME/.config/brzrk-omarchy/hypr/workspaces.lua" \
    "$HOME/.config/brzrk-omarchy/ghostty/fish.ghostty"
  do
    [[ -L "$path" ]] && rm -f -- "$path"
  done
  rmdir "$HOME/.config/brzrk-omarchy/hypr" 2>/dev/null || true
  rmdir "$HOME/.config/brzrk-omarchy/ghostty" 2>/dev/null || true
  rmdir "$HOME/.config/brzrk-omarchy" 2>/dev/null || true
}

stow_overlay() {
  drop_legacy_stow_links
  rm -f "$HOME/.config/starship.toml"
  stow_package brzrk
}

SKILLS_TARGET="$HOME/.agents/skills"
SKILLS_MANIFEST="$MANIFEST_DIR/skills-pack.txt"

valid_skill_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$1" != "." && "$1" != ".." ]]
}

skills_cli() {
  DISABLE_TELEMETRY=1 npx --yes "skills@$SKILLS_CLI_VERSION" "$@"
}

list_pack_skills() {
  python3 - "$SKILLS_PACK_URL" <<'PY'
import re
import sys
from urllib.request import Request, urlopen

url = sys.argv[1]
html = urlopen(Request(url, headers={"User-Agent": "skills-cli"}), timeout=30).read().decode(
    "utf-8", "replace"
)
pattern = (
    r'\\"source\\":\\"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)\\"'
    r'.{0,120}'
    r'\\"skillId\\":\\"([A-Za-z0-9][A-Za-z0-9._-]*)\\"'
)
seen = []
for source, skill in re.findall(pattern, html):
    if skill not in seen:
        seen.append(skill)
        print(f"{source}\t{skill}")
if not seen:
    raise SystemExit("pack membership was not present in the skills.sh response")
PY
}

install_skills_pack() {
  # shellcheck disable=SC1091
  source "$REPO_ROOT/deps.lock"
  ensure_state
  local line source skill
  local pack_sources=() pack_skills=() old_skills=()
  while IFS=$'\t' read -r source skill; do
    [[ -n "$source" && -n "$skill" ]] || continue
    [[ "$source" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "Invalid pack source: $source"
    valid_skill_name "$skill" || die "Invalid skill name from pack: $skill"
    pack_sources+=("$source")
    pack_skills+=("$skill")
  done < <(list_pack_skills)
  ((${#pack_skills[@]})) || die "The skills pack listed no installable skills"

  [[ -f "$SKILLS_MANIFEST" ]] && mapfile -t old_skills < "$SKILLS_MANIFEST"

  mkdir -p "$SKILLS_TARGET"
  for skill in "${pack_skills[@]}"; do
    backup_once "$SKILLS_TARGET/$skill" "skill-$skill"
    grep -qxF "$skill" "$SKILLS_MANIFEST" 2>/dev/null || printf '%s\n' "$skill" >> "$SKILLS_MANIFEST"
  done

  log "Installing ${#pack_skills[@]} skills from $SKILLS_PACK_URL"
  if ! skills_cli add "$SKILLS_PACK_URL" \
    --skill '*' --agent codex --agent cursor --global --copy --yes; then
    warn "Pack URL install failed; installing each pack source with the skills CLI."
    local -A grouped=()
    local i names=() source
    for i in "${!pack_skills[@]}"; do
      grouped["${pack_sources[$i]}"]+="${pack_skills[$i]}"$'\n'
    done
    for source in "${!grouped[@]}"; do
      mapfile -t names < <(printf '%s' "${grouped[$source]}" | sed '/^$/d')
      if ! skills_cli add "$source" \
        --skill "${names[@]}" --agent codex --agent cursor --global --copy --yes; then
        skills_cli add "$source" \
          --skill '*' --agent codex --agent cursor --global --copy --yes
      fi
    done
  fi

  local installed=()
  for skill in "${pack_skills[@]}"; do
    [[ -f "$SKILLS_TARGET/$skill/SKILL.md" ]] && installed+=("$skill")
  done
  ((${#installed[@]})) || die "No pack skills were installed"

  for skill in "${old_skills[@]}"; do
    [[ -n "$skill" ]] || continue
    printf '%s\n' "${installed[@]}" | grep -qxF "$skill" && continue
    valid_skill_name "$skill" || die "Invalid managed skill name: $skill"
    skills_cli remove --global --agent codex --agent cursor --skill "$skill" -y >/dev/null 2>&1 || true
    restore_original "$SKILLS_TARGET/$skill" "skill-$skill"
  done

  local manifest_tmp
  manifest_tmp="$(mktemp "$MANIFEST_DIR/skills-pack.XXXXXX")"
  printf '%s\n' "${installed[@]}" > "$manifest_tmp"
  mv "$manifest_tmp" "$SKILLS_MANIFEST"
}

remove_skills_pack() {
  # shellcheck disable=SC1091
  source "$REPO_ROOT/deps.lock"
  [[ -f "$SKILLS_MANIFEST" ]] || return 0

  local skill
  while IFS= read -r skill; do
    [[ -n "$skill" ]] || continue
    valid_skill_name "$skill" || die "Invalid managed skill name: $skill"
    skills_cli remove --global --agent codex --agent cursor --skill "$skill" -y >/dev/null 2>&1 || true
    restore_original "$SKILLS_TARGET/$skill" "skill-$skill"
  done < "$SKILLS_MANIFEST"
  rm -f "$SKILLS_MANIFEST"
}

record_new_package() {
  local pkg="$1"
  ensure_state
  grep -qxF "$pkg" "$MANIFEST_DIR/pacman-added.txt" 2>/dev/null ||
    printf '%s\n' "$pkg" >> "$MANIFEST_DIR/pacman-added.txt"
}

pacman_ensure() {
  local pkg="$1"
  pacman -Q "$pkg" >/dev/null 2>&1 && return 0
  sudo pacman -S --needed --noconfirm "$pkg"
  record_new_package "$pkg"
}

ensure_packages() {
  for pkg in stow starship fish omarchy-fish git python ghostty chromium nodejs npm docker tailscale; do
    pacman_ensure "$pkg"
  done
}

service_is_enabled() {
  local scope="$1" unit="$2"
  if [[ "$scope" == user ]]; then
    systemctl --user is-enabled --quiet "$unit"
  else
    systemctl is-enabled --quiet "$unit"
  fi
}

service_is_active() {
  local scope="$1" unit="$2"
  if [[ "$scope" == user ]]; then
    systemctl --user is-active --quiet "$unit"
  else
    systemctl is-active --quiet "$unit"
  fi
}

record_service_state_once() {
  local scope="$1" unit="$2" name="$3" state_file
  state_file="$MANIFEST_DIR/${name}.service-state"
  [[ -e "$state_file" ]] && return 0

  local enabled=0 active=0
  service_is_enabled "$scope" "$unit" && enabled=1
  service_is_active "$scope" "$unit" && active=1
  printf 'enabled=%s\nactive=%s\n' "$enabled" "$active" > "$state_file"
}

record_autostart_service_states() {
  command -v systemctl >/dev/null 2>&1 || die "systemd is required for managed autostart services."
  ensure_state
  record_service_state_once user "$EXECUTOR_UNIT" executor
  record_service_state_once system docker.service docker
  record_service_state_once system tailscaled.service tailscaled
}

ensure_autostart_services() {
  log "Enabling Executor, Docker, and Tailscale autostart"
  systemctl --user daemon-reload
  systemctl --user enable --now "$EXECUTOR_UNIT"
  sudo systemctl enable --now docker.service tailscaled.service
}

restore_service_state() {
  local scope="$1" unit="$2" name="$3" state_file enabled active enable_action active_action
  state_file="$MANIFEST_DIR/${name}.service-state"
  [[ -f "$state_file" ]] || return 0

  enabled="$(sed -n 's/^enabled=//p' "$state_file")"
  active="$(sed -n 's/^active=//p' "$state_file")"
  [[ "$enabled" == 0 || "$enabled" == 1 ]] || die "Invalid enabled state for $unit"
  [[ "$active" == 0 || "$active" == 1 ]] || die "Invalid active state for $unit"
  [[ "$enabled" == 1 ]] && enable_action=enable || enable_action=disable
  [[ "$active" == 1 ]] && active_action=start || active_action=stop

  if [[ "$scope" == user ]]; then
    systemctl --user "$enable_action" "$unit" >/dev/null 2>&1 || true
    systemctl --user "$active_action" "$unit" >/dev/null 2>&1 || true
  else
    sudo systemctl "$enable_action" "$unit" >/dev/null 2>&1 || true
    sudo systemctl "$active_action" "$unit" >/dev/null 2>&1 || true
  fi
}

restore_autostart_service_states() {
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  restore_service_state user "$EXECUTOR_UNIT" executor
  restore_service_state system docker.service docker
  restore_service_state system tailscaled.service tailscaled
}

warn_if_login_fish() {
  local login_shell
  login_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ "$login_shell" == *"/fish" ]]; then
    warn "Login shell is already Fish ($login_shell). BRZRK will not change it."
  fi
}

restore_managed_originals() {
  restore_original "$HOME/.config/hypr/hyprland.lua" "hyprland.lua"
  restore_original "$HOME/.config/ghostty/config.ghostty" "ghostty-config.ghostty"
  restore_original "$HOME/.config/ghostty/config" "ghostty-config"
  restore_original "$HOME/.config/starship.toml" "starship.toml"
  restore_original "$HOME/.codex/config.toml" "codex-config.toml"
  restore_original "$HOME/.cursor/mcp.json" "cursor-mcp.json"
  restore_original "$HOME/.executor" "executor-data"
  restore_original "$HOME/.config/systemd/user/$EXECUTOR_UNIT" "executor-service"
}

stop_added_executor() {
  [[ -f "$MANIFEST_DIR/npm-added.txt" ]] || return 0
  command -v executor >/dev/null 2>&1 &&
    executor daemon stop >/dev/null 2>&1 || true
  command -v systemctl >/dev/null 2>&1 &&
    systemctl --user disable --now "$EXECUTOR_UNIT" >/dev/null 2>&1 || true
  command -v systemctl >/dev/null 2>&1 &&
    systemctl --user daemon-reload >/dev/null 2>&1 || true
}

rollback_first_install() {
  local status=$?
  set +e
  trap - ERR
  warn "Install failed; restoring the pre-install state."

  "$REPO_ROOT/bin/patch-user-files.py" remove >/dev/null 2>&1
  remove_skills_pack >/dev/null 2>&1
  unstow_package brzrk >/dev/null 2>&1
  stop_added_executor
  restore_managed_originals
  restore_autostart_service_states
  exit "$status"
}

recover_update() {
  local status=$?
  set +e
  trap - ERR
  warn "Update failed; restoring the managed overlay links and loaders."
  stow_overlay >/dev/null 2>&1
  "$REPO_ROOT/bin/patch-user-files.py" apply >/dev/null 2>&1
  exit "$status"
}
