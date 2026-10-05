# Keep — Decisions and Continuity

## [SNAPSHOT]

- 2026-10-05 [CODE] Goal: native macOS focus workspace; existing UI includes an active target, Pomodoro and flow panels, and task/music areas.
- 2026-10-05 [CODE] Current state: Focus records project time into an editable seven-day Timesheet with locally saved totals and weekly row removal/Undo. Flow takes recording priority; Pomodoro has saved duration/iteration settings and manual uncounted short/long breaks. Support cards fill taller windows; tasks have delete controls. Music remains a disabled playback preview.
- 2026-10-05 [USER] Documentation lives in `docs/architecture.md`, `docs/decisions.md`, and `docs/style.md`; root `AGENTS.md` defines working rules.
- 2026-10-05 [USER] Keep agent guidance and architecture clearer as understanding of the project improves.
- 2026-10-05 [CODE] Created projects, project/day totals, and edits persist in local preferences. A shared creation dialog offers a name and 30 colors. No external integrations, third-party packages, or Xcode test target; standalone timer/workspace checks are available.
- 2026-10-05 [USER] Visual direction: editorial restraint and a cozy palette informed by main-theme and vibe1; first visual implementation is in place.
- 2026-10-05 [CODE] Timers/project selection/ledger are app-shared; timer runtime and window-local task drafts are not restored on relaunch. Next feature is UNCONFIRMED.

## [DECISIONS]

### D001 ACTIVE — 2026-10-05 [USER]

Keep documentation in the existing lowercase `docs/` files and refine root `AGENTS.md` and `docs/architecture.md` as project understanding improves.

Ownership: agent rules in `AGENTS.md`, implemented structure and constraints in architecture, durable context here, and visual language in style. Avoid duplicate root-level or uppercase alternatives.

### D002 ACTIVE — 2026-10-05 [USER]

Provide two independently playable/stoppable timers: Pomodoro and flow. They may run concurrently; actions on one must not change the other.

### D003 PARTIALLY SUPERSEDED BY D008 — 2026-10-05 [CODE]

For the first draft, Stop preserves time, Continue resumes it, and Reset starts fresh. Pomodoro uses 25 minutes; flow has no time limit. Timing uses `ContinuousClock`, including sleep, with state local to each window. No persistence or automatic break cycles are introduced.

### D004 ACTIVE — 2026-10-05 [USER]

The music area previews later lofi/ambient playback with cozy artwork and controls floating on a blurry card. This panel is an exception to the flat visual language; actual audio remains out of scope.

### D005 ACTIVE — 2026-10-05 [CODE]

Use explicit light appearance for the first palette implementation. Keep Stats, Settings, and music playback controls disabled rather than implying unfinished functionality works.

### D006 SUPERSEDED BY D008 — 2026-10-05 [USER]

Build only the Timesheet tab for now using mock project data. Show seven days, hours, and totals; introduce no timesheet business logic or connection to timers. Calendar and list-view alternatives are outside this task.

### D007 ACTIVE — 2026-10-05 [USER]

Add a folder icon to the Working on card to select a project, with a separate editable task name. Adapt the reference picker to Keep’s warm palette.

2026-10-05 [CODE] Initial draft used four local sample projects, search, and No project without timer integration or persistence. D008 supersedes those implementation limits; the picker and separate task-name field remain. D010 enables creation, which was initially disabled.

### D008 PARTIALLY SUPERSEDED BY D011 — 2026-10-05 [USER]

Connect assigned projects to timer recording and editable Timesheet entries. Count Pomodoro focus only; count all running Flow time, with Flow overriding Pomodoro during overlap. Offer a manual 5-minute break after each focus interval. Save recorded time and manual edits locally across closing/reopening Keep. Remove the folder icon’s down arrow.

2026-10-05 [CODE] One app-owned workspace coordinates both timers, shared project selection, and the numeric ledger. Project changes settle past time before switching attribution. Choosing “No project” records into an unassigned row. Edits replace the settled project/day total, and later time adds to it. Timers remain independently controlled; resets keep recorded totals. Saved totals reopen in the current week, with timers idle; app-offline time is excluded. Local data uses `keep.timesheet.v1` in UserDefaults. No sample history is loaded into the live ledger.

### D009 ACTIVE — 2026-10-05 [USER]

Keep equal padding between the panel and the window on all four sides. Switching navigation tabs must not change the panel size.

2026-10-05 [CODE] The panel fills the usable content area with 16-point margins. Navigation stays outside separate mounted tab ScrollViews; content height no longer controls the shell's size.

### D010 ACTIVE — 2026-10-05 [USER]

Create a new project opens a dialog for a project name and a choice of 30 colors.

2026-10-05 [CODE] Both Focus and Timesheet use the same dialog and shared saved catalog. Focus selects the created project; Timesheet adds it to the displayed week without reassigning running timers. Names are trimmed, limited to 80 characters, and must be distinct ignoring case/diacritics. Creation assigns a UUID and saves the name/color before any recorded time. Old saved totals remain readable. Cancel discards the draft.

### D011 ACTIVE — 2026-10-05 [USER]

Make the Pomodoro icon clickable and open a popover to choose focus duration, short-break duration, long-break duration, and the number of iterations before a long break.

2026-10-05 [CODE] Defaults are 25/5/15 minutes and four completed focus intervals. Save validates and persists settings locally; current running/paused intervals keep their original duration, and future intervals use the saved settings. Idle countdowns update immediately. Breaks remain manually started, as previously requested. Focus completion advances the cycle once; short breaks retain progress, a started long break or Reset clears it, and skipped long breaks remain due. Cycle runtime resets on relaunch. Both break types remain excluded from Pomodoro recording; Flow priority is preserved.

### D012 ACTIVE — 2026-10-05 [USER]

Extend the music and tasks cards to the bottom on larger/full-screen windows. Make tasks deletable and add an × to remove Timesheet rows, matching the reference.

2026-10-05 [CODE] Support cards grow from a 288-point minimum to fill the space above the footer, with scrolling for short windows. Task × buttons remove window-local drafts. Timesheet × buttons remove the project's entries in the displayed week after settling recording, save immediately, and offer one-step Undo. Catalog projects and other weeks remain intact. Timers continue recording subsequent time; Undo adds removed history back alongside that new time. Undo history lasts for the current app run.

## [PROGRESS]

- 2026-10-05 [CODE] Established architecture documentation from all current Swift views, asset definitions, and the Xcode project. Documented actual composition and separated placeholders from functional behavior.

- 2026-10-05 [CODE] Added semantic color assets, generated/bundled music artwork, adaptive card composition, independent timer state, and window-local task add/completion behavior.

- 2026-10-05 [CODE] Added selectable Timesheet UI with four static sample projects, seven weekday/date columns, project/day/week totals, and a horizontally scrollable table. Editing and week controls are disabled.

- 2026-10-05 [CODE] Added a native project popover with search, selected-row checks, hover/focus feedback, and a separate task-name field. Selection and task text remain owned by FocusSessionView.

- 2026-10-05 [CODE] Added app-shared recording with Flow priority, focus/rest intervals, computed totals, editable cells, current/historical weeks, local saving, and a termination flush. Moved project metadata and picker presentation into shared boundaries.

## [DISCOVERIES]

- 2026-10-05 [CODE] Initial draft kept timers/tasks in each Focus view. D008 introduces one app-owned WorkspaceModel for timers, selection, and recording; task drafts remain window-local.
- 2026-10-05 [CODE] `PrimaryButton` and `NavBar` receive caller-owned actions. `AppShellView` owns Focus/Timesheet selection and preserves mounted focus state across tab changes.
- 2026-10-05 [CODE] Timer and supporting-card pairs stack below 820 points; tab content and task lists scroll within the fixed panel. Timer cards share presentation without sharing timing state.

## [OUTCOMES]

- 2026-10-05 [CODE] First visual draft is implemented. Unsigned build and timing checks pass; offscreen layout renders inspected. Live UI verification is unavailable without computer-use permission.

- 2026-10-05 [CODE] Timesheet UI is complete for the requested mock-data scope; week editing/navigation and timer integration remain intentionally unimplemented.

- 2026-10-05 [CODE] Working on picker and task-name UI are implemented with local sample data. Offscreen normal/search/empty/unassigned and narrow layouts inspected; live interaction remains unverified.

- 2026-10-05 [CODE] Timer recording and Timesheet editing/persistence implemented. Build, 24 timer checks, and 84 workspace checks passed, including cross-process persistence. Offscreen running/completed/break, empty/live Timesheet, and editor layouts inspected.

## [OPEN QUESTIONS]

These questions are not blockers for unrelated work; resolve them when the relevant feature is requested.

- 2026-10-05 [CODE] UNCONFIRMED: detailed session history, restoring timer runtime, automatic interval starts, and future notifications. Current focus/break/sleep/relaunch behavior is documented in D008, D011, and architecture.
- 2026-10-05 [CODE] UNCONFIRMED: project renaming/deletion, task-level time records, and future storage migration. Project switches currently apply prospectively, and selection preserves task text.
- 2026-10-05 [CODE] UNCONFIRMED: music source/provider, statistics scope, and a future dark palette.

## [WORKING SET]

- 2026-10-05 [CODE] `AGENTS.md`
- 2026-10-05 [CODE] `docs/architecture.md`
- 2026-10-05 [CODE] `docs/decisions.md`
- 2026-10-05 [CODE] `docs/style.md`
- 2026-10-05 [CODE] `keep/App/`
- 2026-10-05 [CODE] `keep/Models/`
- 2026-10-05 [CODE] `keep/Features/FocusSession/`
- 2026-10-05 [CODE] `keep/Features/Timesheet/`
- 2026-10-05 [CODE] `tests/`
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

- 2026-10-05 [TOOL] Recording integration unsigned Debug build passed; 24 timer and 84 workspace checks passed. Separate subprocesses verified persisted data using a temporary preferences domain. Default/wide/narrow native offscreen Timesheet renders, timer focus/completion/break states, and the edit popover inspected; live UI interaction remains unverified.

- 2026-10-05 [TOOL] Fixed-panel unsigned Debug build passed. Offscreen Focus and empty/populated Timesheet renders inspected at wide, default, and minimum content sizes; pixel measurements confirmed 16-point margins on all sides and identical panel bounds across tabs. Live tab switching and scrolling remain unverified.

- 2026-10-05 [TOOL] Project creation unsigned Debug build and 135 workspace checks passed, including catalog persistence without time, backward-compatible loads, validation, all 30 color encodings, and separate-process reloads. Native offscreen dialog/picker/created Timesheet renders inspected; live sheet transitions remain unverified.

- 2026-10-05 [TOOL] Pomodoro settings unsigned Debug build, 45 timer checks, and 157 workspace checks passed. Configurable short/long break cycles, retained active durations, focus-only recording, saved settings, legacy records, and separate-process reloads verified. Offscreen settings and long-break layouts inspected, including narrow controls; live popover interaction remains unverified.

- 2026-10-05 [TOOL] Extended-card/delete-controls unsigned Debug build and 180 workspace checks passed. Weekly deletion scope, running Flow/focus settlement, break exclusion, Undo merges, zero-time rows, and persistence verified. Native offscreen large/wide/default/minimum/tall-compact layouts and Timesheet removal/Undo inspected; live interaction remains unverified.
