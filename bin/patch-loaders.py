#!/usr/bin/env python3
from pathlib import Path
import os
import stat
import sys
import tempfile

HOME = Path.home()
MODE = sys.argv[1] if len(sys.argv) > 1 else "apply"
HYPR = HOME / ".config/hypr/hyprland.lua"
GHOST = HOME / ".config/ghostty"

HB = "-- >>> brzrk-omarchy managed loader >>>"
HE = "-- <<< brzrk-omarchy managed loader <<<"
HYPR_BLOCK = HB + '''
local brzrk_overlay = (os.getenv("HOME") or "") .. "/.config/brzrk-omarchy/hypr/init.lua"
local brzrk_file = io.open(brzrk_overlay, "r")
if brzrk_file then
  brzrk_file:close()
  dofile(brzrk_overlay)
end
''' + HE

GB = "# >>> brzrk-omarchy managed ghostty loader >>>"
GE = "# <<< brzrk-omarchy managed ghostty loader <<<"
GHOST_BLOCK = GB + '''
config-file = ?~/.config/brzrk-omarchy/ghostty/fish.ghostty
''' + GE

def remove_block(text, begin, end):
    while begin in text:
        s = text.index(begin)
        e = text.find(end, s)
        if e < 0:
            raise RuntimeError(f"Unclosed managed block: {begin}")
        e += len(end)
        if text[e:e+1] == "\n":
            e += 1
        text = text[:s] + text[e:]
    return text


def write_atomic(path, text):
    if path.is_symlink():
        path.write_text(text)
        return
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w") as file:
            file.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def apply(path, block, begin, end):
    path.parent.mkdir(parents=True, exist_ok=True)
    old = path.read_text() if path.exists() else ""
    base = remove_block(old, begin, end)
    if base and not base.endswith("\n"):
        base += "\n"
    write_atomic(path, base + block + "\n")

def remove(path, begin, end):
    if path.exists():
        old = path.read_text()
        new = remove_block(old, begin, end)
        if old != new:
            write_atomic(path, new)

def ghost_entry():
    p1 = GHOST / "config.ghostty"
    p2 = GHOST / "config"
    if p1.exists(): return p1
    if p2.exists(): return p2
    return p1

if MODE == "apply":
    if not HYPR.exists():
        raise SystemExit(f"Missing {HYPR}; expected a normal Omarchy Quattro user config.")
    apply(HYPR, HYPR_BLOCK, HB, HE)
    apply(ghost_entry(), GHOST_BLOCK, GB, GE)
elif MODE == "remove":
    remove(HYPR, HB, HE)
    remove(GHOST / "config.ghostty", GB, GE)
    remove(GHOST / "config", GB, GE)
else:
    raise SystemExit("usage: patch-loaders.py [apply|remove]")
