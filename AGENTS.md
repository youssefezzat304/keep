# Keep — Codex Project Guidance

Keep is a native macOS focus workspace built with SwiftUI. Its interface brings together an active project or task, Pomodoro and flow timers, a music area, and a task area.

This file defines the working agreements for Codex in this repository. Distinguish the existing UI prototype from implemented product behavior.

## 1. Project goals

Build a small, reliable focus experience before expanding the product or infrastructure.

The intended core flow, based on the current interface, is:

1. Choose the project or task to focus on.
2. Start a Pomodoro countdown or a flow timer.
3. See the active session and its controls clearly.
4. Use the supporting task and music areas when their behavior is implemented.

This flow describes the direction suggested by the interface, not completed functionality or a full product specification. See `docs/architecture.md` for the verified implementation state and `docs/decisions.md` for durable decisions and unresolved questions. Do not describe placeholders as working features.

Calendar displays recorded timer sessions with time editing and deletion. Stats analyzes recorded sessions and saved task/habit history. Notifications, additional music integrations, accounts, and sync require their own scoped work. Do not add them merely because they could be useful. Project/day time totals and manual edits now persist locally.

## 2. Technology and architecture

- Swift and SwiftUI.
- A native macOS application managed through Xcode.
- Asset catalogs and SwiftUI previews.
- Organize Swift under `Sources/Keep/{App,Core,Services,UI,Support}`, bundled assets/plist/entitlements under `Resources`, checks under `Tests`, and development tools under `Tools`. Keep canonical documentation in lowercase `docs`. This is one Xcode app/module; preserve the existing target and scheme.

Read `docs/architecture.md` for source boundaries, current dependencies, and build configuration. Verify relevant settings in `keep.xcodeproj/project.pbxproj` before making compatibility decisions.

Preserve the native SwiftUI approach. Do not add a web stack, package manager, backend, or cross-platform framework without an explicit architectural need agreed with the user.

## 3. Read the canonical documents

Before non-trivial work, read:

- `docs/decisions.md` — durable decisions, current snapshot, and open questions.
- Relevant sections of `docs/architecture.md` — implemented structure, responsibilities, and constraints.
- `docs/style.md` before UI or styling work — canonical visual direction and design tokens.
- The source files affected by the task; use the architecture document as a map, not a substitute for inspecting code.

Use the exact lowercase documentation paths. Do not create root-level duplicates or uppercase alternatives. There is no separate product specification yet; do not invent requirements to fill that gap.

When documentation and implementation disagree, inspect the source, distinguish intended behavior from current behavior, and correct stale factual documentation within the task's scope. Flag unresolved product or architectural conflicts. The style guide owns visual intent; use shared theme tokens rather than treating incidental colors as new palette decisions.

## 4. Code quality

- Prefer simple Swift code and the smallest coherent change that satisfies the task.
- Preserve repository conventions and avoid unrelated refactors.
- Reuse existing components where appropriate.
- Remove dead code created by the change; do not leave commented-out alternatives.
- Model meaningful states with explicit types and enums rather than unrelated Boolean flags.
- Avoid force unwraps, forced casts, and silently discarded errors.
- Keep user-facing error messages actionable and separate from diagnostic logging.
- Never represent placeholder behavior as a completed feature.

## 5. SwiftUI and state ownership

- Keep views focused on presentation, composition, and user interaction.
- Keep reusable UI in `Sources/Keep/UI/DesignSystem`; keep feature subdirectories within Core, Services and UI. Shared runtime stores/integrations belong in Services, value types/rules in Core, and window-local presentation state beside its views in UI. Do not create new modules or duplicate owners to match the folder layout.
- Introduce models or services when behavior warrants them, without creating speculative architecture.
- Use `@State` for view-owned state, bindings for state passed to child views, and observation when shared feature state requires it.
- Give each piece of state a clear owner; avoid duplicate sources of truth.
- Pass action closures into reusable controls instead of hard-coding feature actions or print statements.
- Avoid expensive work and side effects in `body`.
- Use structured concurrency for asynchronous work and handle cancellation and view lifecycle changes.
- Respect the project's actor-isolation settings. Keep UI mutations on the main actor and avoid blocking it with I/O or heavy work.
- Prefer native SwiftUI controls and behavior; use AppKit bridges only when a concrete macOS requirement calls for them.

## 6. Focus-session behavior

When timer behavior is requested:

- Model idle, running, paused, and completed states explicitly where applicable.
- Define the relationship between Pomodoro and flow sessions before coupling their state.
- Derive elapsed or remaining time from an appropriate clock and recorded timing state. Do not assume every UI timer tick arrives on time.
- Treat display refreshes separately from the source of timing truth.
- Define pause, resume, reset, completion, sleep, and wake behavior for the requested scope.
- Avoid duplicate ticking tasks and cancel work when its owner ends.
- Make session completion and any notifications predictable and testable.

Pomodoro and flow controls are independent and may run concurrently. Recorded time uses a single app-owned recorder: running Flow takes priority; otherwise only Pomodoro focus counts. Manual short/long Pomodoro breaks never add Pomodoro time. Route timer actions, settings changes, project changes, and Timesheet edits/removal/Undo through `WorkspaceModel` so elapsed time is settled before state changes. Settings changes preserve the duration of running/paused intervals; completed focus intervals advance the break cycle once. Removing a weekly row preserves the catalog and timers; new time may recreate the row, and Undo restores removed time without overwriting that new time. Preserve these rules. Consult `docs/architecture.md` for the implemented timing semantics and state lifetime.

Do not add notification permissions, background services, persistence, or music-provider integrations as incidental parts of a visual task.

## 7. Dependencies

Before adding a dependency:

1. Check SwiftUI, Foundation, and other existing Apple frameworks.
2. Check whether the repository already supplies the capability.
3. Verify compatibility with the installed toolchain and deployment target.
4. Prefer a small, maintained package that materially simplifies the work.
5. Explain meaningful dependency additions in the final response.

Use Swift Package Manager through the project's Xcode workflow when needed. Preserve generated package-resolution files when packages are introduced. Do not introduce CocoaPods, Carthage, or Node tooling for ordinary development.

## 8. Commands and Xcode workflow

Run commands from the repository root using the workflow in `docs/architecture.md`. Confirm available schemes before relying on them. A local unsigned build checks compilation; it does not validate release signing, sandbox permissions, or distribution.

Use the actual configured checks; do not claim nonexistent test, lint, or formatting commands passed. Prefer adding Swift files to the appropriate existing directory rather than unnecessary manual edits to the filesystem-synchronized Xcode group.

Do not commit DerivedData, build products, or personal Xcode user state. Preserve unrelated user changes.

## 9. Accuracy, recency, and sourcing

For SDK availability, framework APIs, package compatibility, distribution requirements, or other time-sensitive facts:

- Establish the current date and inspect the installed Xcode/SDK versions as needed.
- Prefer Apple documentation, installed SDK declarations, and upstream package documentation matching the project version.
- Use available documentation tools such as Context7 only when they cover the relevant library.
- Verify changing or uncertain technical claims with authoritative sources.
- Do not research unrelated topics when the repository already provides the needed answer.

Do not raise or lower the deployment target just to make an example compile without considering the product's compatibility requirements.

## 10. Remote services and production safety

Use read-only remote operations unless the task authorizes a mutation. Inspect before destructive actions and use a dry run when available.

Do not publish releases, change remote repositories or infrastructure, send messages, delete production data, or incur paid API usage without authorization. Existing authorization in the session applies; do not request it repeatedly.

Ordinary local edits, builds, and reversible verification are part of the development workflow.

## 11. Secrets, privacy, and capabilities

- Never print or commit credentials, access tokens, signing secrets, or private keys.
- Do not dump the entire environment or request secrets in chat when a safer authenticated workflow exists.
- If credentials become necessary, use an appropriate secure configuration or Keychain workflow; do not embed private credentials in the shipped app.
- Keep private local configuration out of Git.
- Treat imported files, URLs, and remote responses as untrusted input; validate at their boundaries using appropriate Swift types and decoding.
- Request only capabilities needed by the task. Preserve sandbox and signing settings unless a requested feature requires a documented change.
- Do not log personal task content or session data unnecessarily.

## 12. Host tools and containers

Use the native macOS/Xcode workflow. Ordinary app development does not require containers, Dockerfiles, or service infrastructure.

Do not install system packages or change the selected Xcode installation without user authorization. Inspect the current toolchain first and explain any actual requirement that cannot be satisfied with installed tools.

## 13. Reading documents and references

Read enough of a source to understand the relevant context. Do not infer unseen content or invent product requirements.

Inspect visual references when a task depends on their appearance. Use `docs/style.md` for semantic design rules and the images for visual context; do not copy unrelated reference content into Keep. The reference images are local and Git-ignored, so do not assume they exist in every checkout.

## 14. Baseline workflow and planning

For a non-trivial task:

1. Determine the goal and acceptance criteria from the request and repository.
2. Read `docs/decisions.md` and the relevant sections of `docs/architecture.md`.
3. Read applicable guidance, relevant source, and `docs/style.md` for visual work.
4. Identify affected feature, design-system, and project boundaries.
5. Resolve uncertainty from the repository before asking unnecessary questions.
6. Implement the smallest coherent change.
7. Verify behavior and appearance at the appropriate level.
8. Update the canonical documents when implementation or new findings change durable project knowledge.

Use a short execution plan for complex work. Ask for clarification when a material product or architectural choice remains unresolved; continue independent work where possible.

## 15. Continuity ledger

The canonical continuity ledger is `docs/decisions.md`. Read it for non-trivial work. Do not maintain a second ledger.

Update it for meaningful product, architecture, constraint, or implementation-direction changes. Record existing implementation as `[CODE]` evidence; do not turn a suggestion or inference into an approved `[USER]` decision.

Use these sections as needed:

```text
[SNAPSHOT]
[DECISIONS]
[PROGRESS]
[DISCOVERIES]
[OUTCOMES]
[WORKING SET]
[RECEIPTS]
```

Keep the snapshot to roughly 25 lines and the active working set to roughly 12 paths. Record ISO dates and provenance tags (`[USER]`, `[CODE]`, `[TOOL]`, or `[ASSUMPTION]`). Mark unknowns `UNCONFIRMED`. Preserve superseded decisions explicitly rather than rewriting history.

Keep recent milestones and command outcomes concise. Compress older history; do not store transcripts, raw logs, or a micro-task checklist.

## 16. Testing and verification

- For source changes, run an appropriate Xcode build when the installed toolchain supports the project.
- For timer state, persistence, or other significant domain logic, add or run focused tests that verify behavior rather than implementation details.
- For UI changes, inspect the affected SwiftUI previews or running app at relevant window sizes, including the default size documented in `docs/architecture.md` and a narrow window.
- Check keyboard operation, focus visibility, labels, contrast, text clipping, and appearance modes affected by the change.
- Avoid adding tests solely for reversible documentation or cosmetic edits.
- Fix errors introduced by the change without expanding into unrelated refactoring.
- Report exactly what ran. If verification is blocked, state the toolchain or other limitation and what remains unverified.

## 17. Documentation ownership

- `AGENTS.md` owns agent working agreements.
- `docs/architecture.md` owns the source map, component responsibilities, state and data ownership, build workflow, and verified implementation constraints.
- `docs/decisions.md` owns durable decisions, current snapshot, significant findings, and unresolved questions.
- `docs/style.md` owns visual language, palette, typography, and UI implementation guidance.
- Source and `keep.xcodeproj` provide evidence of the actual implementation and build configuration.

As understanding of Keep improves, make `AGENTS.md` and `docs/architecture.md` clearer within the same task:

- Replace vague guidance with specific rules supported by source or explicit user decisions.
- Update architecture when responsibilities, state ownership, dependencies, setup, or constraints change, or when a significant discovery corrects an earlier description.
- Update agent guidance when a discovery changes how future work should be done.
- Keep current implementation, agreed direction, and open questions distinct. Remove obsolete statements and consolidate duplicates.
- Record the evidence or durable decision in `docs/decisions.md` when meaningful.

Do not edit every document after every task. Routine cosmetic changes and trivial fixes do not require ledger entries. Keep stable working rules here and detailed implementation facts in architecture so they can be maintained in one place.

## 18. Definition of done

A task is complete when the requested change is implemented, relevant verification has run, new errors are addressed, and necessary documentation is updated.

The final response should state what changed, where, how it was verified, and any material limitation. Do not claim completion of functionality that remains a placeholder or verification that did not run.

## 19. Current project direction

Focus and Dashboard’s Timesheet/Calendar share the app-owned `WorkspaceModel` and project catalog. Create projects through the workspace; the saved custom catalog is separate from time entries so projects can persist before their first session. Preserve loading of older records without the catalog field. Project catalog deletion persists removed IDs while preserving recorded history. Project name/color edits preserve IDs, durations and completion-event snapshots; update catalog and entry/session/activity display metadata through WorkspaceModel, invalidate affected read-index caches, and resolve current metadata on Undo/stale callbacks. Built-in edits persist as validated optional projectOverrides; legacy archives default to none. Settle recording before deletion; deleting the selected project switches to No project without stopping either timer. Preserve legacy archives without deleted IDs, and never reseed deleted built-in projects or resurrect them through Timesheet Undo. Created projects, recorded timer sessions, project/day totals, and manual edits persist locally; timer runtime and input drafts are not restored after quitting. Keep numeric fixtures in `Sources/Keep/Support/PreviewData/` for previews only. Never seed the live ledger with sample history or store separately calculated totals.

Dashboard owns its shared browsed week and Timesheet / Calendar / Projects selection; keep these view states window-local and preserve the fixed shell viewport. Calendar uses actual `RecordedSession` intervals from the single workspace recorder; never infer timestamps from old or manually edited daily totals. Preserve older archives without the optional sessions field. Session boundaries capture project/task/source changes, pauses, and midnight. Task suggestions/pins persist separately from the current task in the workspace archive as project-linked activity. Remember nonblank tasks only during recording actions; keep pins before recents, filter deleted projects, migrate legacy activity from real sessions, and settle recording before selecting a suggestion or pinning. Suggestion selection changes task/project together without autoplay. Current committed task text is app-shared runtime state; only the window-local `FocusTaskEditor` owns its draft. Commit it before timer actions or leaving Focus, not on every keystroke. Calendar time edits/deletion must settle through WorkspaceModel, adjust the project/day total by the duration delta without going below zero, and start a fresh recorder segment. Keep edits within the saved civil day/timezone; Habit tracker has its own manual daily progress model.

Stats filters and prepared snapshots are window-local. Derive focus analytics from recorded sessions, with adjusted Timesheet totals separate; never infer task/hour history from manual totals. Preserve Flow priority and civil-day/timezone attribution. Completed Pomodoros are separate once-only ledger events attributed to the target at the actual completion boundary, before subsequent target changes; time edits/deletion must not rewrite them. Preserve legacy archives without completion fields and retain tracking coverage instead of estimating counts. Task and habit summaries have date-only scope and must be labelled accordingly. Coalesce/fence background Stats calculations, cancel while hidden and reuse the existing workspace refresh. Always show streaks; save optional goals in AppPreferences; the weekly goal always covers this week/all projects. See architecture for range, comparison and streak semantics.

Preserve one recorder and one owner of Timesheet persistence across tabs and windows. Test overlap, focus/break exclusion, edits during recording, project changes, day boundaries, and reloads when changing recording behavior. Do not reintroduce direct timer bindings that bypass settlement.

Keep history caches disposable and runtime-only. Ledger mutations must emit the corresponding typed WorkspaceChange; WorkspaceModel drains them into its app-owned WorkspaceReadIndex after settlement. Successful reloads replace the index epoch. Preserve task/habit runtime revisions, four window-local Stats queries, eight window-local weekly projections, hidden-page preparation guards, and cancellation fences. Avoid retaining whole ledger arrays or rebuilding history inputs on recording ticks. Apple Music metadata caching stays in the shared serial controller, expires after 60 seconds from the original fetch, and must verify actual scoped access even on a hit; Refresh/Retry, denied access, provider shutdown and process replacement invalidate it. See architecture for retention limits and benchmark commands.

The menu bar presents the same app-owned workspace, task store and music player; never create duplicate runtime models or tickers for it. Preserve the leaf icon, optional selected timer text, independent timer controls, today's shared task checkboxes and selected-provider playback controls without a provider switcher. Task checks route through DailyTaskStore/HabitStore and revalidate origin and actual day at activation. The sliding target page owns a local name/search draft: Back/Escape/dismissal cancels, committing names and selecting projects/recent tasks settle through WorkspaceModel without autoplay. Keep inactive pages out of keyboard/accessibility navigation and honor Reduce Motion. Hiding the status item or closing workspace windows must not stop recording/playback. Save menu behavior in AppPreferences with legacy archive defaults; status text uses the existing workspace display checkpoint. The menu control page must not scroll: keep timer controls and music visible, and bound scrolling to Today's task list and the target picker. Combined controls in the menu and main app switch to Stop both while both timers run; stop through WorkspaceModel.stopBothTimers to settle once and preserve elapsed/cycle state. Give the native panel a nonzero viewport and verify minimum native size proposals; an externally sized screenshot alone cannot catch a collapsed MenuBarExtra.

Habits have one app-owned `HabitStore` in `Sources/Keep/Services/Habits`, separate from workspace recording and daily tasks. Save definitions and unique habit/day logs in `keep.habits.v1`; failed loads preserve saved bytes and block changes. Keep browsing and sheet drafts window-local. Identity editing reuses the original creation dialog with only name/icon enabled; preserve the latest saved UUID, goal, schedule and logs through HabitStore.updateIdentity. Use Gregorian civil keys and calendar day arithmetic; start/end dates are inclusive, future progress is disabled, and partial amounts count complete only when the daily goal is met. Derive intensity, totals/rates, and streaks from logs rather than persisting aggregates. Persist a nonempty unique weekday selection; missing frequency in older archives means all seven days. Rest days reject progress and are excluded from completion rates. Current/best streaks count consecutive scheduled check-ins, skipping rest days; current streak may end on the latest previous due day while today is pending, and ends after the date range. Never infer habit completions from timers. Explicit checkbox actions on projected habit tasks update the same HabitStore log; do not copy completion into task persistence. Keep live archives empty of fixtures and add focused date/persistence/streak checks when changing this behavior.

Tasks have an app-owned `DailyTaskStore` in `Sources/Keep/Services/Tasks`, separate from timer recording and music. Persist tasks/completion by civil day in `keep.tasks.v1`; keep selected day and per-day input drafts window-local. Navigate with calendar day arithmetic, preserve stable task IDs, and scope completion/deletion to the rendered day. Seed examples only in previews. Failed task loads must not overwrite saved data. Task-row Focus/Flow/both actions commit the editor and call `WorkspaceModel.startTask`; preserve the shared current task/project and Flow recording priority. Focus exits a break into focus without clearing cycle progress. Only Today exposes timer launch controls/actions, and callbacks must recheck the actual civil day at activation. Project scheduled habits through the shared HabitStore, retain explicit origins/stable row identity, and persist only per-day hidden occurrences when removing them from Tasks. Keep the both-timers button on its fixed neutral tokens, and expose hover actions to keyboard and VoiceOver.

Music has a separate app-owned `MusicPlayerModel`, native Audius AVPlayer adapter, and serial `AppleMusicController` in `Sources/Keep/Services/Music`. Keep playback independent of timer recording and alive across tab changes. Resolve Audius signed HTTPS stream URLs on demand, never persist/log them or add credentials for public playback. Fence canceled requests and replaced-item callbacks, derive Playing from AVPlayer state, and keep tests silent. Preserve outgoing-network sandbox access without adding microphone permission. Apple Music controls the Mac’s Music app and its existing account/queue; request only the `com.apple.Music.playback` and `com.apple.Music.library.read` scripting groups, with normal Automation access on explicit Browse or Play. Library sheets own their query/selection/paging, share the serial controller, and never autoplay on Browse. Use Music’s source → library playlist hierarchy and retain playlist context in native track references. Cancel/fence stale searches and bound result pages and artwork bytes. Recover transient Music reads and delayed covers without replaying; stop observation on denied access. Settings permission probes must use actual scoped reads without prompting/launching Music; only explicit requests may launch/request consent. Gate checks on the visible Settings tab, and never archive permission status. Search with read-only metadata filtering rather than Music’s rejected native search command; do not expand library access to work around it. Avoid wildcard permission preflights that exceed the scoped entitlement. Keep native events off the main actor, fence late replies, preserve paused intent on skips, and await owned playback release on termination. Provider selection/restoration must not launch Music or request access. Persist provider/volume in AppPreferences, preserving older archives without those fields; never change system output volume. Native library browsing/search and current cover art are implemented; full streaming-catalog search requires separately configured MusicKit, and library writes and zen mode remain unimplemented. Reuse WallpaperLibrary’s native-cover thumbnail for the sheet and selected Track artwork backdrop; preserve custom wallpapers and keep bytes out of archives.

Appearance/music settings have a separate app-owned `AppPreferences` archive in `keep.preferences.v1`. Do not merge it into timer or task persistence. Keep Light/Dark/System at the shell and use semantic asset variants; child sheets/popovers and the menu panel must inherit appearance. Use the shared keepAppearance modifier to resolve both presentation and content color scheme. Start on login uses the app-owned LoginItemModel and SMAppService main-app registration; macOS owns status, with writes only on explicit user changes and no duplicated preference Boolean or background helper. Invalid preference loads must preserve saved data and block edits.

Wallpaper folders use app-scoped read-only security bookmarks, never persisted raw paths. Balance scoped access, decode images/video posters off the main actor, and cancel/fence stale loads. MP4 wallpapers loop silently through native AVPlayerLooper independently of music; retain read-only folder access for resource/renderer lifetime, pause hidden/occluded video renderers, and use a still poster for Reduce Motion, glass crops, background wash and palette. Never archive video bytes/paths or add per-frame palette processing. One app-owned `WallpaperLibrary` handles folder rotation and remote-artwork decoding across windows. Share its image/fallback and runtime sampled palette between the player, blurred window backdrop, panel, and timers; do not duplicate image requests or replace tab content when artwork changes. Keep Reduce Transparency’s opaque music-card fallback. Saved Audius channels support artists and playlists. Restoring a source or choosing it through the passive menu must not autoplay or fetch until Play; clicking a saved-drawer row is an explicit Play action. Keep the drawer open through playback until its toggle is clicked again. Favorites must fit the card’s existing allocation: use a compact list in place of transport controls when necessary, without changing outer page geometry or pausing playback. Heart removal unsaves the source without interrupting playback. Keep temporary stream URLs out of preference archives.

Artwork tints must retain light/dark text contrast and use the existing decoded-image pipeline, without separate fetches or per-view scans. Project labels/icons must keep the selected project hue with a readable shade. Decorative overlays must opt out of hit testing; give custom menu labels a full padded content shape and keep decorative borders noninteractive. Glassiness and music volume use native SwiftUI Slider controls with continuous preview updates and comfortable tracking areas; the normalized glassiness preference remains its single source of truth. Use `KeepScrollView` for consistent thin native overlay scrollbars with transparent tracks. Compact navigation must retain accessible labels. The working-on card stays neutral until a control receives actual focus; entering the task editor requires an explicit action.

Zen presentation is window-local and uses the existing workspace, music model, and decoded wallpaper. Preserve recording/playback through entry and exit; return to windowed mode only when Zen initiated full screen. Observe native window transitions without replacing SwiftUI’s window delegate.

Preserve the native macOS focus-workspace structure. Follow `docs/style.md` for the cozy editorial visual direction. Treat the reference images as inspiration rather than a mandate to reproduce their page structure.

Do not replace established technologies or introduce speculative features as part of unrelated work.

Software updates use one app-owned Sparkle 2 controller in `Sources/Keep/Services/Updates`. Keep Sparkle's preferences/scheduler separate from AppPreferences and timer ticking. Debug/previews must not perform real update checks or install releases. Preserve signed-feed/archive verification, App Sandbox and the documented installer-service exceptions. Restart preparation must settle/save through WorkspaceModel and respect running/paused timers before invoking Sparkle's continuation. Keep the private EdDSA key in Keychain/protected release secrets; only its public key belongs in configuration. Consult `docs/updates.md` for release preparation; local integration does not authorize publishing a GitHub release or changing remote infrastructure.

## 20. Commit messages

After a completed code or documentation task, suggest one concise Conventional Commits message:

```text
<type>(<optional scope>): <short imperative description>
```

Examples:

```text
feat(timer): add Pomodoro pause and resume
fix(session): preserve elapsed time after wake
docs: add project guidance and cozy visual style
```
