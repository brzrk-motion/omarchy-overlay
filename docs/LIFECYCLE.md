# Lifecycle contract

## First install
The installer snapshots touched pre-existing user files once. A snapshot is recorded as either
`present` or `absent`.

This includes Executor's user data/service and any pre-existing skill directories that share a
name with the skills pack. It also records whether Executor was installed by this project.
The skills pack is installed last.

## Update
1. Pull repository changes.
2. Restow current files and drop any leftover links from older overlay paths.
3. Insert current loader blocks atomically and reconcile Codex/Cursor MCP entries.
4. Reconcile Executor/MCP state.
5. Validate, then install the current skills pack (including skills added since last install).
   Skills removed from the pack are restored to their pre-BRZRK snapshot.

If a later update step fails, the updater reasserts the managed links and loaders before exiting.

The original first-install snapshot is never changed by update.
Unrelated Codex and Cursor MCP entries are preserved; only the `executor` entry is managed.
Existing Executor integrations are left unchanged when their slug already exists; the current
Executor CLI has no update/remove operation for these MCP registrations.

## Uninstall
1. Remove managed blocks.
2. Unstow the overlay package.
3. Restore the first-install snapshot.
4. Optionally purge packages recorded as project-added.
5. Delete project state.

Managed pack skills are removed and their first-install snapshots restored. Uninstall returns other
managed user files to the pre-BRZRK state.
