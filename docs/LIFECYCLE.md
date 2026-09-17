# Lifecycle contract

## First install
The installer snapshots touched pre-existing user files once. A snapshot is recorded as either
`present` or `absent`.

This includes the two managed skills and Executor's user data/service. It also records whether
Executor was installed by this project.

## Update
1. Pull repository changes.
2. Rebuild generated skills; leave the active overlay in place if this fails.
3. Restow current files; Stow removes obsolete links as part of the operation.
4. Insert current loader blocks atomically.
5. Reconcile Executor/MCP state.
6. Validate.

If a later update step fails, the updater reasserts the managed links and loaders before exiting.

The original first-install snapshot is never changed by update.
Unrelated Codex and Cursor MCP entries are preserved; only the `executor` entry is managed.
Existing Executor integrations are left unchanged when their slug already exists; the current
Executor CLI has no update/remove operation for these MCP registrations.

## Uninstall
1. Remove managed blocks.
2. Unstow generated/static packages.
3. Restore the first-install snapshot.
4. Optionally purge packages recorded as project-added.
5. Delete project state.

This ensures deleted configs disappear cleanly during update and uninstall returns to the
pre-BRZRK user state.
