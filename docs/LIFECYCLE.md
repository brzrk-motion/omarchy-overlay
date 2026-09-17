# Lifecycle contract

## First install
The installer snapshots touched pre-existing user files once. A snapshot is recorded as either
`present` or `absent`.

This includes the two managed skills and Executor's user data/service. It also records whether
Executor was installed by this project.

## Update
1. Pull repository changes.
2. Rebuild generated skills; leave the active overlay in place if this fails.
3. Unstow old managed links.
4. Remove old managed loader blocks.
5. Restow current files.
6. Insert current loader blocks.
7. Reconcile Executor/MCP state.
8. Validate.

The original first-install snapshot is never changed by update.
Unrelated Codex and Cursor MCP entries are preserved; only the `executor` entry is managed.

## Uninstall
1. Remove managed blocks.
2. Unstow generated/static packages.
3. Restore the first-install snapshot.
4. Optionally purge packages recorded as project-added.
5. Delete project state.

This ensures deleted configs disappear cleanly during update and uninstall returns to the
pre-BRZRK user state.
