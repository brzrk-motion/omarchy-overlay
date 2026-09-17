# BRZRK Omarchy

A reversible, Stow-managed user overlay for **Omarchy Quattro**.

This project deliberately does **not** modify `/usr/share/omarchy` or replace Omarchy-owned defaults.
Everything it owns lives in user space. Existing user files that must be touched are snapshotted on
first install and restored on uninstall.

## Included in v0.1

- Creative-app Hyprland behavior for Blender, Krita, DaVinci Resolve, Plasticity,
  Substance, Natron and Kdenlive.
- Five conceptual Hyprland workspaces paired across two monitors: `(1,6)` through
  `(5,10)`. Workspace switching, cycling and window moves use the pair as one
  workspace. The rightmost monitor is primary and receives focus after every
  pair switch; systems with any other monitor count fall back to workspaces `1–5`.
- Official Starship Tokyo Night preset.
- Fish as the interactive shell inside Ghostty only.
- Bash/login shell left unchanged.
- Executor installed as the managed MCP entry for Codex and Cursor; unrelated entries are preserved.
- Executor's user service plus the Docker and Tailscale system daemons are enabled and started;
  their prior enablement/running state is restored on uninstall or failed-install rollback.
- Context7, Chrome DevTools MCP and shadcn MCP configured behind Executor.
- The maintained [BRZRK skills.sh pack](https://skills.sh/p/ySjQVU7kNo5txTvo) is installed
  into `~/.agents/skills` for Codex and Cursor. Updates reconcile the pack's current contents,
  including newly added skills, while uninstall restores pre-existing same-named skills. The
  installer resolves live pack membership and snapshots from skills.sh, then installs the assembled
  pack with the skills CLI.
- GNU Stow for static configuration.
- Required packages bootstrapped by the installer: Stow, Starship, Fish/
  `omarchy-fish`, Git, Python, Ghostty, Chromium, Node.js, npm, Docker and Tailscale. Executor is
  installed user-local with npm; its configured MCP servers are fetched by `npx`.
- Reversible install/update/uninstall lifecycle.
- The skills.sh CLI and MCP package versions are pinned in `deps.lock`; pack contents intentionally
  follow the current maintainer-managed release.

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

Updates reconcile the required packages and current skills pack, then replace only BRZRK-managed
files and the `executor` MCP entry. Other agent skills and MCP entries are preserved.

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
- skills listed in its state manifest while installed,
- text between explicit BRZRK loader markers,
- managed MCP entries while installed,
- Executor's first-install user data/service snapshot,
- `~/.local/state/brzrk-omarchy`.

It never owns `/usr/share/omarchy`.

## Notes

Monitor names, resolution, refresh rate, scaling, VRR and fixed workspace-to-monitor mappings are
intentionally not hard-coded. The shared workspace-pair bindings discover the two active monitors
dynamically; machine-specific display settings belong in a later `hosts/<hostname>/` layer.
