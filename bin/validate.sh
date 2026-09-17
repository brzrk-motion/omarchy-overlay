#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

skip_skills=0
if [[ "${1:-}" == --skip-skills ]]; then
  skip_skills=1
elif [[ -n "${1:-}" ]]; then
  die "usage: validate.sh [--skip-skills]"
fi

fail=0
for cmd in stow starship fish executor; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ✓ $cmd"
  else
    echo "  ✗ $cmd missing"
    fail=1
  fi
done

[[ -e "$HOME/.config/brzrk-omarchy/hypr/init.lua" ]] || fail=1
if [[ -e "$HOME/.config/brzrk-omarchy/hypr/workspaces.lua" ]] &&
  grep -q 'Switch to workspace pair' "$HOME/.config/brzrk-omarchy/hypr/workspaces.lua"; then
  echo "  ✓ Hyprland workspace-pair bindings installed"
else
  echo "  ✗ Hyprland workspace-pair bindings missing"
  fail=1
fi
grep -q 'brzrk-omarchy managed loader' "$HOME/.config/hypr/hyprland.lua" || fail=1
[[ -e "$HOME/.config/brzrk-omarchy/ghostty/fish.ghostty" ]] || fail=1
if [[ -f "$HOME/.config/ghostty/config.ghostty" ]]; then
  grep -q 'brzrk-omarchy managed ghostty loader' "$HOME/.config/ghostty/config.ghostty" || fail=1
elif [[ -f "$HOME/.config/ghostty/config" ]]; then
  grep -q 'brzrk-omarchy managed ghostty loader' "$HOME/.config/ghostty/config" || fail=1
else
  echo '  ✗ Ghostty config missing'
  fail=1
fi
[[ -L "$HOME/.config/starship.toml" ]] || fail=1
if (( skip_skills )); then
  echo "  ○ Managed skills validation deferred until final install step"
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
