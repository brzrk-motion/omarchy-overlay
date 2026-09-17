#!/usr/bin/env python3
from pathlib import Path
import json
import os
import re
import stat
import sys
import tempfile

HOME = Path.home()
MODE = sys.argv[1] if len(sys.argv) > 1 else "apply"
HYPR = HOME / ".config/hypr/hyprland.lua"
GHOST = HOME / ".config/ghostty"
CODEX = HOME / ".codex/config.toml"
CURSOR = HOME / ".cursor/mcp.json"

HB = "-- >>> brzrk-omarchy managed loader >>>"
HE = "-- <<< brzrk-omarchy managed loader <<<"
HYPR_BLOCK = (
    HB
    + """
require("default.hypr.require_optional").module("hypr.brzrk")
"""
    + HE
)

GB = "# >>> brzrk-omarchy managed ghostty loader >>>"
GE = "# <<< brzrk-omarchy managed ghostty loader <<<"
GHOST_BLOCK = (
    GB
    + """
config-file = ?"~/.config/ghostty/brzrk.ghostty"
"""
    + GE
)


def remove_block(text, begin, end):
    while begin in text:
        s = text.index(begin)
        e = text.find(end, s)
        if e < 0:
            raise RuntimeError(f"Unclosed managed block: {begin}")
        e += len(end)
        if text[e : e + 1] == "\n":
            e += 1
        text = text[:s] + text[e:]
    return text


def write_atomic(path, text, default_mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        path.write_text(text)
        return
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else default_mode
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w") as file:
            file.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def apply(path, block, begin, end, default_mode=0o644):
    old = path.read_text() if path.exists() else ""
    base = remove_block(old, begin, end)
    if base and not base.endswith("\n"):
        base += "\n"
    write_atomic(path, base + block + "\n", default_mode)


def remove(path, begin, end):
    if path.exists():
        old = path.read_text()
        new = remove_block(old, begin, end)
        if old != new:
            write_atomic(path, new)


def ghost_entry():
    p1 = GHOST / "config.ghostty"
    p2 = GHOST / "config"
    if p1.exists():
        return p1
    if p2.exists():
        return p2
    return p1


def strip_codex_mcp(text):
    lines = text.splitlines(keepends=True)
    out, in_mcp = [], False
    section = re.compile(r"^\s*(\[\[|\[)([^\]]+)(\]\]|\])\s*(?:#.*)?$")
    for line in lines:
        match = section.match(line)
        if match:
            name = match.group(2).strip()
            if name == "mcp_servers.executor" or name.startswith("mcp_servers.executor."):
                in_mcp = True
                continue
            in_mcp = False
        if not in_mcp:
            out.append(line)
    return "".join(out).rstrip() + "\n"


def apply_agents():
    base = strip_codex_mcp(CODEX.read_text() if CODEX.exists() else "")
    write_atomic(
        CODEX,
        base.rstrip() + '\n\n[mcp_servers.executor]\ncommand = "executor"\nargs = ["mcp"]\n',
        0o600,
    )

    if CURSOR.exists() and CURSOR.read_text().strip():
        data = json.loads(CURSOR.read_text())
        if not isinstance(data, dict):
            raise RuntimeError("Cursor mcp.json must contain a JSON object")
    else:
        data = {}
    servers = data.get("mcpServers", {})
    if not isinstance(servers, dict):
        raise RuntimeError("Cursor mcp.json mcpServers must be an object")
    servers["executor"] = {"command": "executor", "args": ["mcp"]}
    data["mcpServers"] = servers
    write_atomic(CURSOR, json.dumps(data, indent=2) + "\n", 0o600)


if MODE == "apply":
    if not HYPR.exists():
        raise SystemExit(f"Missing {HYPR}; expected a normal Omarchy Quattro user config.")
    apply(HYPR, HYPR_BLOCK, HB, HE)
    apply(ghost_entry(), GHOST_BLOCK, GB, GE)
    apply_agents()
elif MODE == "remove":
    remove(HYPR, HB, HE)
    remove(GHOST / "config.ghostty", GB, GE)
    remove(GHOST / "config", GB, GE)
else:
    raise SystemExit("usage: patch-user-files.py [apply|remove]")
