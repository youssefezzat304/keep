# Keep — Architecture

Keep is a native macOS focus workspace built with SwiftUI. This document describes the verified implementation and the boundaries to preserve as behavior is added. It is not a roadmap or a claim that the displayed features are functional.

## 1. Current implementation

The application is a first visual draft with one application target. Timers and tasks now have working, window-local state. Music is a visual preview; audio, persistence, and external integrations are not implemented.

| Area | Implemented today | Not implemented |
| --- | --- | --- |
| App window | `WindowGroup`; 1000 × 900 default size; 680 × 650 minimum content frame; scrolling shell | State shared across windows or launches |
| Navigation | Selectable Focus and Timesheet tabs; shell-owned selection; disabled Stats and Settings controls | Stats/Settings destinations |
| Timesheet | Read-only seven-day project grid with a static sample week, daily/project/weekly totals, and horizontal scrolling | Timer integration, history, editing, week navigation, and persistence |
| Active target | Folder button opens a searchable sample-project picker; selected project and editable task name owned by the focus view | Project creation, task/project storage, and session association |
| Pomodoro | 25-minute countdown with Play, Stop/Continue, Reset, and a completion state | Break cycles, notifications, history, adjustable durations in the UI |
| Flow timer | Elapsed time with its own Play, Stop/Continue, and Reset | Session history or a completion limit |
| Music | Bundled cozy illustration with a frosted controls panel; controls disabled and marked coming soon | Playback, music sources, provider integration |
| Tasks | Lined list with example tasks, completion toggles, trimmed nonempty input, and internal scrolling | Persistence, deletion, reordering, project association |
| Design system | Semantic color assets, `KeepTheme`, reusable action button, flexible card modifier | Dark theme |

Both timers may run at the same time. Their actions and resets are independent. Example tasks, the task name, and the selected sample project are editable within the current window; they are not saved.

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
    KeepApp.swift                  @main entry point, WindowGroup, default window size
    AppShellView.swift             Navigation and focus-workspace composition
  DesignSystem/
    KeepTheme.swift                Semantic references to named color assets
    Components/
      NavBar.swift                 Shared navigation presentation
      PrimaryButton.swift          Shared action button with caller-supplied closure
    Modifiers/
      CardStyle.swift              Shared card treatment and View.cardStyle extension
  Features/
    FocusSession/
      Models/                      FocusTimer timing state, FocusTask, and sample FocusProject data
      Views/                       Focus workspace, timer card, and supporting panels
    Timesheet/
      PreviewData/                 Static display fixtures, including all totals
      Views/                       Weekly timesheet page and seven-day table
  Assets.xcassets/                  Named colors, CozyCorner artwork, and AppIcon
tests/FocusTimerChecks.swift        Standalone deterministic timing checks
reference/                         Local, Git-ignored visual references
```

All Swift sources belong to the same application module. Directory boundaries express responsibility, not separate packages or targets. The `keep` source directory is a filesystem-synchronized Xcode group; documentation and reference images sit outside it.

## 3. View composition

```text
keepApp
└── WindowGroup
    └── AppShellView
        ├── NavBar
        │   └── Focus and Timesheet actions; disabled Stats and Settings
        ├── TimesheetView
        │   └── TimesheetTable → TimesheetMockData
        └── FocusSessionView
            ├── ActiveTargetHeader
            │   └── FocusProjectPicker → FocusProject.examples
            ├── TimerWorkspaceCard
            │   ├── PomodoroTimerPanel → FocusTimerCard
            │   └── FlowTimerPanel → FocusTimerCard
            └── Supporting cards (HStack or VStack)
                ├── MusicPlayerCard
                └── TasksCard
```

`TimerWorkspaceCard` selects a horizontal or vertical arrangement of the two panels. Each panel binds its own timer to the shared `FocusTimerCard` presentation. `FocusSessionView` owns the two timers, task name, selected project, and task collection.

`AppShellView` owns `WorkspaceTab` selection and supplies Focus/Timesheet action closures to `NavBar`. Both root views remain mounted; inactive content has zero height and is hidden from hit testing and accessibility. This preserves focus state when switching tabs. Shared `PrimaryButton` receives its action from the caller.

## 4. Responsibility and dependency boundaries

| Location | Owns | Keep outside it |
| --- | --- | --- |
| `App` | Launch, window composition, tab selection, and future dependency assembly | Feature timing calculations and provider-specific logic |
| `Features/FocusSession` | Focus UI and session-specific state, actions, and rules | Generic styles and unrelated feature behavior |
| `Features/Timesheet` | Timesheet presentation and explicitly static preview fixtures | Focus timer state and session recording |
| `DesignSystem` | Reusable presentation, control styles, layout conventions, and theme tokens | Session state, persistence, provider calls, and feature actions |
| `Assets.xcassets` | Named colors and bundled visual resources | Domain behavior and credentials |

The current composition is `App` → feature views and design-system views; feature views reuse the design system. Future business logic should remain independent of the visual components that display it. A shared button should receive an action from its caller.

There is no established MVVM layer, repository abstraction, service container, or package decomposition. Add a model or service only when implemented behavior needs it. Place feature-owned additions with the feature; introduce a shared boundary only when there is a concrete cross-feature need.

## 5. State and data ownership

`FocusSessionView` owns two `FocusTimer` values, a task-name string, an optional selected `FocusProject`, and an array of `FocusTask` values using `@State`. Child views receive bindings. Every window has its own state, and closing the window discards that state. Nothing is saved between launches.

`FocusTimer` is a value type using `ContinuousClock.Instant` and accumulated elapsed seconds. `play` and `stop` accept optional clock instants; elapsed calculations, phase, and display formatting use those recorded instants. Reset clears timing state. Deterministic checks advance supplied instants without sleeping.

Implemented semantics:

- Pomodoro counts down from 25 minutes; flow counts up from zero.
- Play starts an idle timer; Continue resumes a stopped timer. Repeated Play while running does not restart it.
- Stop freezes the current time. Reset returns that timer to its initial value.
- Pomodoro clamps its display at zero and enters completed state. Playing a completed interval begins a new one.
- `ContinuousClock` includes time during system sleep and does not depend on wall-clock adjustments. Relaunch recovery is not implemented.
- A `TimelineView` refreshes the display approximately once per second while running. The refresh schedule is not timing truth. The view freezes completed Pomodoro timing through the model's Stop action.
- Each timer can run, stop, or reset without mutating the other timer.

`ActiveTargetHeader` owns picker presentation and field focus. `FocusProjectPicker` owns its transient search, hover, and focus state. The picker filters four in-memory sample projects by name, ignoring case and surrounding whitespace. Selecting a project (or No project) updates the parent binding, closes the popover, and focuses the task-name field. Switching projects preserves the typed task name; neither choice nor text edits mutate timers, the task list, or Timesheet. The Create a new project control is disabled. These sample projects are independent of Timesheet fixtures; no shared catalog or durable project/task relationship exists.

`TasksCard` owns only its draft input/focus state; task data remains in the parent. `MusicPlayerCard` owns no playback state. There are no ticking background services, observable global stores, notification requests, databases, or provider credentials.

Timesheet has no business state or history model. `TimesheetMockData` contains preformatted strings for one illustrative week (28 September–4 October 2026), four projects, and all totals. It does not calculate hours, access either timer, or record sessions. Cells are read-only text; week arrows, Add project, and Copy last week are disabled visual controls. Calendar and list-view alternatives are not implemented.

Durable task/project relationships, recording target changes during a session, session history, and music sources remain open product questions. See `docs/decisions.md`.

## 6. Visual implementation and layout constraints

`docs/style.md` owns the cozy editorial palette. Named color assets are the source of truth; `KeepTheme` provides shared semantic references. The first draft explicitly uses light appearance to keep fixed warm surfaces and foregrounds consistent.

The shell places a cream workspace over peach surroundings. Pomodoro uses terracotta; flow uses sage. Tasks use an ivory ruled-list treatment. The music artwork is a bundled asset in `keep/Assets.xcassets/CozyCorner.imageset/`; its generation prompt and provenance are in `docs/music-artwork.md`.

Layout and accessibility behavior:

- Default window size is 1000 × 900; the root view has a 680 × 650 minimum frame.
- The outer shell scrolls, centers the workspace, and caps it at 1100 points wide.
- Below 820 points of window width, timer and supporting card pairs stack vertically.
- The Timesheet table keeps a minimum width of 850 points and scrolls horizontally on narrow windows, preserving readable seven-day columns and totals. Its heading and week toolbar can stack using `ViewThatFits`.
- The target header uses `ViewThatFits` to move its project/task card below the heading when needed. Its native popover is 340 points wide with a scrollable project list; the folder button and project rows show hover and keyboard-focus feedback.
- `CardStyle` supplies padding, flexible width, and rounding without imposing fixed maximum heights.
- Supporting cards are 288 points high. The task list scrolls within its card as content grows.
- Timer digits use stable widths and scale down to fit their column. Running/stopped/completed states have explicit text.
- Primary actions and timer reset controls have custom keyboard-focus rings; inputs expose labels and focus boundaries.
- The music panel uses native material with a warm translucent overlay, an explicit user-requested exception to flat styling. Reduce Transparency replaces it with opaque paper.

Offscreen native renders were inspected at 1000 × 872 and 900 × 772 content sizes, plus a full-height 700-point-wide layout. Live interaction, keyboard navigation, VoiceOver, and actual material compositing in an onscreen window remain unverified because computer-use permissions were unavailable.

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

There is no Xcode test target, configured lint/format tool, persistence framework, backend, or network/music integration. Timing checks run through a standalone Swift harness. Sandbox settings do not imply that a file-import feature exists; adding capabilities requires a concrete feature need.

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
  keep/Features/FocusSession/Models/FocusTimer.swift \
  tests/FocusTimerChecks.swift -o /tmp/keep-timer-checks
/tmp/keep-timer-checks
```

On 2026-10-05, the unsigned Debug build and 24 deterministic timing checks passed. The build emitted an App Intents metadata warning because no AppIntents dependency is present. These results do not validate release signing, real audio, or live UI interaction.

The Timesheet draft also passed an unsigned Debug build and static mock-total consistency checks; offscreen default, wide, and narrow layouts were inspected. No new business-logic tests were added for this display-only feature.

The project picker also passed an unsigned Debug build. Offscreen default/narrow layouts and populated, filtered, empty-search, and unassigned states were inspected. Live popover interaction and keyboard navigation remain unverified.

Use previews or the running macOS app to verify appearance and interaction. Add focused tests when meaningful domain behavior is introduced, then document the actual test target and commands. Do not invent test or lint checks before they exist.

## 9. Maintaining this document

Update this document when new source understanding or implementation changes component responsibilities, view composition, state/data ownership, dependencies, build workflow, or important constraints. Replace stale descriptions, keep supporting paths accurate, and distinguish implemented behavior from proposals.

Put agent working rules in `AGENTS.md`, visual rules in `docs/style.md`, and the reason/history behind durable choices in `docs/decisions.md`. Avoid copying their detailed contents here. Product choices that remain unresolved belong in the ledger rather than being presented as settled architecture.
