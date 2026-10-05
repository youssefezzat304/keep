# Keep — Architecture

Keep is a native macOS focus workspace built with SwiftUI. This document describes the verified implementation and the boundaries to preserve as behavior is added. It is not a roadmap or a claim that the displayed features are functional.

## 1. Current implementation

The application is a first visual draft with one application target. Timers record project time into an editable, locally saved Timesheet. Timer and project state are shared across the app’s windows; task-list and task-name drafts remain window-local. Music is a visual preview; audio and external integrations are not implemented.

| Area | Implemented today | Not implemented |
| --- | --- | --- |
| App window | `WindowGroup`; 1000 × 900 default size; 680 × 650 minimum content frame; fixed panel with scrollable tabs; one shared workspace model | Restoring timer runtime or task drafts across launches |
| Navigation | Selectable Focus and Timesheet tabs; shell-owned selection; disabled Stats and Settings controls | Stats/Settings destinations |
| Timesheet | Live project/day seconds, computed totals, seven-day grid, week navigation, manual edits, Add project, and local saving | Detailed session log, calendar/list alternatives, sync |
| Active target | Searchable shared project catalog; creation dialog with name and 30 colors; local saving; selection drives recording; separate editable task name | Project renaming/deletion and task-level time records |
| Pomodoro | Settings popover for focus/short/long breaks and iterations; saved preferences; manual short/long breaks; independent controls; focus-only recording | Automatic interval starts, notifications |
| Flow timer | Elapsed time, independent controls, and recording priority over Pomodoro | Detailed session history or a completion limit |
| Music | Bundled cozy illustration with a frosted controls panel; controls disabled and marked coming soon | Playback, music sources, provider integration |
| Tasks | Lined list with example tasks, completion toggles, trimmed nonempty input, and internal scrolling | Persistence, deletion, reordering, project association |
| Design system | Semantic color assets, `KeepTheme`, reusable action button, flexible card modifier | Dark theme |

Both timers may run at the same time, with independent controls. Flow overrides Pomodoro for recording; overlapping time is counted once. Project/day totals and manual edits survive relaunch; timers restart idle. Example tasks and task names remain editable drafts that are not saved.

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
    KeepApp.swift                  @main entry point, shared workspace, WindowGroup
    WorkspaceApplicationDelegate.swift  Final recording flush on app termination
    AppShellView.swift             Navigation and focus-workspace composition
  DesignSystem/
    KeepTheme.swift                Semantic references to named color assets
    FocusProjectStyle.swift        Shared project-to-theme presentation mapping
    Components/
      NavBar.swift                 Shared navigation presentation
      PrimaryButton.swift          Shared action button with caller-supplied closure
      ProjectPicker.swift          Searchable project selection shared by Focus/Timesheet
      ProjectCreationDialog.swift  Shared name/color sheet with caller-owned creation action
    Modifiers/
      CardStyle.swift              Shared card treatment and View.cardStyle extension
  Models/
    WorkspaceModel.swift           Shared timers, project selection, recorder, save coordination
    FocusProject.swift             Shared project catalog and Codable metadata
  Features/
    FocusSession/
      Models/                      FocusTimer timing/cycles, PomodoroSettings, and FocusTask data
      Views/                       Focus workspace, timer/settings popover, and supporting panels
    Timesheet/
      Models/                      TimesheetLedger, calendar/duration helpers, local persistence
      PreviewData/                 Numeric fixtures used only by previews
      Views/                       Weekly timesheet page and seven-day table
  Assets.xcassets/                  Named colors, CozyCorner artwork, and AppIcon
tests/FocusTimerChecks.swift        Standalone deterministic timing checks
tests/WorkspaceChecks.swift         Recording, editing, calendar, and persistence checks
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

`TimerWorkspaceCard` selects a horizontal or vertical arrangement of the two panels. Each panel passes a timer snapshot and caller-owned actions to `FocusTimerCard`. All actions go through `WorkspaceModel`. `FocusSessionView` owns only the task-name draft and task collection; it reads the shared project selection and timers.

`AppShellView` owns `WorkspaceTab` selection and supplies Focus/Timesheet action closures to `NavBar`. Navigation stays outside the scrolling content. Each tab has a separate, mounted ScrollView in the same fixed viewport; the inactive tab is invisible and hidden from hit testing and accessibility. This preserves drafts and each tab's scroll position without changing the panel size. Shared `PrimaryButton` receives its action from the caller.

## 4. Responsibility and dependency boundaries

| Location | Owns | Keep outside it |
| --- | --- | --- |
| `App` | Launch, shared model assembly, window composition, tab selection, and termination flush | Feature timing calculations and provider-specific logic |
| `Features/FocusSession` | Focus UI and session-specific state, actions, and rules | Generic styles and unrelated feature behavior |
| `Models` | Shared project metadata and coordination of timer recording with the ledger | View layout and provider integrations |
| `Features/Timesheet` | Numeric ledger, calendar/duration helpers, local saving, editable UI, and preview fixtures | Independent timer mutation and overlapping recorders |
| `DesignSystem` | Reusable presentation, control styles, layout conventions, and theme tokens | Session state, persistence, provider calls, and feature actions |
| `Assets.xcassets` | Named colors and bundled visual resources | Domain behavior and credentials |

The current composition is `App` → feature views and design-system views; feature views reuse the design system. Future business logic should remain independent of the visual components that display it. A shared button should receive an action from its caller.

There is no established MVVM layer, repository abstraction, service container, or package decomposition. Add a model or service only when implemented behavior needs it. Place feature-owned additions with the feature; introduce a shared boundary only when there is a concrete cross-feature need.

## 5. State and data ownership

`KeepApp` creates one `@State` reference to the observable, main-actor `WorkspaceModel` and passes it into every window. It owns two `FocusTimer` values, the selected project, the numeric ledger, and one update task. Shells own tab selection; Focus views own task-name and task-list drafts. Previews construct models without persistence and cannot write live history.

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

`TimesheetPersistence` JSON-encodes the ledger, custom catalog, and optional `PomodoroSettings` into the app’s standard `UserDefaults` under `keep.timesheet.v1`. Older records without the added fields load with an empty custom catalog and default timer settings, retaining their entries. It loads on app model creation, saves about every five seconds during recording, and saves immediately after actions/edits/creation/settings changes. `WorkspaceApplicationDelegate` flushes the last partial interval on normal app termination, including when no windows remain. Abrupt termination can lose time since the last checkpoint save. Corrupt saved data, including invalid settings, blocks mutations and shows Retry rather than overwriting unreadable records. Timer runtime, task drafts, and selection are not persisted.

`ActiveTargetHeader` and `TimesheetView` own picker and creation-sheet presentation. `ProjectPicker` owns transient search/hover/focus state and searches the shared catalog by name. Its Create action closes the popover and opens `ProjectCreationDialog`, which owns only draft name/color/error state. The dialog offers 30 named color swatches, a selection checkmark, keyboard focus, and native Create/Cancel shortcuts. Cancel discards drafts. `WorkspaceModel.createProject` trims names, requires 1–80 characters, rejects case/diacritic-insensitive duplicate names and invalid colors, assigns a UUID, and saves the catalog without inventing time entries. Focus selects the created project and returns focus to the task field; Timesheet adds it to the displayed week without changing the active timer project. `DesignSystem/FocusProjectStyle.swift` maps Codable project accents to named color assets; the neutral accent is reserved for unassigned time. `TimesheetPreviewData` supplies numeric sample data exclusively for previews.

`TasksCard` owns draft input/focus only; its list remains in the Focus view. `MusicPlayerCard` has no playback state. There are no external providers, notification permissions, databases, or credentials.

Project management, task-level session history, music sources, and notifications remain scoped future work. See `docs/decisions.md`.

## 6. Visual implementation and layout constraints

`docs/style.md` owns the cozy editorial palette. Named color assets are the source of truth; `KeepTheme` provides shared semantic references. The first draft explicitly uses light appearance to keep fixed warm surfaces and foregrounds consistent.

The shell places a cream workspace over peach surroundings. Pomodoro focus uses terracotta, its break uses butter yellow, and flow uses sage. Tasks use an ivory ruled-list treatment. The music artwork is a bundled asset in `keep/Assets.xcassets/CozyCorner.imageset/`; its generation prompt and provenance are in `docs/music-artwork.md`.

Layout and accessibility behavior:

- Default window size is 1000 × 900; the root view has a 680 × 650 minimum frame.
- The panel fills the usable window content area with equal 16-point margins on all four sides and 24-point inner padding. Its size depends on the window, not the selected tab or content height. Navigation stays at the top; longer tab content scrolls inside the panel. There is no fixed maximum panel width.
- Below 820 points of window width, timer and supporting card pairs stack vertically.
- The Timesheet table keeps a minimum width of 850 points and scrolls horizontally on narrow windows, preserving readable seven-day columns and totals. Its heading and week toolbar can stack using `ViewThatFits`.
- The target header uses `ViewThatFits` to move its project/task card below the heading when needed. Its native popover is 340 points wide with a scrollable project list; the folder button and project rows show hover and keyboard-focus feedback.
- `CardStyle` supplies padding, flexible width, and rounding without imposing fixed maximum heights.
- Supporting cards are 288 points high. The task list scrolls within its card as content grows.
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
| Info.plist | Generated by Xcode |
| Third-party package products | None |

The language-mode setting does not identify the installed Swift compiler. Project metadata does not prove SDK availability or that a build succeeds on a given machine. Check the installed toolchain when compatibility matters.

There is no Xcode test target, configured lint/format tool, third-party persistence framework, backend, or network/music integration. Foundation UserDefaults provides local storage; timer/recording checks run through standalone Swift harnesses. Sandbox settings do not imply that a file-import feature exists; adding capabilities requires a concrete feature need.

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

On 2026-10-05, the unsigned Debug build, 45 timing checks, and 157 workspace checks passed. Checks cover configurable durations, short/long break cycles, settings changes during focus/rest, recording overlap, Flow priority, manual break exclusion, paused/reset timers, project reassignment, active edits, fractions, midnight/week rollover, DST, duration validation, project creation, all 30 color encodings, backward compatibility, corrupt-load protection, and persistence of time/catalog/settings across separate processes using isolated temporary preferences. The build emitted an App Intents metadata warning because no AppIntents dependency is present.

Native offscreen renders of running/completed/break Focus states, empty/live/populated Timesheets at default, wide, and narrow sizes, and the entry editor were inspected. Live popover interaction, keyboard navigation, VoiceOver, release signing, and actual audio remain unverified; computer-use permission was unavailable for live UI checks.

The project-creation dialog, all 30 color swatches, the updated picker, and a newly created Timesheet row were inspected in native offscreen renders. Live popover-to-sheet transitions and keyboard interaction remain unverified.

Default/custom Pomodoro settings, long-break completion/running states, wrapped controls on a narrow timer card, and the default Focus layout were inspected in native offscreen renders. Live popover interaction and keyboard navigation remain unverified.

Use previews or the running macOS app to verify appearance and interaction. Add focused tests when meaningful domain behavior is introduced, then document the actual test target and commands. Do not invent test or lint checks before they exist.

## 9. Maintaining this document

Update this document when new source understanding or implementation changes component responsibilities, view composition, state/data ownership, dependencies, build workflow, or important constraints. Replace stale descriptions, keep supporting paths accurate, and distinguish implemented behavior from proposals.

Put agent working rules in `AGENTS.md`, visual rules in `docs/style.md`, and the reason/history behind durable choices in `docs/decisions.md`. Avoid copying their detailed contents here. Product choices that remain unresolved belong in the ledger rather than being presented as settled architecture.
