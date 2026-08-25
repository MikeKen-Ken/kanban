# System Architecture

## Product boundary

This project is a personal Windows and Android cross-platform kanban board. Core capabilities are multiple projects, column-based task flow, local-first storage, and WebDAV multi-device sync.

It explicitly does not include accounts, team members, realtime collaboration, or CRDT. Other platforms only need to avoid breaking existing conditional compilation; they are not current acceptance targets.

## Layers

```text
UI layer screens/widgets/features/*/ui
  ↓
Feature layer features/* (queries, commands, dispatch, import/export)
  ↓
App orchestration controllers/BoardController
  ↓
Storage and sync storage/ + webdav_sync/ + features/sync_conflict/
  ↓
Local JSON / SharedPreferences / WebDAV
```

- The UI layer only displays state and forwards user intent; it does not hold authoritative process state.
- Feature modules expose a small number of models, services, or page entry points; internal implementation stays in their own directories.
- `BoardController` orchestrates across modules and does not host independently testable filtering, date, recurrence, statistics, or parsing algorithms.
- Pure utilities used by two or more features belong in `app/lib/common/`.
- The storage and sync layers must not depend on specific UI.

## Data ownership

### Synced user content

- Project list, boards, columns, cards, project settings, and trash
- Board wallpapers (workspace-level `SharedContent.wallpapers` metadata + root `wallpapers/` files; project settings only store references and carousel policy)
- Image attachments
- Custom labels
- Saved views
- Card templates
- Activity history
- WIP configuration
- Reminder times and recurrence rules
- Card external links, dependencies, and relations
- Card Agent overrides (engine, model, parameters, whether a dirty working tree is allowed, whether automated tests are required)
- Card Agent Markdown conversation records (the card field is the authoritative text, with an `Agent 对话.md` file-attachment mirror)
- Swimlane grouping and automation rules

Synced content uses optional JSON fields or separate file extensions. Old clients must ignore unknown fields; new clients must use safe defaults when fields are missing.

### Device-local data

- WebDAV credentials
- Current project
- UI preferences such as light/dark mode, drag delay, and onboarding state
- Windows embedded MCP switch and port
- Agent dispatch preferences (engine, repo path, model, thinking level, whether card parameters may be used, whether a dirty working tree is allowed, and similar)
- Agent dispatch pending finalization transactions and commit-scope snapshots (device-local SharedPreferences only; not in workspace JSON / WebDAV)
- MCP agent run context (sub-agent / Git recovery stored per project and card)
- Undo stack
- System notification scheduling records
- SyncBase

## Main data flows

### Local edits

```text
User action
  → feature command
  → BoardController orchestration
  → immediate local persist
  → UI update
  → no automatic upload; upload / download / merge only when the user chooses
```

### Remote sync

```text
Upload: push the full local workspace, overwriting the cloud (requires second confirmation)
Download: pull the full cloud workspace, overwriting local (requires second confirmation)
Merge: pull remote → local/base/remote three-way merge → write conflict marks → persist locally → if there are differences, write back to remote
```

## Feature directories

New features go in `app/lib/features/<feature>/`:

- `views/`: today, calendar, global query, combined filters, and saved views
- `quick_capture/`: quick capture and natural-language parsing
- `undo/`: undoable commands and the device-local undo stack
- `templates/`: card templates and copy
- `reminders/`: reminders, recurrence rules, and platform scheduling
- `agent_dispatch/`: desktop local batch dispatch of Cursor SDK / Codex exec; Windows release builds ship a Worker; API keys use OS secure storage (device-local only). The Agent prompt only invokes the installed `kanban-complete-tasks` Skill; it does not contain copied Skill, Rule, Architecture, card, attachment, or MCP-schema text. Cursor uses the complete client-equivalent ambient settings stack (`all`: project, user, team, MDM, and plugins) for Rules / Skills / Hooks. Codex uses an isolated home that copies the user's `AGENTS.md` unchanged and copies only `%USERPROFILE%\.cursor\skills\kanban-complete-tasks`. Each claimed card gets a scoped `kanbanMCP` exposing `get_current_card`, `ready_to_submit`, `submit_consultation`, and `block_card`; `get_current_card` returns the immutable claimed work scope, effective test policy, and embedded file/image attachments. Extra MCPs such as Hub / Aseprite / Chrome DevTools / Tavily / Unity / Cocos / Node REPL come from the current project's `ProjectSettings.agentMcpTags`, merging the matching user MCP by project theme rather than card-label switches. The workbench local switch "end the session after completion" is on by default: after a terminal scoped tool persists successfully, the Worker cancels the Cursor SDK run or stops the Codex process; when off, it waits for the Agent to finish naturally for more session logs. A card may turn off "require tests"; the Skill follows the claim's effective policy and records why automated tests were skipped. Consultation status comes from the immutable claim's `cardKind`. `ready_to_submit` uses the Worker-reported Shell timeline to reject verification that is still running, failed, or implausibly short. Hard blocking of unbounded globs remains in the local user Cursor Hook (`%USERPROFILE%\.cursor\hooks`), not in this repository. If Git HEAD is a descendant of the claim baseline at finalize, the Worker restores it with `git reset --soft` and then creates the official trailered commit; checkout or rebase onto unrelated history is still refused. During a Cursor run, `ask_user` pauses for a card-conversation reply; later follow-ups restore context through a new rework claim.
- `mcp/`: Windows embedded MCP and one-click Cursor/Codex setup (device-local only)
- `statistics/`: read-only statistics
- `wip/`: column WIP-limit policy
- `activity/`: activity events, persistence, and merge
- `import_export/`: full backup, validation, and import
- `labels/`: shared custom label management
- `onboarding/`: first-run onboarding
- `app_update/`: check/download updates from GitHub Releases (Android APK install; Windows zip overwrite-in-place and restart)
- `automations/`: in-project automation rules (trigger → action)
- `kanban/`: column/card display, swimlane grouping, detail editing

Cross-feature date checks, identifiers, and result types live in `app/lib/common/`.

## Sync extension constraints

When adding or changing synced fields, also check:

1. `toJson` / `fromJson` and defaults
2. Content equality
3. Three-way field merge
4. SyncBase snapshot
5. WebDAV upload and download manifests
6. Conflict counts and the resolve UI
7. Compatibility tests for old data and old clients

Append-only activity history merges by event-id union. Recurring tasks use a stable series id and period key when generating the next occurrence so multi-device generation is idempotent.

## Verification

- Pure algorithms use unit tests.
- Storage and sync use model, merge, and integration tests.
- Windows shortcuts, context menus, and notifications need platform verification.
- Android notification permission, TalkBack, narrow layouts, and long-press drag need platform verification.
- During human development and CI: at least run `flutter analyze` and related tests; finally run the full test suite and Windows/Android builds.
- For cards where `agentRequireTests` is missing or true, the Agent must run targeted tests directly related to this card's changes in-session and only declare completion after they pass; when false, automated tests are not required, but necessary formatting, type checking, or user-requested acceptance should still run, and the declaration must record "This card has no test switch enabled". Do not hand test commands to the Worker to re-run, and do not treat the previous bullet's full `flutter analyze` / full suite as default completion. Hang or timeout must not count as pass; skipped UI verification must be marked as not executed. At `ready_to_submit`, if a test command was started but has not finished according to its `executionTime` (including the SDK emitting completed early), or the last valid test failed, the call must be rejected. End time is `startedAt + executionTime`; a short `cd ... &&` failure that PowerShell cannot execute must not overwrite already-passed verification.
