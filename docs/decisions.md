# Keep — Decisions and Continuity

## [SNAPSHOT]

- 2026-10-05 [CODE] Goal: native macOS focus workspace; existing UI includes an active target, Pomodoro and flow panels, and task/music areas.
- 2026-10-05 [CODE] Current state: cozy Focus draft plus a selectable, UI-only Timesheet tab with a seven-day mock project grid. Focus timers/tasks and project selection/task-name input work locally; music remains a disabled playback preview.
- 2026-10-05 [USER] Documentation lives in `docs/architecture.md`, `docs/decisions.md`, and `docs/style.md`; root `AGENTS.md` defines working rules.
- 2026-10-05 [USER] Keep agent guidance and architecture clearer as understanding of the project improves.
- 2026-10-05 [CODE] No persistence, external integrations, third-party packages, or Xcode test target. A standalone timer-check harness is available.
- 2026-10-05 [USER] Visual direction: editorial restraint and a cozy palette informed by main-theme and vibe1; first visual implementation is in place.
- 2026-10-05 [CODE] State is window-local and resets when the window closes. Next feature is UNCONFIRMED.

## [DECISIONS]

### D001 ACTIVE — 2026-10-05 [USER]

Keep documentation in the existing lowercase `docs/` files and refine root `AGENTS.md` and `docs/architecture.md` as project understanding improves.

Ownership: agent rules in `AGENTS.md`, implemented structure and constraints in architecture, durable context here, and visual language in style. Avoid duplicate root-level or uppercase alternatives.

### D002 ACTIVE — 2026-10-05 [USER]

Provide two independently playable/stoppable timers: Pomodoro and flow. They may run concurrently; actions on one must not change the other.

### D003 ACTIVE — 2026-10-05 [CODE]

For the first draft, Stop preserves time, Continue resumes it, and Reset starts fresh. Pomodoro uses 25 minutes; flow has no time limit. Timing uses `ContinuousClock`, including sleep, with state local to each window. No persistence or automatic break cycles are introduced.

### D004 ACTIVE — 2026-10-05 [USER]

The music area previews later lofi/ambient playback with cozy artwork and controls floating on a blurry card. This panel is an exception to the flat visual language; actual audio remains out of scope.

### D005 ACTIVE — 2026-10-05 [CODE]

Use explicit light appearance for the first palette implementation. Keep Stats, Settings, and music playback controls disabled rather than implying unfinished functionality works.

### D006 ACTIVE — 2026-10-05 [USER]

Build only the Timesheet tab for now using mock project data. Show seven days, hours, and totals; introduce no timesheet business logic or connection to timers. Calendar and list-view alternatives are outside this task.

### D007 ACTIVE — 2026-10-05 [USER]

Add a folder icon to the Working on card to select a project, with a separate editable task name. Adapt the reference picker to Keep’s warm palette.

2026-10-05 [CODE] The picker uses four local sample projects, search, and No project. Selecting a project preserves the task text; neither field is connected to timer recording or Timesheet. Project creation is a disabled preview, and no persistence is added.

## [PROGRESS]

- 2026-10-05 [CODE] Established architecture documentation from all current Swift views, asset definitions, and the Xcode project. Documented actual composition and separated placeholders from functional behavior.

- 2026-10-05 [CODE] Added semantic color assets, generated/bundled music artwork, adaptive card composition, independent timer state, and window-local task add/completion behavior.

- 2026-10-05 [CODE] Added selectable Timesheet UI with four static sample projects, seven weekday/date columns, project/day/week totals, and a horizontally scrollable table. Editing and week controls are disabled.

- 2026-10-05 [CODE] Added a native project popover with search, selected-row checks, hover/focus feedback, and a separate task-name field. Selection and task text remain owned by FocusSessionView.

## [DISCOVERIES]

- 2026-10-05 [CODE] Each `WindowGroup` root now owns independent session/task state through `FocusSessionView`; no shared app store is needed for this draft.
- 2026-10-05 [CODE] `PrimaryButton` and `NavBar` receive caller-owned actions. `AppShellView` owns Focus/Timesheet selection and preserves mounted focus state across tab changes.
- 2026-10-05 [CODE] Timer and supporting-card pairs stack below 820 points; outer shell and task list scroll. Timer cards share presentation without sharing timing state.

## [OUTCOMES]

- 2026-10-05 [CODE] First visual draft is implemented. Unsigned build and timing checks pass; offscreen layout renders inspected. Live UI verification is unavailable without computer-use permission.

- 2026-10-05 [CODE] Timesheet UI is complete for the requested mock-data scope; week editing/navigation and timer integration remain intentionally unimplemented.

- 2026-10-05 [CODE] Working on picker and task-name UI are implemented with local sample data. Offscreen normal/search/empty/unassigned and narrow layouts inspected; live interaction remains unverified.

## [OPEN QUESTIONS]

These questions are not blockers for unrelated work; resolve them when the relevant feature is requested.

- 2026-10-05 [CODE] UNCONFIRMED: durable history/relaunch recovery, automatic break cycles, and future notifications. Draft sleep/window/stop behavior is documented in D003.
- 2026-10-05 [CODE] UNCONFIRMED: durable task/project relationship, recording target switches during a session, and storage requirements. Current UI selection preserves task text and does not alter timing.
- 2026-10-05 [CODE] UNCONFIRMED: music source/provider, statistics scope, and a future dark palette.

## [WORKING SET]

- 2026-10-05 [CODE] `AGENTS.md`
- 2026-10-05 [CODE] `docs/architecture.md`
- 2026-10-05 [CODE] `docs/decisions.md`
- 2026-10-05 [CODE] `docs/style.md`
- 2026-10-05 [CODE] `keep/App/`
- 2026-10-05 [CODE] `keep/Features/FocusSession/`
- 2026-10-05 [CODE] `keep/Features/Timesheet/`
- 2026-10-05 [CODE] `tests/FocusTimerChecks.swift`
- 2026-10-05 [CODE] `keep/Assets.xcassets/`
- 2026-10-05 [CODE] `keep/DesignSystem/`
- 2026-10-05 [CODE] `keep.xcodeproj/project.pbxproj`

## [RECEIPTS]

- 2026-10-05 [TOOL] `xcodebuild -list -project keep.xcodeproj` succeeded: application target and scheme `keep`; Debug and Release configurations. This is project discovery, not a compilation check.
- 2026-10-05 [TOOL] Unsigned Debug `xcodebuild` succeeded; App Intents metadata extraction warning only.
- 2026-10-05 [TOOL] Standalone Swift harness passed 24 timing checks for independent actions, pause/resume, reset, completion, and formatting.
- 2026-10-05 [TOOL] Inspected offscreen AppKit/SwiftUI renders at default and narrow sizes. Computer-use permissions were not granted; live interaction remains unverified.
- 2026-10-05 [TOOL] Timesheet unsigned Debug build passed. Inspected offscreen layouts at default, wide, and narrow sizes; static totals reconcile to 26h 30m. Live interaction remains unverified.

- 2026-10-05 [TOOL] Project picker unsigned Debug build passed; native offscreen default/narrow, case-insensitive trimmed search, no-match, and No project/empty-task states inspected. Live popover and keyboard interaction remain unverified.
