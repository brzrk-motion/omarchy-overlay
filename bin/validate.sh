#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

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
[[ -e "$HOME/.agents/skills/ponytail/SKILL.md" ]] || fail=1
[[ -e "$HOME/.agents/skills/impeccable/SKILL.md" ]] || fail=1
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
