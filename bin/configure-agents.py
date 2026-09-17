#!/usr/bin/env python3
from pathlib import Path
import json
import os
import re
import stat
import tempfile

HOME = Path.home()
CODEX = HOME / ".codex/config.toml"
CURSOR = HOME / ".cursor/mcp.json"

def strip_codex_mcp(text):
    lines = text.splitlines(keepends=True)
    out, in_mcp = [], False
    section = re.compile(r'^\s*(\[\[|\[)([^\]]+)(\]\]|\])\s*(?:#.*)?$')
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


def write_atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        path.write_text(text)
        return
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w") as file:
            file.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

CODEX.parent.mkdir(parents=True, exist_ok=True)
base = strip_codex_mcp(CODEX.read_text() if CODEX.exists() else "")
write_atomic(
    CODEX,
    base.rstrip()
    + '\n\n[mcp_servers.executor]\ncommand = "executor"\nargs = ["mcp"]\n'
)

CURSOR.parent.mkdir(parents=True, exist_ok=True)
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
write_atomic(CURSOR, json.dumps(data, indent=2) + "\n")
