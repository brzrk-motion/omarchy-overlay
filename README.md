# BRZRK Omarchy

A reversible, Stow-managed user overlay for **Omarchy Quattro**.

This project deliberately does **not** modify `/usr/share/omarchy` or replace Omarchy-owned defaults.
Everything it owns lives in user space. Existing user files that must be touched are snapshotted on
first install and restored on uninstall.

## Included in v0.1

- Creative-app Hyprland behavior for Blender, Krita, DaVinci Resolve, Plasticity,
  Substance, Natron and Kdenlive.
- Official Starship Tokyo Night preset.
- Fish as the interactive shell inside Ghostty only.
- Bash/login shell left unchanged.
- Executor installed as the managed MCP entry for Codex and Cursor; unrelated entries are preserved.
- Context7, Chrome DevTools MCP and shadcn MCP configured behind Executor.
- Ponytail and Impeccable installed once in `~/.agents/skills` for both agents.
- GNU Stow for static configuration.
- Required packages bootstrapped by the installer: Stow, Starship, Fish/
  `omarchy-fish`, Git, Python, Ghostty, Chromium, Node.js and npm. Executor is
  installed user-local with npm; its configured MCP servers are fetched by `npx`.
- Reversible install/update/uninstall lifecycle.
- External skill revisions and MCP package versions are pinned in `skills.lock` and `deps.lock`.

## Install

```bash
git clone <your-repo-url> ~/src/brzrk-omarchy
cd ~/src/brzrk-omarchy
./install.sh
```

If an install is interrupted, run `./uninstall.sh` to clear its saved state before retrying.

## Update

```bash
./update.sh
```

The original pre-install snapshot is never replaced during updates.

Updates reconcile the required packages, then replace only BRZRK-managed files and the `executor`
MCP entry. Other agent MCP entries are preserved.

## Uninstall

```bash
./uninstall.sh
```

This restores the exact user files captured before the first install.

To additionally remove packages that BRZRK recorded as newly installed:

```bash
./uninstall.sh --purge-packages
```

## Ownership boundary

BRZRK owns only:

- its Stow links,
- generated skill links,
- text between explicit BRZRK loader markers,
- managed MCP entries while installed,
- Executor's first-install user data/service snapshot,
- `~/.local/state/brzrk-omarchy`.

It never owns `/usr/share/omarchy`.

## Notes

Monitor names, resolution, refresh rate, scaling, VRR and workspace-to-monitor mappings are
intentionally not hard-coded yet. They belong in a later `hosts/<hostname>/` layer.
