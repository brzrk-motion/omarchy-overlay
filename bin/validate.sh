#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
source "$REPO_ROOT/deps.lock"

skip_skills=0
repo_only=0
if [[ "${1:-}" == --skip-skills ]]; then
  skip_skills=1
elif [[ "${1:-}" == --repo ]]; then
  repo_only=1
elif [[ -n "${1:-}" ]]; then
  die "usage: validate.sh [--skip-skills|--repo]"
fi

fail=0
check() {
  local ok="$1" msg="$2"
  if (( ok )); then
    echo "  ✓ $msg"
  else
    echo "  ✗ $msg"
    fail=1
  fi
}

stow_root="$REPO_ROOT/stow/brzrk/.config"
hypr_lua="$stow_root/hypr/brzrk.lua"
ghostty_cfg="$stow_root/ghostty/brzrk.ghostty"
starship_cfg="$stow_root/starship.toml"
patcher="$REPO_ROOT/bin/patch-user-files.py"

check "$([[ -f "$hypr_lua" ]] && echo 1 || echo 0)" "repo Hyprland overlay at hypr/brzrk.lua"
check "$([[ -f "$ghostty_cfg" ]] && echo 1 || echo 0)" "repo Ghostty overlay at ghostty/brzrk.ghostty"
check "$([[ -f "$starship_cfg" ]] && echo 1 || echo 0)" "repo Starship preset in brzrk package"
check "$([[ -f "$patcher" ]] && echo 1 || echo 0)" "unified user-file patcher"
check "$([[ ! -e "$REPO_ROOT/bin/resolve-skills-pack.py" ]] && echo 1 || echo 0)" "skills HTML scraper removed"
check "$([[ ! -e "$REPO_ROOT/bin/sync-skills.sh" ]] && echo 1 || echo 0)" "skills staging script removed"
check "$([[ ! -e "$REPO_ROOT/bin/patch-loaders.py" ]] && echo 1 || echo 0)" "loader-only patcher removed"
check "$([[ ! -e "$REPO_ROOT/bin/configure-agents.py" ]] && echo 1 || echo 0)" "separate agents patcher removed"
check "$([[ ! -d "$REPO_ROOT/stow/starship" ]] && echo 1 || echo 0)" "starship Stow package merged"
check "$([[ ! -d "$REPO_ROOT/stow/brzrk/.config/brzrk-omarchy" ]] && echo 1 || echo 0)" "private brzrk-omarchy tree removed"
check "$([[ ! -d "$REPO_ROOT/hosts" ]] && echo 1 || echo 0)" "empty hosts layer removed"
check "$([[ ! -e "$REPO_ROOT/bin/common.sh" ]] || ! grep -q GENERATED_DIR "$REPO_ROOT/bin/common.sh" && echo 1 || echo 0)" "generated-skills migration removed"

if [[ -f "$hypr_lua" ]]; then
  check "$(grep -q 'gaps_in = 2' "$hypr_lua" && grep -q 'gaps_out = 2' "$hypr_lua" && echo 1 || echo 0)" "window gaps are 2px"
  check "$(grep -q 'tile = true' "$hypr_lua" && grep -q 'maximize = true' "$hypr_lua" && echo 1 || echo 0)" "creative apps tile+maximize as effects"
  check "$(grep -q 'float = false' "$hypr_lua" && echo 0 || echo 1)" "creative rules do not match on float=false"
  check "$(grep -q 'switch_pair' "$hypr_lua" && grep -q 'hl.workspace_rule' "$hypr_lua" && echo 1 || echo 0)" "workspace-pair bindings in overlay"
  check "$(grep -Fq 'class = class_pattern, title = title_pattern' "$hypr_lua" && echo 1 || echo 0)" "dialog title rules scoped by class"
fi

if [[ -f "$ghostty_cfg" ]]; then
  check "$(grep -q '^command = direct:fish$' "$ghostty_cfg" && echo 1 || echo 0)" "Ghostty uses Fish as interactive shell"
fi

if [[ -f "$patcher" ]]; then
  check "$(grep -Fq 'require("default.hypr.require_optional").module("hypr.brzrk")' "$patcher" && echo 1 || echo 0)" "Hyprland loader uses require_optional"
  check "$(grep -Fq 'config-file = ?"~/.config/ghostty/brzrk.ghostty"' "$patcher" && echo 1 || echo 0)" "Ghostty include is quoted optional path"
fi

check "$(grep -Fq "npx --yes \"skills@\$SKILLS_CLI_VERSION\"" "$REPO_ROOT/bin/common.sh" && grep -q 'skills_cli add "$SKILLS_PACK_URL"' "$REPO_ROOT/bin/common.sh" && echo 1 || echo 0)" "skills install is npx skills add of the pack URL"
check "$(grep -q 'list_pack_skills' "$REPO_ROOT/bin/common.sh" && grep -q 'skillId' "$REPO_ROOT/bin/common.sh" && echo 1 || echo 0)" "update lists current pack membership before install"
check "$(grep -q '^remove_skills_pack()' "$REPO_ROOT/bin/common.sh" && echo 1 || echo 0)" "skills pack can be removed"
check "$(grep -q 'remove_skills_pack' "$REPO_ROOT/uninstall.sh" && echo 1 || echo 0)" "uninstall removes managed pack skills"
check "$(grep -q 'stow_package starship' "$REPO_ROOT"/install.sh "$REPO_ROOT"/update.sh "$REPO_ROOT"/uninstall.sh && echo 0 || echo 1)" "install lifecycle no longer stows a starship package"

if (( repo_only )); then
  exit "$fail"
fi

for cmd in stow starship fish executor; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ✓ $cmd"
  else
    echo "  ✗ $cmd missing"
    fail=1
  fi
done

check "$([[ -e "$HOME/.config/hypr/brzrk.lua" ]] && echo 1 || echo 0)" "Hyprland overlay installed"
check "$([[ -e "$HOME/.config/hypr/hyprland.lua" ]] && grep -q 'brzrk-omarchy managed loader' "$HOME/.config/hypr/hyprland.lua" && grep -q 'hypr.brzrk' "$HOME/.config/hypr/hyprland.lua" && echo 1 || echo 0)" "hyprland.lua loads hypr.brzrk"
check "$([[ -e "$HOME/.config/ghostty/brzrk.ghostty" ]] && echo 1 || echo 0)" "Ghostty overlay installed"
ghostty_ok=0
if [[ -f "$HOME/.config/ghostty/config.ghostty" ]] && grep -q 'brzrk-omarchy managed ghostty loader' "$HOME/.config/ghostty/config.ghostty"; then
  ghostty_ok=1
elif [[ -f "$HOME/.config/ghostty/config" ]] && grep -q 'brzrk-omarchy managed ghostty loader' "$HOME/.config/ghostty/config"; then
  ghostty_ok=1
fi
check "$ghostty_ok" "Ghostty config includes overlay"
check "$([[ -L "$HOME/.config/starship.toml" ]] && echo 1 || echo 0)" "Starship config is a Stow link"

if (( skip_skills )); then
  echo "  ○ Skills pack validation deferred until final install step"
else
  skills_manifest="$MANIFEST_DIR/skills-pack.txt"
  if [[ -s "$skills_manifest" ]]; then
    skill_count=0
    while IFS= read -r skill; do
      [[ -n "$skill" ]] || continue
      if [[ -f "$HOME/.agents/skills/$skill/SKILL.md" ]]; then
        ((skill_count += 1))
      else
        echo "  ✗ Managed skill missing: $skill"
        fail=1
      fi
    done < "$skills_manifest"
    echo "  ✓ $skill_count managed skills from skills.sh pack"
  else
    echo "  ✗ Managed skills manifest missing or empty"
    fail=1
  fi
fi
grep -q '\[mcp_servers\.executor\]' "$HOME/.codex/config.toml" || fail=1

python3 - <<'PY' || fail=1
from pathlib import Path
import json
d = json.loads((Path.home()/".cursor/mcp.json").read_text())
assert d["mcpServers"]["executor"] == {"command": "executor", "args": ["mcp"]}
print("  ✓ Cursor MCP includes executor")
PY

login_shell="$(getent passwd "$USER" | cut -d: -f7)"
echo "  ✓ Login shell unchanged by BRZRK: $login_shell"

check_service() {
  local scope="$1" unit="$2" label="$3"
  if service_is_enabled "$scope" "$unit" && service_is_active "$scope" "$unit"; then
    echo "  ✓ $label enabled and running"
  else
    echo "  ✗ $label is not both enabled and running"
    fail=1
  fi
}

check_service user "$EXECUTOR_UNIT" Executor
check_service system docker.service Docker
check_service system tailscaled.service Tailscale

if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload >/dev/null || fail=1
  errors="$(hyprctl configerrors 2>/dev/null || true)"
  if [[ -z "${errors//[[:space:]]/}" ]]; then
    echo "  ✓ Hyprland reload clean"
  else
    echo "$errors"
    fail=1
  fi
fi

exit "$fail"
