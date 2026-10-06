# Keep — Architecture

Keep is a native macOS focus workspace built with SwiftUI. This document describes the verified implementation and the boundaries to preserve as behavior is added. It is not a roadmap or a claim that the displayed features are functional.

## 1. Current implementation

The application has one native application target, with implemented timers, local records, daily tasks, habits, and music; the separate Stats destination remains disabled. Timers record project time into an editable, locally saved Timesheet inside Dashboard. Dashboard also displays actual recorded focus/Flow intervals in its weekly Calendar; old or manually edited daily totals remain in Timesheet without invented timestamps. Timers, projects, saved daily tasks, habits, and music are shared across the app’s windows; committed task text is app-shared runtime state, while task-day selection, input drafts, and the task-selection popover editor remain window-local. Settings saves appearance, music wallpaper/material preferences, and Audius artist/playlist channels. Music streams public Audius tracks through native AVPlayer and controls Apple Music through the Mac’s Music app; provider and volume preferences persist locally.

| Area | Implemented today | Not implemented |
| --- | --- | --- |
| App window | `WindowGroup`; 1000 × 900 default size; 680 × 650 minimum content frame; fixed panel with scrollable tabs; one shared workspace model | Restoring timer runtime or unfinished task input across launches |
| Navigation | Selectable Focus, Dashboard, Habit tracker, and Settings; icon-only navigation below 900 points; disabled Stats | Statistics destination |
| Dashboard | Timesheet / Calendar / Projects switch; shared week navigation for time views; project creation/deletion; editable saved Timesheet; weekly Calendar with saved timer sessions, actual day totals, zoom, and live read-only details | Calendar editing, list/month views, sync |
| Active target | Searchable shared project catalog; creation dialog with name and 30 colors; local saving; selection drives recording; task-selection/name popover with saved project-linked suggestions and pins, captured in sessions | Project renaming and task-level aggregate editing |
| Pomodoro | Settings popover for focus/short/long breaks and iterations; saved preferences; manual short/long breaks; independent controls; focus-only recording | Automatic interval starts, notifications |
| Flow timer | Elapsed time, independent controls, session recording, and priority over Pomodoro | A completion limit |
| Music | Audius streaming and native Music-app control; in-Keep Music library songs/playlists/search, current cover art, seek/shuffle/repeat, transport, saved volume, loading/Retry, and Audius favorites | Full Apple Music catalog/recommendations, library writes, offline downloading, restoring queue/playback, zen mode |
| Tasks | Saved per-day lists; previous/next, date picker, Today; completion/add/delete, hover/keyboard Focus/Flow/both launch actions, and internal scrolling | Reordering, recurrence, project association |
| Settings | Music Automation permission status/request/recovery, saved Light/Dark/System appearance with glass subsection, wallpaper folder/rotation/looping, artist/playlist links | Sync, wallpaper subfolders |
| Habit tracker | Saved check-ins and minutes/times targets with weekday frequency; name/icon/date-range creation sheet; full-year monthly/weekly activity; weekly progress; selected-habit totals/rate/streak/calendar | Editing/deleting definitions, other recurrence rules, reminders, automatic timer completion, sync |
| Design system | Semantic light/dark assets, artwork-tinted shell/timers, readable project accents, reusable controls | Additional themes |

Both timers may run at the same time, with independent controls. Flow overrides Pomodoro for recording; overlapping time is counted once. Recorded sessions, project/day totals, and manual edits survive relaunch; timers restart idle. Daily task lists and completion states survive relaunch; current task text and unfinished input are runtime-only, while task names captured in sessions are saved. The live task store starts empty; examples appear only in previews.

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
    KeepApp.swift                  @main entry point, shared workspace/music/tasks/habits/preferences/wallpapers, WindowGroup
    WorkspaceApplicationDelegate.swift  Recording flush, music/wallpaper cleanup on termination
    AppShellView.swift             Navigation and focus-workspace composition
    ArtworkBackdrop.swift          Blurred shared music artwork behind the fixed panel
  DesignSystem/
    KeepTheme.swift                Semantic references to named color assets
    FocusProjectStyle.swift        Shared project accents and readable project labels
    ArtworkPalette.swift          Runtime artwork colors and appearance-aware contrast limits
    Components/
      NavBar.swift                 Shared navigation presentation
      PrimaryButton.swift          Shared action button with caller-supplied closure
      ProjectPicker.swift          Searchable project selection shared by Focus/Timesheet
      ProjectCreationDialog.swift  Shared name/color sheet with caller-owned creation action
      RemoveRowButton.swift        Accessible × button shared by task and Timesheet rows
      KeepControls.swift           Warm button/input styles and native selection menus
      KeepScrollView.swift         Shared native thin overlay scrollbars with transparent tracks
    Modifiers/
      CardStyle.swift              Shared card treatment and View.cardStyle extension
  Models/
    WorkspaceModel.swift           Shared timers, project selection, recorder, save coordination
    FocusProject.swift             Shared project catalog and Codable metadata
  Features/
    FocusSession/
      Models/                      FocusTimer timing/cycles, PomodoroSettings, window-local FocusTaskEditor
      Views/                       Focus workspace, timer/settings popover, and supporting panels
    Tasks/
      Models/                      FocusTask, civil-day selection/month grid, DailyTaskStore, TaskPersistence
      Views/                       TasksCard, day navigation, and date-picker popover
    Music/
      Models/                      MusicProvider, MusicTrack, MusicChannel, MusicPlayerModel, AppleMusicAccess, AppleMusicLibrary requests/state, WallpaperLibrary/cycle
      Services/                    AudiusClient, AVMusicPlayback, serial AppleMusicController, ArtworkWash, ArtworkPaletteSampler
      Views/                       MusicPlayerCard/favorites, AppleMusicLibraryView sheet, MusicArtworkView, MusicGlassPanel
    Settings/
      Models/                      AppPreferences, validated SettingsArchive/SettingsPersistence
      Views/                       SettingsView; native folder importer, channel-link editor, GlassinessSlider
    Dashboard/
      Views/                       Shared week/page controls, weekly calendar, and project catalog UI
      Models/                      RecordedSession timestamps, task/project/source and recorded civil timezone
    Habits/
      Models/                      Habit/goal/log archive, HabitStore/persistence, civil-date grids and labels
      Views/                       Activity grid, weekly progress, habit stats/calendar, creation/amount sheets
    Timesheet/
      Models/                      TimesheetLedger, calendar/duration helpers, local persistence
      PreviewData/                 Numeric fixtures used only by previews
      Views/                       Timesheet content and seven-day table; week supplied by Dashboard
  Assets.xcassets/                  Semantic light/dark colors, CozyCorner artwork, and AppIcon
  keep.entitlements                App-scoped read-only wallpaper bookmarks and scoped Music playback/read-only library automation
tests/HabitChecks.swift             Habit goals/weekday schedules, annual grids, aggregation/streaks, protected loads and relaunch persistence
tests/HabitTaskChecks.swift         Due task projection, shared completion, hidden days, Today-only launches and relaunch
tests/DailyTaskChecks.swift         Daily navigation, task isolation, and local persistence checks
tests/SessionRecordingChecks.swift  Timer sessions, task launches, overlap/breaks, archives, removal/Undo
tests/TaskActivityChecks.swift      Task/project suggestions, pins, recording, and archive checks
tests/AppearanceChecks.swift        Native offscreen appearance transitions and multiple-window checks
tests/ProjectCatalogChecks.swift    Catalog creation/deletion, active timers, historical time, and archive checks
tests/MusicPreferencesChecks.swift  Silent provider/volume/lifecycle and preferences-migration checks
reference/                         Local, Git-ignored visual references
```

All Swift sources belong to the same application module. Directory boundaries express responsibility, not separate packages or targets. The `keep` source directory is a filesystem-synchronized Xcode group; documentation and reference images sit outside it.

## 3. View composition

```text
keepApp → WorkspaceModel → FocusTimer + TimesheetLedger + TimesheetPersistence
└── WindowGroup
    └── AppShellView
        ├── NavBar
        │   └── Focus, Dashboard, Habit tracker, and Settings actions; disabled Stats
        ├── KeepScrollView → SettingsView → AppPreferences + WallpaperLibrary + MusicPlayerModel
        ├── DashboardView (shared week and Timesheet / Calendar / Projects selection)
        │   ├── KeepScrollView → TimesheetView
        │   │   └── TimesheetTable → TimesheetTimeCell → TimesheetEntryEditor
        │   ├── DashboardCalendarView → actual session hour grid + recorded detail sheet
        │   └── DashboardProjectsView → project catalog + shared creation sheet + deletion confirmation
        ├── HabitTrackerView (own KeepScrollView) → app-owned HabitStore
        │   ├── HabitActivityGrid → centered current-year daily intensity / stacked weekly totals
        │   ├── HabitWeekProgress + HabitStatisticsView → manual daily progress
        │   └── HabitCreationDialog / HabitAmountDialog sheets
        └── KeepScrollView → FocusSessionView
            ├── ActiveTargetHeader
            │   └── ProjectPicker → WorkspaceModel.projects; ProjectCreationDialog sheet
            ├── TimerWorkspaceCard
            │   ├── PomodoroTimerPanel → FocusTimerCard
            │   └── FlowTimerPanel → FocusTimerCard
            └── Supporting cards (HStack or VStack)
                ├── MusicPlayerCard
                └── TasksCard
```

`TimerWorkspaceCard` selects a horizontal or vertical arrangement of the two panels. Each panel passes a timer snapshot and caller-owned actions to `FocusTimerCard`. All actions go through `WorkspaceModel`. `FocusSessionView` owns a window-local `FocusTaskEditor` shared with its header and timer actions; committed task text lives in the workspace. `FocusSessionView` reads shared projects/timers and composes the music and daily-task feature views.

`AppShellView` owns `WorkspaceTab` selection and supplies Focus/Dashboard/Habit tracker/Settings action closures to `NavBar`. Navigation stays outside the scrolling content. Each tab remains mounted in the same fixed viewport; inactive content is invisible and hidden from hit testing and accessibility. Focus, Habit tracker, and Settings own vertical scroll views; Dashboard owns its three viewports. This preserves drafts and scroll positions without changing the panel size. Shared `PrimaryButton` receives its action from the caller.

## 4. Responsibility and dependency boundaries

| Location | Owns | Keep outside it |
| --- | --- | --- |
| `App` | Launch, shared model assembly, window composition, tab selection, and termination flush | Feature timing calculations and provider-specific logic |
| `Features/FocusSession` | Focus UI and session-specific state, actions, and rules | Generic styles and unrelated feature behavior |
| `Models` | Shared project metadata and coordination of timer recording with the ledger | View layout and provider integrations |
| `Features/Habits` | Habit definitions/logs, local persistence, prepared annual activity, completion/streak calculations, activity/progress UI | Timer recording, task lists, music, reminders, and sync |
| `Features/Tasks` | Per-day tasks and due-habit projection, civil-date navigation, local persistence, task-card UI | Timer recording, music state, and project assignment |
| `Features/Music` | Audius discovery/channels/artwork, stream resolution, AVPlayer lifecycle, read-only wallpaper loading/rotation, and card UI | Timer recording, archive ownership, credentials, and provider writes |
| `Features/Settings` | App-owned appearance/music preferences, validated archive, Settings UI | Timer/task archives, audio runtime, and image decoding |
| `Features/Dashboard` | Shared browsed week, Timesheet/Calendar selection, weekly calendar presentation, and the RecordedSession value type | Timer recording, ledger persistence, and invented history |
| `Features/Timesheet` | Numeric ledger, calendar/duration helpers, local saving, editable UI, and preview fixtures | Independent timer mutation and overlapping recorders |
| `DesignSystem` | Reusable presentation, control styles, layout conventions, and theme tokens | Session state, persistence, provider calls, and feature actions |
| `Assets.xcassets` | Named colors and bundled visual resources | Domain behavior and credentials |

The current composition is `App` → feature views and design-system views; feature views reuse the design system. Future business logic should remain independent of the visual components that display it. A shared button should receive an action from its caller.

There is no established MVVM layer, repository abstraction, service container, or package decomposition. Add a model or service only when implemented behavior needs it. Place feature-owned additions with the feature; introduce a shared boundary only when there is a concrete cross-feature need.

## 5. State and data ownership

`KeepApp` creates one `@State` reference to the observable, main-actor `WorkspaceModel` and passes it into every window. It owns two `FocusTimer` values, the selected project, the ledger with daily totals and timestamped sessions, committed task text, and one update task. Shells own tab selection; each Dashboard owns its page selection and week offset, and its Calendar owns zoom/scroll/recorded-detail state. FocusSessionView owns an explicit task editor draft model, and each TasksCard owns its day selection/input drafts. Previews construct models without persistence and cannot write live history.

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
- Selecting another project settles the old project first; only future time goes to the new selection. No project records under an explicit unassigned row. Committing a task-name change settles the old task and starts a new session context prospectively. Project/task/source changes and pauses separate sessions; ticks in the same context coalesce.
- The workspace updates approximately once per second, across tabs and windows. Clock differences determine duration; missing refreshes do not lose time. `ContinuousClock` includes system sleep and excludes wall-clock adjustments from duration calculations.
- Recorded intervals split at local calendar midnights, including DST days of 23 or 25 hours. Duration is mapped from the previous checkpoint’s civil date; later wall-clock changes affect subsequent date attribution.
- Timers and selection are app-scoped, continue while Keep runs, and restart idle on relaunch. No time is counted while the app is quit. Closing a window does not end app-owned timers.

`TimesheetLedger` stores one numeric seconds value per project ID/local day ID, together with project metadata. It also stores a separate `customProjects` catalog, so a created project survives relaunch before it has any time entries. `WorkspaceModel.projects` combines the four built-in projects with this saved catalog, excluding persisted `deletedProjectIDs`. The optional deleted-ID field preserves compatibility with earlier v1 archives and prevents built-in projects from reappearing after deletion. Deleted custom metadata and recorded entries/sessions remain intact; archive validation rejects unknown or unassigned deleted IDs. Rows appear immediately when recording starts or a project is added manually. Daily, project, and weekly totals are derived from entries. The UI initially shows the current Monday–Sunday week; arrows navigate history and This week returns to the current week.

`DashboardView` owns one Monday–Sunday week offset and supplies the resulting `TimesheetWeek` to both time views. Its header, week arrows, This week action, summary, and Timesheet / Calendar / Projects switch stay outside the scrolling content. Switching views or leaving Dashboard preserves the selected week, page, and mounted content. `TimesheetView` owns only its content and project-picker/creation presentation; all ledger mutations still route through the workspace.

`DashboardCalendarView` reads real `RecordedSession` values from the workspace ledger, filtered by the displayed week’s saved civil day IDs. Each interval captures project metadata, trimmed task text, Pomodoro focus or Flow source, start/end dates, and the recording timezone. The existing single recorder supplies both sessions and daily totals, so Flow priority and uncounted breaks cannot diverge. Continuous ticks coalesce by recording context/day; project/task/source changes, pauses, removals, and midnight create separate segments. Clock discontinuities preserve duration and create separate segments instead of fabricating one continuous wall-clock interval. The model preserves the recorded civil timezone for display, including repeated DST hours.

Calendar shows actual daily/session-week totals, seven weekday headers, weekend shading, Today, and a scrollable 24-hour grid initially positioned at 08:00. Project-colored blocks show task/project/start/duration where space permits, with lanes for overlapping minimum-height blocks. Clicking opens read-only details that update while recording continues. Hour zoom ranges from 48 to 108 points, and the 900-point minimum grid scrolls horizontally at narrow widths. A week without sessions shows an empty state. The sample source has been removed. Existing daily totals and manual edits cannot reconstruct timestamps and therefore remain in Timesheet only; Calendar’s session total can differ from an edited daily total. There is no Calendar editing, drag-and-drop, or connection to saved daily tasks.

`TimesheetTimeCell` opens a native `TimesheetEntryEditor` popover. The editor accepts nonnegative `h:mm` or `h:mm:ss`; blank sets the cell to zero. Invalid input stays in the editor with an explanation. Saving replaces the cell total after settling the running timer; later elapsed time adds to the edited value. A zero cell retains its project row. Timesheet edits project/day aggregates; they do not rewrite the separately recorded session timestamps or task metadata.

The trailing × removes a project's entries and recorded sessions for the displayed week through `WorkspaceModel.removeTimesheetProject`. It settles recording before removal and saves immediately, preserving other projects, other weeks, catalog metadata, selection, and timer state. A running timer can create the row again with subsequent time. The model keeps one in-memory `TimesheetRemoval` for Undo across tabs/windows; Undo settles again and adds back removed time and sessions alongside newly recorded/edited values, then saves. Subsequent running time uses a new recording ID, so Undo cannot merge it into deleted history. Undo history is not restored after quitting. `TimesheetView` shows the removal/Undo notice and explains continued recording when applicable.

`TimesheetPersistence` JSON-encodes the ledger, custom catalog, optional `PomodoroSettings`, actual sessions, and `taskActivities` into the app’s standard `UserDefaults` under `keep.timesheet.v1`. Older records without the added fields load with an empty custom catalog/session array and default timer settings, retaining their entries. Session validation checks IDs, finite ordered dates, civil-day boundaries, timezone, and task length; malformed records preserve the archive and block edits. It loads on app model creation, saves about every five seconds during recording, and saves immediately after actions/edits/creation/settings changes. `WorkspaceApplicationDelegate` flushes the last partial interval on normal app termination, including when no windows remain. Abrupt termination can lose time since the last checkpoint save. Corrupt saved data, including invalid settings, blocks mutations and shows Retry rather than overwriting unreadable records. Timer runtime, current task text, inline/input drafts, and project selection are not restored. Daily task lists use their own persistence below.

`DashboardProjectsView` presents an alphabetically sorted, scrollable catalog with project-colored folders/names, row delete controls, and a fixed Add project footer. It owns creation-sheet and native deletion-confirmation presentation. Adding uses the shared dialog without changing selection or inventing time. Deletion routes through `WorkspaceModel.deleteProject`: settle elapsed recording, persist the removed ID, and switch a deleted active selection to No project. Timer phases and committed task text are preserved; future running time is unassigned. Deleting an inactive project leaves the current session context intact. Timesheet/Calendar retain historical metadata and time, and Timesheet removal/Undo does not restore a deleted catalog project. Projects hides week controls and shows a project count; switching Dashboard pages retains the browsed week.

`ActiveTargetHeader` and `TimesheetView` own picker and creation-sheet presentation. The target border stays neutral; clicking task text opens `TaskSuggestionPicker`. `FocusTaskEditor` owns its window-local name/search draft; typing never changes recording. Return, dismissal, leaving Focus, or a timer action commits through the workspace; Escape cancels, while picking a saved row discards the draft and atomically selects that task/project without starting timers. The menu searches task/project names and presents one flat list directly beneath the input, with inline project-colored folder/name labels and pin controls. Pinned tasks stay first; there are no separate pinned/recent sections or inset suggestion cards. Selecting a project never forces the task field into focus. `ProjectPicker` owns transient search/hover/focus state and searches the shared catalog by name. Its Create action closes the popover and opens `ProjectCreationDialog`, which owns only draft name/color/error state. The dialog offers 30 named color swatches, a selection checkmark, keyboard focus, and native Create/Cancel shortcuts. Cancel discards drafts. `WorkspaceModel.createProject` trims names, requires 1–80 characters, rejects case/diacritic-insensitive duplicate names and invalid colors, assigns a UUID, and saves the catalog without inventing time entries. Focus selects the created project without automatically opening or selecting task text; Timesheet adds it to the displayed week without changing the active timer project. `DesignSystem/FocusProjectStyle.swift` maps Codable project accents to named color assets; the neutral accent is reserved for unassigned time. `TimesheetPreviewData` supplies numeric sample data exclusively for previews.

`TaskActivity` lives alongside its saved ledger metadata, with a stable UUID, trimmed title, project snapshot, last-used date, and pin state. `WorkspaceModel.taskSuggestions` filters to current catalog projects plus No project, sorts pinned first and then most recent, and owns selection/pin actions. Work remembers a task/project pair when starting a recording timer, committing a title during recording, or changing project/task while recording; blank tasks and standalone breaks add no activity. Case/diacritic-insensitive reuse within a project preserves identity/pins, while the same name in different projects remains separate. Selection settles prior recording before changing both task/project; it preserves running/paused timer phases. Pinning also settles recording, so delayed focus completion cannot lose elapsed time. Suggestions/pins share the workspace archive independently of daily task lists. Legacy archives without activities derive them from real recorded sessions; corrupt/duplicate identities or invalid metadata preserve the archive and block mutations. Deleted projects are excluded without losing their time or saved metadata. Current task text/selection still starts fresh after relaunch.

`KeepApp` owns one observable `DailyTaskStore`, passed through AppShellView/FocusSessionView to TasksCard. Task changes are shared across windows independently of timer recording and music. The store receives the app-owned HabitStore to project due habits into the selected civil day, without writing duplicate recurring tasks. `FocusTask` has a stable Codable UUID, title, and completion state; `TaskArchive` maps Gregorian `yyyy-MM-dd` civil-date keys to task arrays. The live store starts empty, with example tasks confined to previews.

Each `TasksCard` owns `TaskDaySelection`, a date-picker draft, focus, and unfinished input keyed by day. Previous/next arrows use calendar day arithmetic rather than 24-hour offsets. Clicking the date opens a styled SwiftUI calendar popover (`TaskDatePicker`) with a six-week month grid, month navigation, Today marker, and a warm typed YYYY-MM-DD field; Show tasks selects the specific past/future date. `TaskMonthGrid` uses the supplied calendar’s first weekday, month/day arithmetic, and timezone. Day buttons expose full date/selection labels and keyboard arrow navigation; invalid typed dates disable Show tasks. Dismissing the popover discards its draft. Today returns to the current day; following Today crosses midnight automatically through the workspace's existing day refresh, while a browsed date stays pinned. Selecting another day preserves that day's input draft and resets list scrolling. Civil-date keys keep saved plans on their original dates across timezone changes; the task calendar follows the supplied calendar's timezone while retaining Gregorian keys.

Adding, checking, or deleting a task targets the rendered day and stable task ID, so delayed callbacks cannot change another day's task. Each day's remaining count is derived from its own list. Blank ruled rows fill the available list area, and the add field stays at the card's bottom. Only today’s task rows offer Focus, Flow, and both-timers buttons on hover or keyboard focus; past/future rows have no launch buttons or timer accessibility actions. Launch callbacks recheck the actual current day at activation to reject stale midnight actions; task text also exposes equivalent accessibility actions. FocusSessionView commits any active editor before calling `WorkspaceModel.startTask`. This settles the old title once, assigns the selected title to the shared active task, and starts/resumes only the chosen timers on the current project. Focus leaves an active break for a new focus interval without clearing completed-cycle progress. Both starts at one instant and retains Flow priority. Other already-running timers stay running and share the new task title; past/future tasks cannot launch recording. Ordinary tasks have no carry-forward, recurrence, or saved project association.

Due habit rows use their stable habit UUID and an explicit habit origin, with distinct list identities from ordinary rows. They appear on past/current/future scheduled dates within the inclusive range and expose a Habit label. Checking one explicitly sets its habit goal amount; unchecking clears progress. Partial amounts remain unchecked. Future habit checkboxes are disabled. Tracker edits invalidate the task projection through observation; there is no second completion archive or timer-to-completion inference. Removing a habit row saves only a hidden occurrence for that day in the optional `TaskArchive.hiddenHabitIDs` field; it preserves the definition, other days, and any completed log. Older task archives default this field to empty. Corrupt habit loads omit projected rows and surface Retry while ordinary tasks remain available.

`TaskPersistence` JSON-encodes the complete archive into UserDefaults under `keep.tasks.v1` after every task mutation. It is separate from the Timesheet key and leaves existing time/catalog/settings data intact. Invalid JSON, invalid civil dates, blank task titles, or duplicate IDs within a day block edits and show Retry, preserving unreadable data. Save failures retain in-memory changes and offer a save retry. Task lists/completion survive relaunch; selected day resets to Today and input drafts are not saved. Previous unsaved prototype tasks have no persisted data to migrate. Previews use stores without persistence. There are no notification permissions, databases, or credentials.

`KeepApp` also owns one observable, main-actor `MusicPlayerModel`, passed through each shell and Focus view. It is independent of timer recording, persists across tab/window changes while the app runs, and stops at app termination. Playback and queue are runtime-only. Provider, volume (including mute), and Audius channel selection restore from AppPreferences without launching Music, requesting access, or loading audio. Previews stay idle and make no network calls until Play.

Music behavior and external boundary (verified against the [Audius REST reference](https://api.audius.co/v1) and [Apple AVPlayer documentation](https://developer.apple.com/documentation/avfoundation/avplayer) on 2026-10-05):

- `AudiusClient` uses an ephemeral URLSession without a disk cache against `https://api.audius.co/v1`, searches `tracks/search?query=lofi&limit=30&includePurchaseable=false`, and identifies requests with `app_name=Keep`. Current public read-only endpoints need no API key. Decode numeric/access flags explicitly; reject gated, unavailable, deleted, unlisted, inaccessible, duplicate, or invalid-ID tracks. Track titles/artists appear in the card with a safe Audius attribution link.
- Resolve `tracks/{id}/stream?no_redirect=true` when selecting/retrying a track. Audius returns a temporary signed HTTPS audio URL; pass it to AVPlayer and never save/log it. Metadata can outlive audio: stream-lookup 403/404 results advance to the next candidate, bounded by the queue length. A fully unavailable queue shows an error. Network/rate-limit errors stop discovery and offer Retry.
- `AVMusicPlayback` owns AVPlayer, item/status KVO, and end/failure notifications. Actual `timeControlStatus` drives Playing versus Loading/buffering. End advances/wraps the queue; previous/next preserve paused intent. Play resumes the current item after pause. Volume is clamped to 0–1; the card adds mute/unmute with a remembered nonzero level.
- State is explicit: idle, loading, playing, paused, or failed with actionable text. Pause cancels discovery/stream resolution; item and request identities prevent delayed callbacks from restarting canceled/replaced audio. Requests have 20-second timeouts; active loading/buffering has a 30-second watchdog and Retry. App shutdown cancels tasks, removes observers, and releases the current item.
- `MusicCatalog` and `MusicPlayback` protocols allow deterministic network/player fixtures. No third-party package, backend, write endpoint, credentials, microphone permission, or offline downloading is introduced. Audius remains an external service; availability and rate limits can vary.

Apple Music uses the native Music app’s existing account and audio engine. `AppleMusicController` sends typed Apple events on a serial actor, using the installed Music scripting dictionary. Request only `com.apple.Music.playback` and `com.apple.Music.library.read` through Apple’s [scoped scripting-target entitlement](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html), alongside the Apple-events automation entitlement and `NSAppleEventsUsageDescription`. Provider selection/restoration remains passive. Explicit Browse or Play launches Music in the background if needed; normal macOS Automation permissions apply. No scripts, credentials, library writes, UI-control entitlement, or system output-volume changes are introduced. Sign-in/account management remains in Music.

`AppleMusicLibraryView` opens a 620 × 720 sheet without changing the music card’s allocation. The shell supplies its viewport through the environment; the sheet clamps to viewport width minus 48 and height minus 64 (620 × 586 at the minimum window). The former discovery/account footer is removed; Open Music remains in the provider menu and Settings. Each sheet owns its search/selection/paging and an `AppleMusicLibraryModel`, sharing only the player’s serial controller. Songs and playlists load in 50-item pages; search is debounced 350 ms. Search reads names/IDs and song artists/albums in bulk, then filters locally with case/diacritic-insensitive matching and returns a page. Metadata reads happen on the serial actor and check cancellation between calls and while filtering. Music’s native search command returns -10004 under the read-only sandbox grant on this installation, so Keep does not use it or expand to library-write access. The controller bounds search text to 200 characters and follows `source 1 → library playlist 1` for songs and the source’s user playlists for playlist browsing, matching Music’s exposed element hierarchy. Music accepts song ranges but rejects playlist range reads (-1708), so playlists use indexed object references. Native absolute ordinals use the correct descriptor type and Foundation’s host representation. Runtime native IDs include the playlist context when needed and never enter an archive; selecting a song plays its native object, and a playlist can be opened or explicitly played. Request generations and sheet task cancellation fence old results; failed reads offer Open Music/Retry, and empty libraries/results are explicit. Browse never starts playback; it observes the current Music selection and starts the shared status refresh without claiming ownership of already-playing audio. Playback Retry retains the failed library selection.

The app-owned one-second refresh reads actual state, title/artist, stable track identity, position/duration, shuffle, and repeat. Native current-track artwork is cached when available, bounded to 12 MiB, and forwarded to the shared wallpaper decoder. Missing/delayed covers retry after two seconds for the first few attempts, then every 15 seconds; changing identity resets that retry schedule. Missing artwork does not stop audio. The sheet shows available cover art even with a custom wallpaper and exposes play/pause, previous/next, volume/mute, seeking, shuffle, and repeat off/all/one. Selecting Track artwork in Settings uses the same cover for the card/backdrop/palette. Play first applies Keep’s saved volume; skips retain paused intent. Transient Music read failures retain the status observer. An eight-second recovery grace shows Loading with a native spinner, preserving play intent and current metadata instead of flashing Retry; status reads stay at one-second intervals during grace, then back off to 15 seconds. A Play response that is still stopped/paused also remains Loading until playback starts or grace expires. Persistent failures show the real error, while permission denials bypass grace; a read failure immediately after a native command also starts observation. A later status restores metadata/artwork without another Play. Permission failures stop the observer instead of repeatedly asking for consent. All native commands remain off the main actor, with cancellation and generation fences. Playback continues across tabs/windows. Provider switching and quitting pause only an engaged Music session; termination awaits the bounded release event. Music’s account, subscription, local library, and cloud availability determine which items can play.

`MusicPlayerModel` owns runtime `AppleMusicAccess` state independently of preference persistence. Settings shows a Permissions section even when invalid preferences block edits. Opening the visible Settings tab or returning from System Settings checks access only if Music is already running. The controller probes actual playback-state and library-count events with `kAEDoNotPromptForUserConsent`, distinguishing unrequested and denied access without wildcard permission preflights. Explicit Allow Music access launches Music if needed and permits the normal macOS prompt; it never plays, changes provider, or applies volume. Denied access links to Privacy & Security → Automation, and a recovered grant reconnects status observation for the selected Apple provider. Hidden mounted Settings must not initiate probes. Permission status is not archived. SDK behavior was checked against installed AppleEvents declarations and [Apple’s Automation guidance](https://support.apple.com/en-hk/guide/mac-help/mchl108e1718/mac) on 2026-10-06.

Full streaming-catalog search, recommendations, and library modification are outside this bridge. Apple’s native MusicKit catalog support requires enabling the MusicKit App Service for Keep’s matching App ID and development team; see [automatic token generation](https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api). No private key or developer token is embedded, and no remote developer-account settings are changed.

Settings and wallpaper ownership:

- `KeepApp` owns one `AppPreferences` and one `WallpaperLibrary`, shared across windows independently of timer/task stores. Settings selection uses the same mounted viewport as Focus and Dashboard. Its title and sections share a horizontally centered column capped at 900 points; rows can stack at narrow widths. Shared `KeepControls` supplies rounded paper buttons/inputs and native menus with hover/focus/disabled states; appearance uses explicit selected buttons. Appearance includes Dark mode and an “A little glass” subsection. Its continuous native glassiness slider has a custom 28-point thumb and 44-point tracking area, retaining AppKit pointer/keyboard behavior and theme-colored fill. The subsection includes a live player preview sharing the same model and artwork, so adjustments are visible immediately without changing tabs. Default appearance remains Light; System resolves the native application’s `effectiveAppearance` through the observable `SystemAppearance` KVO adapter in `App/KeepAppearance.swift`; `keepAppearance` gives the shell and Music library sheet an explicit Light/Dark preference. Window overrides do not become the source for System. Native changes update the SwiftUI content across windows without recreating views or losing drafts. Clearing an explicit preference with nil previously left content in Light while the title bar followed macOS. Sheets/popovers inherit the selected appearance. Named assets define dark variants.
- `SettingsPersistence` stores a validated Codable archive in `keep.preferences.v1`: appearance, wallpaper source, read-only folder bookmark/display name, order/interval/automatic rotation/loop, material/glassiness, saved channel metadata, and selected channel ID. Updates save immediately; invalid loads disable editing and preserve the original data with Retry. No signed audio URLs or image bytes enter this archive. Provider and volume persist through optional validated archive fields; playback/queue and drafts remain runtime-only.
- Native `fileImporter` chooses a folder. `WallpaperLibrary` creates/resolves app-scoped read-only security bookmarks, refreshes stale bookmarks, and balances scoped access. Folder scans and ImageIO thumbnail decoding run off the main actor, skip hidden files/symlinks/subfolders, and bound thumbnails to 2048 pixels. Cancellation and generation checks reject stale folder/image results. Missing folders, empty lists, or unreadable images show actionable Settings errors and retain the bundled visual fallback.
- The app owns a single rotation task regardless of the number of windows. Folder rotation defaults to automatic, sequential, every minute, and looping. Intervals are 30 seconds, 1, 5, or 15 minutes. Shuffle visits each image once per cycle and avoids an immediate repeat between cycles. Turning looping off stops on the final image; manual Next can begin another cycle. Changing configuration cancels/restarts the applicable load/rotation; shutdown cancels both tasks.
- Wallpaper sources are bundled Cozy corner, My folder, and Track artwork (Audius or Apple Music). The persisted `audius` raw value is retained for backward compatibility. `MusicTrack` carries validated HTTPS artwork and optional artist-channel metadata; `WallpaperLibrary` fetches the current track artwork only when that source is selected, using an ephemeral URLSession with a 20-second timeout. It validates HTTPS URLs/statuses, rejects responses over 12 MiB, and decodes 2048-pixel thumbnails off the main actor with cancellation/generation checks. One decoded NSImage is shared across all windows; missing/failed artwork falls back to Cozy corner on both surfaces. Native artwork bytes use the same off-main ImageIO thumbnail/wash/palette pipeline. One cached native cover serves the library sheet and, when selected, the card/backdrop without duplicate decoding; native and folder load tasks are independently canceled/fenced. Artwork advances with tracks; folder rotation options apply only to folder images.
- The player’s passive channel menu lists saved artists/playlists plus All lofi. The heart saves/unsaves the selected artist/playlist, or the current track’s artist when browsing All lofi. Its outline/filled state comes from the existing preferences archive; unsaving here does not stop playback. A separate saved-list button expands the bottom controls upward with a 250 ms animation (no motion when Reduce Motion is enabled). The drawer is local to each card, remains open through channel playback/track changes, and collapses only when toggled. Clicking a saved row explicitly starts/resumes that source; repeated clicks on an already playing source do not restart it. Opening favorites does not change the card’s 288-point minimum or its allocated size. A vertically bounded `ViewThatFits` shows the list above transport controls when both fit; otherwise the list replaces the track/transport area and puts the heart/toggle in its heading. Playback continues while controls are hidden. Only the saved-list area scrolls; toggling never adds outer Focus scroll overflow. Audius attribution sits at the top-left of the artwork. A small provider menu sits beside the top-left attribution badge and retains passive Audius source selection in a submenu. The top-right 46-point circle displays `chevron.up.chevron.right.chevron.down.chevron.left` as a disabled zen-mode placeholder; heart/list controls have circular hover/focus treatments and the list uses `list.bullet`.
- Settings resolves pasted HTTPS Audius links via `/v1/resolve`, accepts only public artist/playlist resources, deduplicates by kind/resource ID, and offers Play/removal. Playback loads `/users/{id}/tracks` or `/playlists/{id}/tracks` through the existing access filters and native player. Source changes release the old queue/item and fence canceled callbacks. Choosing through the passive source menu never autoplays; Settings Play and saved-drawer rows explicitly start/resume it. The selected saved source reopens without networking/autoplay; removing it through Settings returns to All lofi.
- `MusicGlassPanel` uses an explicitly aligned copy of the player artwork behind the transport, cropped to the controls’ rounded bounds. It receives the full artwork size/inset so the crop remains aligned as the card grows. Glassiness continuously reduces artwork blur (24 points to zero) and paper opacity (one to zero), with a permanent appearance-specific readability wash (stronger in Dark to protect cream text over bright artwork). At zero and with Reduce Transparency it uses opaque paper. Frosted uses this artwork-backed treatment; Liquid Glass adds native `glassEffect(.clear)` so a more opaque native material cannot substitute the outer window’s colors for the player image. This supersedes the previous material-thickness/tint mapping; neither the outer background nor playback state changes when moving the slider. `GlassinessSlider` bridges a continuous native NSSlider with a stable coordinator/binding and a theme-colored track. Its enlarged thumb stays bright in both appearances. Decorative shell, section, and glass borders opt out of hit testing so they cannot intercept control input.

Project management, further music providers, and notifications remain scoped future work. See `docs/decisions.md`.

### Habits

`KeepApp` owns one main-actor observable `HabitStore` shared across windows, independently of workspace recording, daily tasks, and music. `HabitPersistence` validates and saves the complete `HabitArchive` in UserDefaults under `keep.habits.v1` after each mutation. Definitions persist before their first log. Stable UUIDs identify habits; logs are unique by habit/day. The archive rejects invalid goals/date ranges/frequencies, duplicate identities/logs, orphan or rest-day logs, and invalid amounts. A failed load preserves the saved bytes and blocks changes until Retry succeeds; failed saves retain in-memory changes and offer Retry. Live storage starts empty; verification fixtures are in-memory only.

A habit has a trimmed 1–80-character name, one of twelve named SF Symbols, a start date, optional inclusive end date, and a goal: **Daily check-in** (0/1) or **Daily target** (positive minutes/times per day). Seven selectable weekday circles set the frequency; all days are selected initially, at least one is required, and older archives without weekdays remain daily. Targets allow 1–1,440 minutes or 1–10,000 times. An amount log stores a nonnegative integer up to 1,000,000; zero removes the log, a partial amount does not count complete, and meeting/exceeding the goal counts the habit once on that day. Editing progress is manual and allowed only on scheduled dates through today. Nothing automatically completes a habit from elapsed timer time. Explicitly checking its projected daily task updates the same habit log.

Habit dates reuse `TaskDay`'s Gregorian civil keys, with the local calendar/timezone and Monday-first weeks. Calendar arithmetic handles DST, leap days, and month/year boundaries. Saved keys stay on their original civil day after a timezone change. Formatting uses the same calendar/timezone as the keys. Browsed week/day, activity mode, selected habit, stats month, and sheet drafts are window-local; following Today updates across midnight through the existing workspace display refresh. No second ticker or recorder is introduced.

The activity view centers January through December of the current year in Monday-first week columns. Monthly mode shows daily tiles with five completed-habit intensity levels (0, 1, 2, 3, 4+); Weekly mode fills one square per completed goal, capped at seven, with an explicit 7+ legend and exact totals in tooltips/accessibility labels. A lone completion fills only one square. Squares fit the viewport at 6–11 points with 3-point gaps; adjacent-year dates are hidden and future dates disabled. Choosing a past/current tile navigates the weekly progress list. Activity, progress, and stats share one paper surface separated by faded lines. The weekly list fits its seven day columns at 480 points; selected-habit stats and an interactive month calendar use the space on the right (up to 560 points) at viewport widths of at least 900 points, and stack below at smaller widths. Icon-derived accents, green/purple activity modes, and varied pastel metrics reuse existing semantic/project colors with readable ink. Check-ins toggle directly; amount goals open a numeric sheet with a target shortcut and zero-to-clear. The fixed shell viewport scrolls vertically.

Stats derive from the saved logs, with no stored totals. A runtime habit/day query index is rebuilt on loading and updated with log changes so every visible cell does not rescan the complete history; the index is not persisted. Month completion rate uses scheduled days through today, excluding future days and dates outside the habit range. Lifetime totals count completed days, including previous months. Current/best streaks count consecutive scheduled check-ins, skipping rest days. While today is a rest day or its goal is pending, current streak can end at the latest previous scheduled date; a missed due day breaks it. After the habit end date, current streak is zero while best streak retains history. Weekday matching uses the Gregorian civil key rather than a timezone-dependent instant. The stats calendar can correct prior daily progress; its month totals/rate follow the browsed month while current/best streaks remain as of today. Definition editing/deletion, reminders, recurrence rules beyond weekday selection, and sync remain outside this implementation.

`HabitActivitySnapshot` prepares annual civil dates, labels and exact daily/weekly counts from validated logs. HabitStore caches it by civil day/timezone/locale and invalidates it on definition/log changes or Retry. Monthly/Weekly selection reuses the snapshot instead of recalculating and formatting a year in the view body; accent contrast and tile size resolve once per body. The grouped mode switch follows Dashboard styling. HabitDateField reuses the styled TaskDatePicker calendar (with a Choose date confirmation), and KeepCheckboxStyle supplies the theme-consistent end-date/task checkbox. Empty habit circles retain visible outlines even when future/rest days are disabled.


## 6. Visual implementation and layout constraints

`docs/style.md` owns the cozy editorial palette. Named color assets are the source of truth; `KeepTheme` provides shared semantic references. Light uses the original cozy palette; Dark uses espresso/brown surfaces and cream ink. Settings selects Light, Dark, or System through the root color-scheme preference.

The shell places a cream workspace over a heavily blurred version of the player’s current artwork. `MusicArtworkView` shares the selected folder/Audius image or bundled CozyCorner fallback between the music card and `ArtworkBackdrop`. The wallpaper library prepares a clamped-edge, Gaussian-blurred 64 × 64 Core Image texture off the main actor alongside each decoded image, with a cached bundled fallback. The backdrop smoothly scales that small texture to fill the window and applies a light paper wash or a stronger dark tint; it needs no window-sized blur layer. It is decorative, opaque, noninteractive, and present behind every tab; artwork changes never replace the tab/content hierarchy or alter panel geometry. The semantic background asset remains the fallback and dark tint. Pomodoro focus, break, and Flow retain their terracotta, butter, and sage bases, blended with the artwork’s primary, ambient, and supporting hues. The panel takes a quieter ambient tint while staying opaque. Tasks use an ivory ruled-list treatment. The music artwork is a bundled asset in `keep/Assets.xcassets/CozyCorner.imageset/`; its generation prompt and provenance are in `docs/music-artwork.md`.

`ArtworkPaletteSampler` downsamples the already-decoded image to 32 × 32 sRGB off the main actor. Alpha-weighted averaging supplies an ambient tint; chromatic hue buckets supply two distinct supporting colors. Transparent images return no palette and grayscale images use their average. The image, wash, and runtime-only palette are delivered together behind the existing cancellation/generation fences. Bundled fallback uses the same pipeline; no extra fetches, archives, or per-view image scans are added. `AppShellView` passes the selected palette through the environment. `KeepTheme.artworkSurface` blends opaque semantic bases in linear RGB and limits the tint to retain 4.5:1 contrast against timer ink or panel muted text in the actual appearance. Project labels/folder icons use the chosen accent with hue-preserving lightness adjustment for readable light/dark shades; picker and Timesheet names share this mapping.

Layout and accessibility behavior:

- Default window size is 1000 × 900; the root view has a 680 × 650 minimum frame.
- The panel fills the usable window content area with equal 16-point margins on all four sides and 24-point inner padding. Its size depends on the window, not the selected tab or content height. Navigation stays at the top; longer tab content scrolls inside the panel. There is no fixed maximum panel width.
- Navigation switches to icons only below 900 points, preserving accessible labels, tooltips, and actual selected/focus states. Habit tracker is selectable beside Dashboard and uses its own saved daily habit model.
- Every scrolling surface uses `KeepScrollView`, which configures the enclosing native scroll view for overlay scrollbars and draws rounded 5-point thumbs with transparent tracks. Native scrolling, tracking, and fade behavior remain; no system scrollbar preferences are changed.
- Below 820 points of window width, timer and supporting card pairs stack vertically.
- The Timesheet table keeps a minimum width of 900 points and scrolls horizontally on narrow windows, preserving readable seven-day columns, totals, and the trailing remove button. Dashboard’s shared heading and week/view toolbar can stack using `ViewThatFits`. The Calendar likewise preserves a 900-point minimum grid width and uses both horizontal and vertical scrolling.
- The target header uses `ViewThatFits` to move its project/task card below the heading when needed. Its native popover is 340 points wide with a scrollable project list; the folder button and project rows show hover and keyboard-focus feedback.
- `CardStyle` supplies padding, flexible width, and rounding without imposing fixed maximum heights.
- The shell passes the Focus tab's available viewport height into its content as a minimum height. Music and task cards have a 288-point minimum and grow together into the remaining space above the footer on taller windows. On short windows the content keeps its natural minimum height and scrolls; compact layouts retain stacked cards. The music artwork fills its card without changing aspect ratio, while its controls stay at the bottom. Task lists scroll internally.
- Timer digits use stable widths and scale down to fit their column. Running/stopped/completed states have explicit text.
- Primary actions, timer settings/reset/break controls, and editable time cells have visible keyboard-focus rings; inputs expose labels and focus boundaries. Editors use native Save/Cancel shortcuts. Completion controls place the break button on a separate row when needed.
- The music panel offers frosted material or native Liquid Glass with adjustable glassiness, an explicit user-requested exception to flat styling. Reduce Transparency replaces either with opaque paper.

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
| Folder bookmarks | `com.apple.security.files.bookmarks.app-scope` via `keep/keep.entitlements` in Debug/Release |
| Outgoing network connections | Enabled in Debug and Release for Audius API/audio hosts |
| Music automation | `com.apple.Music.playback` scripting target, Apple-events automation entitlement, and usage description in Debug/Release |
| Info.plist | Generated by Xcode |
| Third-party package products | None |

The language-mode setting does not identify the installed Swift compiler. Project metadata does not prove SDK availability or that a build succeeds on a given machine. Check the installed toolchain when compatibility matters.

There is no Xcode test target, configured lint/format tool, third-party persistence framework, backend, or third-party music SDK. AVFoundation handles audio and Foundation URLSession handles Audius HTTPS requests. Foundation UserDefaults provides local storage; the checked-in daily-task and session-recording checks run through standalone Swift harnesses. The native wallpaper importer uses read-only selected-folder access and app-scoped bookmarks; it adds no filesystem write permission.

## 8. Development and verification

Run commands from the repository root:

```sh
open keep.xcodeproj
xcodebuild -list -project keep.xcodeproj
xcodebuild -project keep.xcodeproj -scheme keep -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/keep-derived-data \
  CODE_SIGNING_ALLOWED=NO build
```

Run the daily-task checks:

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  keep/Features/Tasks/Models/*.swift keep/Features/Habits/Models/*.swift \
  tests/DailyTaskChecks.swift \
  -o /tmp/keep-daily-task-checks
/tmp/keep-daily-task-checks
```

Run the integration checks using the daily-task source list above, replacing `tests/DailyTaskChecks.swift` with `tests/HabitTaskChecks.swift` and the executable with `/tmp/keep-habit-task-checks`.

Run the habit checks:

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  keep/Features/Tasks/Models/TaskDay.swift \
  keep/Features/Habits/Models/*.swift tests/HabitChecks.swift \
  -o /tmp/keep-habit-checks
/tmp/keep-habit-checks
```

Run the session-recording checks:

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  keep/Models/FocusProject.swift keep/Models/WorkspaceModel.swift \
  keep/Features/FocusSession/Models/FocusTimer.swift \
  keep/Features/FocusSession/Models/PomodoroSettings.swift \
  keep/Features/Timesheet/Models/TimesheetLedger.swift \
  keep/Features/Timesheet/Models/TimesheetPersistence.swift \
  keep/Features/Dashboard/Models/RecordedSession.swift \
  tests/SessionRecordingChecks.swift -o /tmp/keep-session-checks
/tmp/keep-session-checks
```

Run the project-catalog checks using the same domain-source list as the session checks above, replacing `tests/SessionRecordingChecks.swift` with `tests/ProjectCatalogChecks.swift` and the output with `/tmp/keep-project-checks`.

Run task-activity checks with the session domain-source command above, replacing `tests/SessionRecordingChecks.swift` with `tests/TaskActivityChecks.swift` and the output with `/tmp/keep-task-activity-checks`.

Run native offscreen appearance checks (changes affect only the test process):

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  $(rg --files keep -g '*.swift' | rg -v 'KeepApp.swift') \
  tests/AppearanceChecks.swift -o /tmp/keep-appearance-checks
/tmp/keep-appearance-checks
```

Run the silent music/preferences checks:

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  $(rg --files keep -g '*.swift' | rg -v 'KeepApp.swift') \
  tests/MusicPreferencesChecks.swift -o /tmp/keep-music-preferences-checks
/tmp/keep-music-preferences-checks
```

`tests/HabitChecks.swift`, `tests/HabitTaskChecks.swift`, `tests/DailyTaskChecks.swift`, `tests/SessionRecordingChecks.swift`, `tests/ProjectCatalogChecks.swift`, `tests/TaskActivityChecks.swift`, `tests/AppearanceChecks.swift`, and `tests/MusicPreferencesChecks.swift` are the checked-in standalone check sources. Earlier timer/workspace/music/preferences harness sources were removed from the repository; the new music/preferences source above is separate from those historical harnesses; the verification receipts below describe earlier runs and do not imply those commands are available today. Reinspect the current tree before choosing checks for a change.

On 2026-10-05, the unsigned Debug build, 45 timing checks, and 180 workspace checks passed. Checks cover configurable durations, short/long break cycles, settings changes during focus/rest, recording overlap, Flow priority, manual break exclusion, paused/reset timers, project reassignment, active edits, weekly row removal/Undo during recording, preserved other weeks/projects, fractions, midnight/week rollover, DST, duration validation, project creation, all 30 color encodings, backward compatibility, corrupt-load protection, and persistence of time/catalog/settings across separate processes using isolated temporary preferences. The build emitted an App Intents metadata warning because no AppIntents dependency is present.

Native offscreen renders of running/completed/break Focus states, empty/live/populated Timesheets at default, wide, and narrow sizes, and the entry editor were inspected. Live popover interaction, keyboard navigation, VoiceOver, release signing, and audible sound remain unverified; computer-use permission was unavailable for live UI checks.

The project-creation dialog, all 30 color swatches, the updated picker, and a newly created Timesheet row were inspected in native offscreen renders. Live popover-to-sheet transitions and keyboard interaction remain unverified.

Default/custom Pomodoro settings, long-break completion/running states, wrapped controls on a narrow timer card, and the default Focus layout were inspected in native offscreen renders. Live popover interaction and keyboard navigation remain unverified.

Growing support cards and task delete controls were inspected at 1710 × 1080, 1920 × 1400, 1000 × 872, 700 × 1700, and 680 × 650 content sizes. Timesheet remove controls and Undo were inspected at wide/default/minimum sizes. Live click/keyboard interaction remains unverified.

Audius integration verification on 2026-10-05: unsigned Debug and local ad hoc signed Debug builds passed; generated entitlements retain App Sandbox and include `com.apple.security.network.client`. The 47 music checks and 180 workspace regression checks passed. Live API discovery returned 29 accessible tracks, and a separate sandboxed native harness reached AVPlayer Playing, paused, and resumed at volume zero. This validates actual streaming and native playback state without testing audible output. Idle/playing/loading/error cards and default/wide/narrow workspace layouts were inspected in native offscreen renders. Live music-button/slider interaction, keyboard/VoiceOver, and audible sound remain unverified.

Daily-task verification on 2026-10-05: unsigned Debug build and 56 daily-task checks passed, including independent dates, past/future jumps, Today/midnight behavior, 23/25-hour DST navigation, leap/invalid dates, pinned civil dates across timezone changes, stable UUIDs, per-day completion/deletion, corrupt-load protection/Retry, and separate-process persistence. The existing 180 workspace and 47 music checks also passed. Native offscreen today/past/tomorrow/future-empty/load-error cards, date picker, narrow card, and default/wide/minimum window layouts were inspected. Live date-popover/input/keyboard/VoiceOver interaction remains unverified.

Settings verification on 2026-10-05: unsigned and local ad hoc signed Debug builds passed; the signed app retains sandbox/network/read-only access and adds app-scoped bookmarks. Passed 68 music, 63 preferences/wallpaper, 180 workspace, and 56 daily-task checks. Preferences include separate-process saving/reloading; wallpaper checks load real temporary images and restore a bookmark, exclude hidden/symlink files, stop or loop cycles, and handle a missing folder. A separate sandboxed harness resolved a real artist and playlist, fetched accessible tracks/artwork metadata, and verified native Play/Pause/Resume for both at zero volume. Native offscreen Settings at default/minimum widths, full settings content, dark Focus/Timesheet/Pomodoro settings, and solid/frosted music controls were inspected. Live folder-import/menu/keyboard/VoiceOver interaction and Liquid Glass onscreen compositing remain unverified; Liquid Glass does not render reliably in the offscreen bitmap harness.

Artwork-backdrop verification on 2026-10-05: unsigned Debug build, 74 preference/wallpaper checks, and 68 music checks passed. Shared remote image tests cover one fetch/decoded image across repeated window configuration, source/URL changes, invalid URLs/bytes, HTTP failures, canceled results, and pixel checks that confirm smooth color mixing across a sharp image boundary. Native offscreen default/wide/minimum, light/dark, all-tab, folder-artwork, and isolated color-wash renders were inspected; live window interaction remains unverified.

Calendar/Settings/glass refinement verification on 2026-10-05: unsigned Debug build, 68 daily-task checks, and 74 preferences/wallpaper checks passed. Added month-grid checks for Monday/Sunday alignment, leap days, month/year boundaries, and DST. Native default/wide/minimum Settings, full settings content, light/dark calendars, and solid/mid/clear music cards were inspected. An isolated live preview confirmed Settings centering, native material-menu selection, appearance switching, actual frosted blur versus sharp transparency, calendar selection, invalid typed-date blocking, and opening future/historical task dates. The preview used in-memory stores and did not change the user's saved data or play audio. Popover keyboard/VoiceOver and toggling the system Reduce Transparency setting remain unverified; the native UI tool closes the transient popover when sending a window-targeted key.

Dashboard verification on 2026-10-05: unsigned Debug build passed. Native offscreen Calendar layouts at 1000 × 900, 1710 × 1080, and 680 × 650, a dark Calendar, and populated Timesheet were inspected. An isolated live preview confirmed Timesheet / Calendar selection, shared week navigation and This week, state retention after visiting Focus, sample-detail opening/dismissal, zoom, and Timesheet editing with updated totals. Accessibility-tree inspection confirmed that inactive Dashboard views no longer expose their controls. Preview models used in-memory data; no user archives were changed and no audio was played. Full keyboard and VoiceOver interaction remain unverified. That historical Calendar draft was sample-only; D021 supersedes it with actual recorded sessions.

Session/controls verification on 2026-10-06: unsigned Debug build and 38 checked-in session-recording checks passed. Checks cover coalescing, captured tasks/projects, Flow priority, focus/break exclusion, pauses, delayed completion, midnight, 23/25-hour DST days, wall-clock jumps, manual totals without invented timestamps, running removal/Undo, legacy archives, reloads, and protected corrupt loads. An isolated in-memory native preview verified actual Flow time and updating session details in Calendar, task-name commit before Play, explicit inline editing without persistent highlight, default/minimum layouts, Appearance’s merged glass subsection, Light/Dark, thin transparent-track scrollbars, and the Habit tracker placeholder. An actual thumb drag changed glassiness from 45% to 73%; final styling retains native tracking and a larger bright thumb. Native UI tools intermittently rejected later drags with noWindowsAvailable; full VoiceOver remains unverified. No user archives were changed or real audio/network playback used.

Use previews or the running macOS app to verify appearance and interaction. Add focused tests when meaningful domain behavior is introduced, then document the actual test target and commands. Do not invent test or lint checks before they exist.

Provider/task verification on 2026-10-06: unsigned Debug build, 48 session-recording checks, 68 daily-task checks, and 17 silent music/preferences checks passed. Provider/volume were reloaded in a separate process; tests also cover legacy/corrupt archives, denied access/Retry, paused skips, replaced replies, and atomic task launches during recording/breaks. Isolated native previews verified provider switching, silent Apple transport/metadata, task assignment/Focus/both, Tab/Space/Return activation, default and compact Light/Dark layouts, and the fixed neutral action. A separately ad hoc signed sandboxed native harness read Music’s actual playback state with only the playback scripting group; it started no audio. Actual subscribed Apple Music playback/metadata and release signing remain unverified. Minimum-width shell layout was inspected, but pointer hover/scroll and lower narrow content were limited by intermittent UI-tool noWindowsAvailable errors; full VoiceOver remains unverified. No user archives were changed.

## 9. Maintaining this document

Update this document when new source understanding or implementation changes component responsibilities, view composition, state/data ownership, dependencies, build workflow, or important constraints. Replace stale descriptions, keep supporting paths accurate, and distinguish implemented behavior from proposals.

Put agent working rules in `AGENTS.md`, visual rules in `docs/style.md`, and the reason/history behind durable choices in `docs/decisions.md`. Avoid copying their detailed contents here. Product choices that remain unresolved belong in the ledger rather than being presented as settled architecture.


Artwork/favorites verification on 2026-10-06: unsigned Debug build and 240 temporary palette/contrast checks passed (30 project hues in both appearances, timer/panel contrast under saturated/bright/dark samples, transparent/grayscale images, and separated red/blue sampling). Native offscreen default/wide/minimum Focus, Settings, warm/cool artwork, and light/dark treatments were inspected. An isolated in-memory preview verified playlist playback intent with a silent adapter, heart save/unsave without stopping playback, retained drawer state, collapse, project selection, appearance switching, and a glassiness change from 45% to 90% reflected in the live artwork preview. Pointer dragging and full keyboard/VoiceOver remain unverified: the native UI tool intermittently reports unavailable windows/capture failures and does not reliably deliver drags. No user archives were changed and no audio/network playback was used for this verification.

Projects verification on 2026-10-06: unsigned Debug build, 28 checked-in project-catalog checks, and 48 session-recording regression checks passed. Catalog checks cover creation before time, duplicate names, selected/inactive deletion, concurrent timers, paused/resumed Flow, uncounted breaks, preserved history/Timesheet Undo, empty catalog reload, legacy archives, and protected invalid loads. Native offscreen screenshots inspected Light/Dark Projects, long names, empty state, and the three-tab time views at default 1000 × 900 and minimum 680 × 650 shell allocations. Live sheet/confirmation transitions, scrolling, keyboard operation, and VoiceOver remain unverified; no live user archives or audio were used.

System appearance verification: 2026-10-06 [TOOL] System appearance unsigned Debug build, 10 native offscreen appearance checks, and `git diff --check` passed. Checks cover Light/Dark overrides, Light → System and Dark → System, later native appearance changes, repeated transitions, and two windows sharing preferences. Persistent-window Settings screenshots inspected explicit Light and System Light/Dark at 1000 × 900 and System Dark at 680 × 650. Native changes were simulated through the isolated harness process’s application appearance; macOS settings, live user archives, and audio were untouched. Actual macOS automatic scheduled switching and live sheet/keyboard/VoiceOver interaction remain unverified.

Task suggestions and copy cleanup verification: 2026-10-06 [TOOL] Task suggestions/copy cleanup unsigned Debug build, 24 task-activity checks, 48 session-recording checks, 28 project-catalog checks, and `git diff --check` passed. Checks cover project-linked reuse, pin ordering/reload, blank/break exclusion, atomic task/project selection during concurrent timers, paused selection without autoplay, late-completion pin settlement, legacy session migration, deleted-project filtering, and corrupt-load protection. Native offscreen Light/Dark menu/search/long-title, default 1000 × 900 and narrow 680 × 650 Focus, full Settings, Pomodoro settings, and Calendar screenshots inspected. The installed native symbol lookup confirms waveform.mid exists. No live user archives or real audio were used; actual popover transitions, keyboard/VoiceOver, and pointer scrolling remain unverified.

Habit tracker verification on 2026-10-06: unsigned Debug build and 91 standalone habit checks passed, covering definition/goal/date validation, inclusive ranges, future blocking, check-in clearing, partial/exceeded targets, completion aggregation, observable UI invalidation, month rates, current/best streaks, leap/DST/week/year boundaries, Gregorian keys, corrupt-load protection/Retry, and separate-process persistence. Native offscreen screenshots inspected Light/Dark default 1000 × 900, narrow 680 × 650, and wide 1710 × 1080 layouts, monthly/weekly grids, empty/populated states, aligned full-width weekly rows, long-name stats, and creation/amount/end-date sheets. All twelve habit SF Symbols resolve in the installed native system. No live UI control, user archives, real audio, or network playback were used; actual sheet/menu transitions, keyboard navigation, pointer scrolling, VoiceOver, and release signing remain unverified.


Habit layout/frequency verification on 2026-10-06: unsigned Debug build and 130 standalone habit checks passed, including legacy daily archive migration, saved weekday frequency and separate-process reload, rest-day log rejection, scheduled-day rates/current/best streaks, DST, and complete 365/366-day annual grids (including a 54-column year). Native offscreen screenshots inspected Light/Dark at default 1000 × 900, narrow 680 × 650, and wide 1710 × 1080, plus full content, annual weekly bars, and amount/end-date creation with selected weekdays. The annual grid fits all twelve months at narrow widths; weekly rows remain compact and stats expand beside them or stack below. No live UI control or user archives were used. Keyboard navigation, VoiceOver, live sheet transitions, and release signing remain unverified.


2026-10-06 [TOOL] Habit/task refinement: unsigned Debug build, 130 habit checks, 68 daily-task checks, 47 habit/task integration checks, 24 task-activity checks, and git diff --check passed. Integration covers due dates/weekdays, shared check-in/amount completion, future blocking, independent manual tasks, observation invalidation, stable mixed-row identity, hidden occurrences, protected corrupt loads, separate-process relaunch, and Today/midnight timer eligibility. Native offscreen Light/Dark screenshots inspected default/narrow/wide Habit layouts, visible empty/disabled circles, themed creation/end-date controls and calendar, Today/past/future Tasks, flat pinned suggestions, and a single-completion weekly grid. Four programmatic mode-binding updates in an isolated native host completed layout in 47–78 ms (including a 10 ms yield), and rendered images confirmed both modes changed; 1,000 cached annual reads took about 3 ms. No live UI control, user archives, audio or network playback were used. Actual pointer/keyboard popover transitions, VoiceOver, and release signing remain unverified.
