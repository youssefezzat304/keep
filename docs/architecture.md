# Keep — Architecture

Keep is a native macOS focus workspace built with SwiftUI. This document describes the verified implementation and the boundaries to preserve as behavior is added. It is not a roadmap or a claim that the displayed features are functional.

## 1. Current implementation

The application is a first visual draft with one application target. Timers record project time into an editable, locally saved Timesheet. Timers, projects, saved daily tasks, and music are shared across the app’s windows; task-day selection, input drafts, and task-name drafts remain window-local. Music streams public lofi tracks from Audius through native AVPlayer, with app-shared playback and volume state.

| Area | Implemented today | Not implemented |
| --- | --- | --- |
| App window | `WindowGroup`; 1000 × 900 default size; 680 × 650 minimum content frame; fixed panel with scrollable tabs; one shared workspace model | Restoring timer runtime or unfinished task input across launches |
| Navigation | Selectable Focus and Timesheet tabs; shell-owned selection; disabled Stats and Settings controls | Stats/Settings destinations |
| Timesheet | Live project/day seconds, computed totals, seven-day grid, week navigation, manual edits, weekly row removal with Undo, Add project, and local saving | Detailed session log, calendar/list alternatives, sync |
| Active target | Searchable shared project catalog; creation dialog with name and 30 colors; local saving; selection drives recording; separate editable task name | Project renaming/deletion and task-level time records |
| Pomodoro | Settings popover for focus/short/long breaks and iterations; saved preferences; manual short/long breaks; independent controls; focus-only recording | Automatic interval starts, notifications |
| Flow timer | Elapsed time, independent controls, and recording priority over Pomodoro | Detailed session history or a completion limit |
| Music | Audius lofi discovery/streaming via AVPlayer; play/pause, previous/next, volume/mute, loading/buffering, Retry, and track attribution over bundled cozy artwork | Offline audio, accounts/gated tracks, saved queue/preferences |
| Tasks | Saved per-day lists; previous/next, date picker, Today; completion/add/delete and internal scrolling | Reordering, recurrence, project association |
| Design system | Semantic color assets, `KeepTheme`, reusable action button, flexible card modifier | Dark theme |

Both timers may run at the same time, with independent controls. Flow overrides Pomodoro for recording; overlapping time is counted once. Project/day totals and manual edits survive relaunch; timers restart idle. Daily task lists and completion states survive relaunch; task names and unfinished input remain unsaved drafts. The live task store starts empty; examples appear only in previews.

## 2. Repository structure

```text
AGENTS.md                          Agent working agreements
docs/
  architecture.md                  Structure, responsibilities, and build workflow
  decisions.md                     Durable decisions and continuity
  style.md                         Canonical visual direction
keep.xcodeproj/                     Xcode project and application target
keep/
  App/
    KeepApp.swift                  @main entry point, shared workspace/music/tasks, WindowGroup
    WorkspaceApplicationDelegate.swift  Recording flush and music shutdown on termination
    AppShellView.swift             Navigation and focus-workspace composition
  DesignSystem/
    KeepTheme.swift                Semantic references to named color assets
    FocusProjectStyle.swift        Shared project-to-theme presentation mapping
    Components/
      NavBar.swift                 Shared navigation presentation
      PrimaryButton.swift          Shared action button with caller-supplied closure
      ProjectPicker.swift          Searchable project selection shared by Focus/Timesheet
      ProjectCreationDialog.swift  Shared name/color sheet with caller-owned creation action
      RemoveRowButton.swift        Accessible × button shared by task and Timesheet rows
    Modifiers/
      CardStyle.swift              Shared card treatment and View.cardStyle extension
  Models/
    WorkspaceModel.swift           Shared timers, project selection, recorder, save coordination
    FocusProject.swift             Shared project catalog and Codable metadata
  Features/
    FocusSession/
      Models/                      FocusTimer timing/cycles and PomodoroSettings
      Views/                       Focus workspace, timer/settings popover, and supporting panels
    Tasks/
      Models/                      FocusTask, civil-day selection, DailyTaskStore, TaskPersistence
      Views/                       TasksCard, day navigation, and date-picker popover
    Music/
      Models/                      MusicTrack, playback/failure states, MusicPlayerModel
      Services/                    AudiusClient and native AVMusicPlayback adapter
      Views/                       MusicPlayerCard and accessible playback controls
    Timesheet/
      Models/                      TimesheetLedger, calendar/duration helpers, local persistence
      PreviewData/                 Numeric fixtures used only by previews
      Views/                       Weekly timesheet page and seven-day table
  Assets.xcassets/                  Named colors, CozyCorner artwork, and AppIcon
tests/FocusTimerChecks.swift        Standalone deterministic timing checks
tests/WorkspaceChecks.swift         Recording, editing, calendar, and persistence checks
tests/MusicPlayerChecks.swift       Playback state, cancellation, and HTTP contract checks
tests/DailyTaskChecks.swift         Daily navigation, task isolation, and local persistence checks
reference/                         Local, Git-ignored visual references
```

All Swift sources belong to the same application module. Directory boundaries express responsibility, not separate packages or targets. The `keep` source directory is a filesystem-synchronized Xcode group; documentation and reference images sit outside it.

## 3. View composition

```text
keepApp → WorkspaceModel → FocusTimer + TimesheetLedger + TimesheetPersistence
└── WindowGroup
    └── AppShellView
        ├── NavBar
        │   └── Focus and Timesheet actions; disabled Stats and Settings
        ├── ScrollView → TimesheetView
        │   └── TimesheetTable → TimesheetTimeCell → TimesheetEntryEditor
        └── ScrollView → FocusSessionView
            ├── ActiveTargetHeader
            │   └── ProjectPicker → WorkspaceModel.projects; ProjectCreationDialog sheet
            ├── TimerWorkspaceCard
            │   ├── PomodoroTimerPanel → FocusTimerCard
            │   └── FlowTimerPanel → FocusTimerCard
            └── Supporting cards (HStack or VStack)
                ├── MusicPlayerCard
                └── TasksCard
```

`TimerWorkspaceCard` selects a horizontal or vertical arrangement of the two panels. Each panel passes a timer snapshot and caller-owned actions to `FocusTimerCard`. All actions go through `WorkspaceModel`. `FocusSessionView` owns only the task-name draft; it reads shared projects/timers and composes the music and daily-task feature views.

`AppShellView` owns `WorkspaceTab` selection and supplies Focus/Timesheet action closures to `NavBar`. Navigation stays outside the scrolling content. Each tab has a separate, mounted ScrollView in the same fixed viewport; the inactive tab is invisible and hidden from hit testing and accessibility. This preserves drafts and each tab's scroll position without changing the panel size. Shared `PrimaryButton` receives its action from the caller.

## 4. Responsibility and dependency boundaries

| Location | Owns | Keep outside it |
| --- | --- | --- |
| `App` | Launch, shared model assembly, window composition, tab selection, and termination flush | Feature timing calculations and provider-specific logic |
| `Features/FocusSession` | Focus UI and session-specific state, actions, and rules | Generic styles and unrelated feature behavior |
| `Models` | Shared project metadata and coordination of timer recording with the ledger | View layout and provider integrations |
| `Features/Tasks` | Per-day tasks, civil-date navigation, local persistence, task-card UI | Timer recording, music state, and project assignment |
| `Features/Music` | Audius read-only discovery, stream resolution, AVPlayer lifecycle, playback state, and card UI | Timer recording, persistence, credentials, and provider writes |
| `Features/Timesheet` | Numeric ledger, calendar/duration helpers, local saving, editable UI, and preview fixtures | Independent timer mutation and overlapping recorders |
| `DesignSystem` | Reusable presentation, control styles, layout conventions, and theme tokens | Session state, persistence, provider calls, and feature actions |
| `Assets.xcassets` | Named colors and bundled visual resources | Domain behavior and credentials |

The current composition is `App` → feature views and design-system views; feature views reuse the design system. Future business logic should remain independent of the visual components that display it. A shared button should receive an action from its caller.

There is no established MVVM layer, repository abstraction, service container, or package decomposition. Add a model or service only when implemented behavior needs it. Place feature-owned additions with the feature; introduce a shared boundary only when there is a concrete cross-feature need.

## 5. State and data ownership

`KeepApp` creates one `@State` reference to the observable, main-actor `WorkspaceModel` and passes it into every window. It owns two `FocusTimer` values, the selected project, the numeric ledger, and one update task. Shells own tab selection; Focus views own task-name drafts, and each TasksCard owns its day selection/input drafts. Previews construct models without persistence and cannot write live history.

`FocusTimer` is a value type using `ContinuousClock.Instant` plus accumulated elapsed seconds. Timer display refreshes are separate from timing truth. The workspace accepts injected clock instants and dates for deterministic checks.

Implemented timer and recording semantics:

- Pomodoro defaults to 25-minute focus, 5-minute short breaks, 15-minute long breaks, and a long break after four completed focus intervals. The timer/cup icon opens a settings popover with editable minute/count fields and native steppers, Save, and Cancel. Valid ranges are focus 1–180 minutes, short break 1–60, long break 1–120, and iterations 1–12.
- Focus completion waits for a manually started break or Focus again. Short breaks preserve cycle progress. Starting a due long break begins a new cycle; skipping it keeps a long break due until chosen. Break completion waits for the next focus interval. No interval starts automatically.
- Each completed focus interval advances the cycle once, including delayed refreshes and skipped breaks. Flow recording priority does not affect Pomodoro cycle progress. Reset clears cycle progress and starts fresh focus; relaunch also starts a fresh cycle.
- `WorkspaceModel.updatePomodoroSettings` settles recording and validates/saves configuration. Running or paused intervals retain their original duration and elapsed time; later intervals use the new settings. Idle countdowns update immediately. Cancel/dismissing the popover discards its draft. Settings are shared across windows; runtime progress is not saved.
- Flow counts up from zero. Both timers have independent Play, Stop/Continue, and Reset controls, and may run concurrently.
- Stop preserves elapsed time; Continue excludes stopped intervals. Repeated Play does not restart a running interval. Reset returns that timer to its configured focus duration/zero without deleting recorded time.
- Every timer action, project change, and manual edit settles recording before mutating state. There is no writable timer binding in the views.
- Running Flow contributes the entire monotonic interval. Otherwise a running Pomodoro focus interval contributes only its remaining focus duration. Breaks contribute zero Pomodoro time, including delayed completion updates. Overlap contributes once; stopping Flow falls back to running focus.
- Selecting another project settles the old project first; only future time goes to the new selection. No project records under an explicit unassigned row. Task-name changes do not affect recording.
- The workspace updates approximately once per second, across tabs and windows. Clock differences determine duration; missing refreshes do not lose time. `ContinuousClock` includes system sleep and excludes wall-clock adjustments from duration calculations.
- Recorded intervals split at local calendar midnights, including DST days of 23 or 25 hours. Duration is mapped from the previous checkpoint’s civil date; later wall-clock changes affect subsequent date attribution.
- Timers and selection are app-scoped, continue while Keep runs, and restart idle on relaunch. No time is counted while the app is quit. Closing a window does not end app-owned timers.

`TimesheetLedger` stores one numeric seconds value per project ID/local day ID, together with project metadata. It also stores a separate `customProjects` catalog, so a created project survives relaunch before it has any time entries. `WorkspaceModel.projects` combines the four built-in projects with this saved catalog. Rows appear immediately when recording starts or a project is added manually. Daily, project, and weekly totals are derived from entries. The UI initially shows the current Monday–Sunday week; arrows navigate history and This week returns to the current week.

`TimesheetTimeCell` opens a native `TimesheetEntryEditor` popover. The editor accepts nonnegative `h:mm` or `h:mm:ss`; blank sets the cell to zero. Invalid input stays in the editor with an explanation. Saving replaces the cell total after settling the running timer; later elapsed time adds to the edited value. A zero cell retains its project row. Timesheet has project/day aggregates, not individual sessions or task-level records.

The trailing × removes a project's entries for the displayed week through `WorkspaceModel.removeTimesheetProject`. It settles recording before removal and saves immediately, preserving other projects, other weeks, catalog metadata, selection, and timer state. A running timer can create the row again with subsequent time. The model keeps one in-memory `TimesheetRemoval` for Undo across tabs/windows; Undo settles again and adds back removed time alongside newly recorded/edited values, then saves. Undo history is not restored after quitting. `TimesheetView` shows the removal/Undo notice and explains continued recording when applicable.

`TimesheetPersistence` JSON-encodes the ledger, custom catalog, and optional `PomodoroSettings` into the app’s standard `UserDefaults` under `keep.timesheet.v1`. Older records without the added fields load with an empty custom catalog and default timer settings, retaining their entries. It loads on app model creation, saves about every five seconds during recording, and saves immediately after actions/edits/creation/settings changes. `WorkspaceApplicationDelegate` flushes the last partial interval on normal app termination, including when no windows remain. Abrupt termination can lose time since the last checkpoint save. Corrupt saved data, including invalid settings, blocks mutations and shows Retry rather than overwriting unreadable records. Timer runtime, task-name/input drafts, and project selection are not persisted. Daily task lists use their own persistence below.

`ActiveTargetHeader` and `TimesheetView` own picker and creation-sheet presentation. `ProjectPicker` owns transient search/hover/focus state and searches the shared catalog by name. Its Create action closes the popover and opens `ProjectCreationDialog`, which owns only draft name/color/error state. The dialog offers 30 named color swatches, a selection checkmark, keyboard focus, and native Create/Cancel shortcuts. Cancel discards drafts. `WorkspaceModel.createProject` trims names, requires 1–80 characters, rejects case/diacritic-insensitive duplicate names and invalid colors, assigns a UUID, and saves the catalog without inventing time entries. Focus selects the created project and returns focus to the task field; Timesheet adds it to the displayed week without changing the active timer project. `DesignSystem/FocusProjectStyle.swift` maps Codable project accents to named color assets; the neutral accent is reserved for unassigned time. `TimesheetPreviewData` supplies numeric sample data exclusively for previews.

`KeepApp` owns one observable `DailyTaskStore`, passed through AppShellView/FocusSessionView to TasksCard. Task changes are shared across windows independently of timer recording and music. `FocusTask` has a stable Codable UUID, title, and completion state; `TaskArchive` maps Gregorian `yyyy-MM-dd` civil-date keys to task arrays. The live store starts empty, with example tasks confined to previews.

Each `TasksCard` owns `TaskDaySelection`, a date-picker draft, focus, and unfinished input keyed by day. Previous/next arrows use calendar day arithmetic rather than 24-hour offsets. Clicking the date opens a native graphical DatePicker with a typed date field; Show tasks selects the specific past/future date. Today returns to the current day; following Today crosses midnight automatically through the workspace's existing day refresh, while a browsed date stays pinned. Selecting another day preserves that day's input draft and resets list scrolling. Civil-date keys keep saved plans on their original dates across timezone changes; the task calendar follows the supplied calendar's timezone while retaining Gregorian keys.

Adding, checking, or deleting a task targets the rendered day and stable task ID, so delayed callbacks cannot change another day's task. Each day's remaining count is derived from its own list. Blank ruled rows fill the available list area, and the add field stays at the card's bottom. There is no automatic carry-forward, recurrence, project link, or timer effect.

`TaskPersistence` JSON-encodes the complete archive into UserDefaults under `keep.tasks.v1` after every task mutation. It is separate from the Timesheet key and leaves existing time/catalog/settings data intact. Invalid JSON, invalid civil dates, blank task titles, or duplicate IDs within a day block edits and show Retry, preserving unreadable data. Save failures retain in-memory changes and offer a save retry. Task lists/completion survive relaunch; selected day resets to Today and input drafts are not saved. Previous unsaved prototype tasks have no persisted data to migrate. Previews use stores without persistence. There are no notification permissions, databases, or credentials.

`KeepApp` also owns one observable, main-actor `MusicPlayerModel`, passed through each shell and Focus view. It is independent of timer recording, persists across tab/window changes while the app runs, and stops at app termination. No playback, queue, or volume state is restored across launches. Previews stay idle and make no network calls until Play.

Music behavior and external boundary (verified against the [Audius REST reference](https://api.audius.co/v1) and [Apple AVPlayer documentation](https://developer.apple.com/documentation/avfoundation/avplayer) on 2026-10-05):

- `AudiusClient` uses an ephemeral URLSession without a disk cache against `https://api.audius.co/v1`, searches `tracks/search?query=lofi&limit=30&includePurchaseable=false`, and identifies requests with `app_name=Keep`. Current public read-only endpoints need no API key. Decode numeric/access flags explicitly; reject gated, unavailable, deleted, unlisted, inaccessible, duplicate, or invalid-ID tracks. Track titles/artists appear in the card with a safe Audius attribution link.
- Resolve `tracks/{id}/stream?no_redirect=true` when selecting/retrying a track. Audius returns a temporary signed HTTPS audio URL; pass it to AVPlayer and never save/log it. Metadata can outlive audio: stream-lookup 403/404 results advance to the next candidate, bounded by the queue length. A fully unavailable queue shows an error. Network/rate-limit errors stop discovery and offer Retry.
- `AVMusicPlayback` owns AVPlayer, item/status KVO, and end/failure notifications. Actual `timeControlStatus` drives Playing versus Loading/buffering. End advances/wraps the queue; previous/next preserve paused intent. Play resumes the current item after pause. Volume is clamped to 0–1; the card adds mute/unmute with a remembered nonzero level.
- State is explicit: idle, loading, playing, paused, or failed with actionable text. Pause cancels discovery/stream resolution; item and request identities prevent delayed callbacks from restarting canceled/replaced audio. Requests have 20-second timeouts; active loading/buffering has a 30-second watchdog and Retry. App shutdown cancels tasks, removes observers, and releases the current item.
- `MusicCatalog` and `MusicPlayback` protocols allow deterministic network/player fixtures. No third-party package, backend, write endpoint, credentials, microphone permission, or offline downloading is introduced. Audius remains an external service; availability and rate limits can vary.

Project management, task-level session history, additional music providers, and notifications remain scoped future work. See `docs/decisions.md`.

## 6. Visual implementation and layout constraints

`docs/style.md` owns the cozy editorial palette. Named color assets are the source of truth; `KeepTheme` provides shared semantic references. The first draft explicitly uses light appearance to keep fixed warm surfaces and foregrounds consistent.

The shell places a cream workspace over peach surroundings. Pomodoro focus uses terracotta, its break uses butter yellow, and flow uses sage. Tasks use an ivory ruled-list treatment. The music artwork is a bundled asset in `keep/Assets.xcassets/CozyCorner.imageset/`; its generation prompt and provenance are in `docs/music-artwork.md`.

Layout and accessibility behavior:

- Default window size is 1000 × 900; the root view has a 680 × 650 minimum frame.
- The panel fills the usable window content area with equal 16-point margins on all four sides and 24-point inner padding. Its size depends on the window, not the selected tab or content height. Navigation stays at the top; longer tab content scrolls inside the panel. There is no fixed maximum panel width.
- Below 820 points of window width, timer and supporting card pairs stack vertically.
- The Timesheet table keeps a minimum width of 900 points and scrolls horizontally on narrow windows, preserving readable seven-day columns, totals, and the trailing remove button. Its heading and week toolbar can stack using `ViewThatFits`.
- The target header uses `ViewThatFits` to move its project/task card below the heading when needed. Its native popover is 340 points wide with a scrollable project list; the folder button and project rows show hover and keyboard-focus feedback.
- `CardStyle` supplies padding, flexible width, and rounding without imposing fixed maximum heights.
- The shell passes the Focus tab's available viewport height into its content as a minimum height. Music and task cards have a 288-point minimum and grow together into the remaining space above the footer on taller windows. On short windows the content keeps its natural minimum height and scrolls; compact layouts retain stacked cards. The music artwork fills its card without changing aspect ratio, while its controls stay at the bottom. Task lists scroll internally.
- Timer digits use stable widths and scale down to fit their column. Running/stopped/completed states have explicit text.
- Primary actions, timer settings/reset/break controls, and editable time cells have visible keyboard-focus rings; inputs expose labels and focus boundaries. Editors use native Save/Cancel shortcuts. Completion controls place the break button on a separate row when needed.
- The music panel uses native material with a warm translucent overlay, an explicit user-requested exception to flat styling. Reduce Transparency replaces it with opaque paper.

Offscreen native renders were inspected at 1000 × 872 and 900 × 772 content sizes, plus a full-height 700-point-wide layout. Live interaction, keyboard navigation, VoiceOver, and actual material compositing in an onscreen window remain unverified because computer-use permissions were unavailable.

The fixed panel was inspected in native offscreen renders at 1710 × 1080, 1000 × 872, and the 680 × 650 minimum content size. Pixel measurements confirmed equal 16-point margins and matching bounds for Focus and Timesheet, including empty and populated Timesheets. Its unsigned Debug build passed. Live tab switching and scrolling remain unverified.

## 7. Build configuration and capabilities

The checked-in project currently declares:

| Setting | Value |
| --- | --- |
| Application target / scheme | `keep` / `keep` |
| Platform / SDK root | macOS / `macosx` |
| Deployment target | macOS 26.5 |
| Swift language mode | `SWIFT_VERSION = 5.0` |
| Default actor isolation | `MainActor` |
| Approachable concurrency | Enabled |
| Build configurations | Debug and Release |
| App Sandbox | Enabled |
| User-selected file access | Read-only |
| Outgoing network connections | Enabled in Debug and Release for Audius API/audio hosts |
| Info.plist | Generated by Xcode |
| Third-party package products | None |

The language-mode setting does not identify the installed Swift compiler. Project metadata does not prove SDK availability or that a build succeeds on a given machine. Check the installed toolchain when compatibility matters.

There is no Xcode test target, configured lint/format tool, third-party persistence framework, backend, or third-party music SDK. AVFoundation handles audio and Foundation URLSession handles Audius HTTPS requests. Foundation UserDefaults provides local storage; timer/recording/music checks run through standalone Swift harnesses. Sandbox settings do not imply that a file-import feature exists; adding capabilities requires a concrete feature need.

## 8. Development and verification

Run commands from the repository root:

```sh
open keep.xcodeproj
xcodebuild -list -project keep.xcodeproj
xcodebuild -project keep.xcodeproj -scheme keep -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/keep-derived-data \
  CODE_SIGNING_ALLOWED=NO build
```

Run the deterministic timing checks:

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  keep/Features/FocusSession/Models/PomodoroSettings.swift \
  keep/Features/FocusSession/Models/FocusTimer.swift \
  tests/FocusTimerChecks.swift -o /tmp/keep-timer-checks
/tmp/keep-timer-checks
```

Run the recording, editing, and persistence checks:

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  keep/Models/FocusProject.swift keep/Models/WorkspaceModel.swift \
  keep/Features/FocusSession/Models/PomodoroSettings.swift \
  keep/Features/FocusSession/Models/FocusTimer.swift \
  keep/Features/Timesheet/Models/TimesheetLedger.swift \
  keep/Features/Timesheet/Models/TimesheetPersistence.swift \
  tests/WorkspaceChecks.swift -o /tmp/keep-workspace-checks
/tmp/keep-workspace-checks
```

Run the focused music checks:

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  keep/Features/Music/Models/*.swift keep/Features/Music/Services/*.swift \
  tests/MusicPlayerChecks.swift -o /tmp/keep-music-checks
/tmp/keep-music-checks
```

The music checks use injected catalog/playback fixtures and an isolated URLProtocol session; they do not play sound or request live Audius data. They cover loading versus actual playing, pause/resume, volume clamping, stalled playback, queue navigation/completion, cancellation, stale item callbacks, bounded unavailable-track fallback, retry, shutdown, safe URLs, access filtering, and HTTP error mapping. Live service verification is a separate opt-in developer check; silence AVPlayer by setting volume to zero when probing on a user's Mac.

Run the daily-task checks:

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  keep/Features/Tasks/Models/*.swift tests/DailyTaskChecks.swift \
  -o /tmp/keep-daily-task-checks
/tmp/keep-daily-task-checks
```

On 2026-10-05, the unsigned Debug build, 45 timing checks, and 180 workspace checks passed. Checks cover configurable durations, short/long break cycles, settings changes during focus/rest, recording overlap, Flow priority, manual break exclusion, paused/reset timers, project reassignment, active edits, weekly row removal/Undo during recording, preserved other weeks/projects, fractions, midnight/week rollover, DST, duration validation, project creation, all 30 color encodings, backward compatibility, corrupt-load protection, and persistence of time/catalog/settings across separate processes using isolated temporary preferences. The build emitted an App Intents metadata warning because no AppIntents dependency is present.

Native offscreen renders of running/completed/break Focus states, empty/live/populated Timesheets at default, wide, and narrow sizes, and the entry editor were inspected. Live popover interaction, keyboard navigation, VoiceOver, release signing, and audible sound remain unverified; computer-use permission was unavailable for live UI checks.

The project-creation dialog, all 30 color swatches, the updated picker, and a newly created Timesheet row were inspected in native offscreen renders. Live popover-to-sheet transitions and keyboard interaction remain unverified.

Default/custom Pomodoro settings, long-break completion/running states, wrapped controls on a narrow timer card, and the default Focus layout were inspected in native offscreen renders. Live popover interaction and keyboard navigation remain unverified.

Growing support cards and task delete controls were inspected at 1710 × 1080, 1920 × 1400, 1000 × 872, 700 × 1700, and 680 × 650 content sizes. Timesheet remove controls and Undo were inspected at wide/default/minimum sizes. Live click/keyboard interaction remains unverified.

Audius integration verification on 2026-10-05: unsigned Debug and local ad hoc signed Debug builds passed; generated entitlements retain App Sandbox and include `com.apple.security.network.client`. The 47 music checks and 180 workspace regression checks passed. Live API discovery returned 29 accessible tracks, and a separate sandboxed native harness reached AVPlayer Playing, paused, and resumed at volume zero. This validates actual streaming and native playback state without testing audible output. Idle/playing/loading/error cards and default/wide/narrow workspace layouts were inspected in native offscreen renders. Live music-button/slider interaction, keyboard/VoiceOver, and audible sound remain unverified.

Daily-task verification on 2026-10-05: unsigned Debug build and 56 daily-task checks passed, including independent dates, past/future jumps, Today/midnight behavior, 23/25-hour DST navigation, leap/invalid dates, pinned civil dates across timezone changes, stable UUIDs, per-day completion/deletion, corrupt-load protection/Retry, and separate-process persistence. The existing 180 workspace and 47 music checks also passed. Native offscreen today/past/tomorrow/future-empty/load-error cards, date picker, narrow card, and default/wide/minimum window layouts were inspected. Live date-popover/input/keyboard/VoiceOver interaction remains unverified.

Use previews or the running macOS app to verify appearance and interaction. Add focused tests when meaningful domain behavior is introduced, then document the actual test target and commands. Do not invent test or lint checks before they exist.

## 9. Maintaining this document

Update this document when new source understanding or implementation changes component responsibilities, view composition, state/data ownership, dependencies, build workflow, or important constraints. Replace stale descriptions, keep supporting paths accurate, and distinguish implemented behavior from proposals.

Put agent working rules in `AGENTS.md`, visual rules in `docs/style.md`, and the reason/history behind durable choices in `docs/decisions.md`. Avoid copying their detailed contents here. Product choices that remain unresolved belong in the ledger rather than being presented as settled architecture.
