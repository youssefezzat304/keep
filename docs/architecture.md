# Keep — Architecture

Keep is a native macOS focus workspace built with SwiftUI. This document describes the verified implementation and the boundaries to preserve as behavior is added. It is not a roadmap or a claim that the displayed features are functional.

## 1. Current implementation

Keep is one native macOS SwiftUI application. Focus, Dashboard, Habit tracker, and Settings work; the separate Stats destination is disabled. The implementation uses Apple frameworks and local UserDefaults archives, with no third-party packages, backend, accounts, or sync.

- Focus has independent Pomodoro and Flow timers, project/task selection, daily tasks, and music. Flow takes recording priority, so concurrent timers count time once. Breaks never add Pomodoro time.
- Dashboard contains an editable Timesheet, a weekly Calendar of actual recorded sessions, and a saved project catalog with add/delete. Manual totals cannot supply invented Calendar timestamps.
- Music streams public Audius tracks and controls the Mac’s Music app, including an in-Keep library browser/search, available artwork, transport, seeking, shuffle, and repeat. Provider/volume persist; playback and queues do not restore.
- Tasks persist by civil day and include scheduled habits with shared completion. Only Today’s rows can start Focus, Flow, or both. Project-linked suggestions and pins belong to the workspace, separately from daily lists.
- Habits save weekday schedules, inclusive date ranges, check-ins or minutes/times targets, manual progress, full-year activity, and derived stats.
- Settings saves Light/Dark/System, wallpaper/material preferences, and Audius sources. It exposes Music Automation permission status/recovery. Zen is a window-local full-screen wallpaper with minimal timer and music controls.

Projects, recorded sessions, daily totals/edits, tasks, habits, and preferences survive relaunch. Timers restart idle; active selection, committed task text, input drafts, and other window-local state are not restored. Live stores have no sample history; previews use isolated fixtures. Calendar editing, project renaming, habit definition editing/deletion, statistics, notifications, MusicKit catalog integration, and sync remain unimplemented.

## 2. Source map

All Swift files share the application module. `keep/` is a filesystem-synchronized Xcode group; add source files to their feature directory. Documentation, tests, and Git-ignored visual references sit outside it.

| Location | Responsibility / main entry points |
| --- | --- |
| `keep/App/` | KeepApp model assembly and WindowGroup; AppShellView tab/Zen composition; application-delegate termination flush; appearance and artwork backdrop |
| `keep/Models/` | WorkspaceModel coordinates timers, selected project/task, recording, ledger mutations and saving; FocusProject supplies catalog metadata |
| `keep/Features/FocusSession/` | FocusTimer/PomodoroSettings; window-local FocusTaskEditor; active target, timer/settings and support-card composition |
| `keep/Features/Timesheet/` | TimesheetLedger/Persistence, civil-day/duration helpers, editable weekly table; PreviewData fixtures only |
| `keep/Features/Dashboard/` | Shared browsed week/page, Calendar and Projects UI; RecordedSession value type |
| `keep/Features/Tasks/` | DailyTaskStore/Persistence, FocusTask, day navigation and calendar picker; due-habit projection |
| `keep/Features/Habits/` | HabitStore/Persistence, definitions/logs, cached activity and derived stats; tracker and creation/progress sheets |
| `keep/Features/Music/` | MusicPlayerModel; AudiusClient, AVMusicPlayback, serial AppleMusicController; library browser, artwork/wallpaper loading and rotation |
| `keep/Features/Settings/` | AppPreferences/SettingsPersistence and validated archive; settings UI/importer |
| `keep/Features/Zen/` | ZenModeModel, native-window bridge, compact timer readouts and music controls |
| `keep/DesignSystem/` | KeepTheme and named semantic assets, project/decoded-artwork palette helpers, reusable controls, scrolling and card styles |
| `keep/Assets.xcassets/` | Semantic Light/Dark colors, bundled artwork and app icon |
| `keep/keep.entitlements` | Read-only folder bookmarks, network and scoped Music automation |
| `tests/` | Standalone domain, appearance, music and native Zen checks; no Xcode test target |

Canonical context: `AGENTS.md` owns working agreements, `docs/decisions.md` owns decisions/history, and `docs/style.md` owns visual intent. Consult affected source before changing behavior.

## 3. Composition and lifetime

`KeepApp` assembles shared workspace, music, tasks, habits, preferences, and wallpapers and passes them to each AppShellView. Shells own tab and Zen presentation; Dashboard owns its page/week. Navigation stays outside the scrolling viewport. All tabs remain mounted; inactive content is invisible and excluded from input/accessibility, preserving drafts and scroll positions.

Focus composes ActiveTargetHeader, TimerWorkspaceCard and music/tasks. Its window-local task editor commits through WorkspaceModel before timer actions or leaving Focus. Dashboard supplies one week to Timesheet and Calendar; Projects has its own catalog viewport. Habits and Settings scroll within the same fixed shell.

## 4. Responsibility boundaries

Views present state and pass actions; WorkspaceModel alone settles and mutates recording. Timesheet owns ledger/storage types, Dashboard owns Calendar presentation, and neither has an independent recorder. Habits, tasks, music, preferences and wallpaper loading have separate app-owned models and archives. Zen changes presentation only.

Shared controls receive caller actions and remain free of feature state, persistence, and provider calls. Feature directories own feature-specific UI/logic; DesignSystem owns reusable appearance. There is no separate MVVM/service-container/package architecture. Introduce a shared abstraction only for a concrete implemented need; preserve native SwiftUI and existing Apple frameworks.

## 5. State and data ownership

`KeepApp` creates one `@State` reference to the observable, main-actor `WorkspaceModel` and passes it into every window. It owns two `FocusTimer` values, the selected project, the ledger with daily totals and timestamped sessions, committed task text, and one update task. Shells own tab selection; each Dashboard owns its page selection and week offset, and its Calendar owns zoom/scroll/recorded-detail state. FocusSessionView owns an explicit task editor draft model, and each TasksCard owns its day selection/input drafts. Previews construct models without persistence and cannot write live history.

`FocusTimer` is a value type using `ContinuousClock.Instant` plus accumulated elapsed seconds. Timer display refreshes are separate from timing truth. The workspace accepts injected clock instants and dates for deterministic checks.

Implemented timer and recording semantics:

- Pomodoro defaults to 25-minute focus, 5-minute short breaks, 15-minute long breaks, and a long break after four completed focus intervals. Valid ranges are focus 1–180 minutes, short break 1–60, long break 1–120, and iterations 1–12.
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

Calendar presents a weekly 24-hour grid of actual sessions, project-colored blocks, overlap lanes, zoom, and read-only details that update during recording. Empty weeks have no sample blocks. Existing daily totals and manual edits cannot reconstruct timestamps and therefore remain in Timesheet only; Calendar’s session total can differ from an edited daily total. There is no Calendar editing, drag-and-drop, or connection to saved daily tasks.

`TimesheetTimeCell` opens a native `TimesheetEntryEditor` popover. The editor accepts nonnegative `h:mm` or `h:mm:ss`; blank sets the cell to zero. Invalid input stays in the editor with an explanation. Saving replaces the cell total after settling the running timer; later elapsed time adds to the edited value. A zero cell retains its project row. Timesheet edits project/day aggregates; they do not rewrite the separately recorded session timestamps or task metadata.

The trailing × removes a project's entries and recorded sessions for the displayed week through `WorkspaceModel.removeTimesheetProject`. It settles recording before removal and saves immediately, preserving other projects, other weeks, catalog metadata, selection, and timer state. A running timer can create the row again with subsequent time. The model keeps one in-memory `TimesheetRemoval` for Undo across tabs/windows; Undo settles again and adds back removed time and sessions alongside newly recorded/edited values, then saves. Subsequent running time uses a new recording ID, so Undo cannot merge it into deleted history. Undo history is not restored after quitting. `TimesheetView` shows the removal/Undo notice and explains continued recording when applicable.

`TimesheetPersistence` JSON-encodes the ledger, custom catalog, optional `PomodoroSettings`, actual sessions, and `taskActivities` into the app’s standard `UserDefaults` under `keep.timesheet.v1`. Older records without the added fields load with an empty custom catalog/session array and default timer settings, retaining their entries. Session validation checks IDs, finite ordered dates, civil-day boundaries, timezone, and task length; malformed records preserve the archive and block edits. It loads on app model creation, saves about every five seconds during recording, and saves immediately after actions/edits/creation/settings changes. `WorkspaceApplicationDelegate` flushes the last partial interval on normal app termination, including when no windows remain. Abrupt termination can lose time since the last checkpoint save. Corrupt saved data, including invalid settings, blocks mutations and shows Retry rather than overwriting unreadable records. Timer runtime, current task text, inline/input drafts, and project selection are not restored. Daily task lists use their own persistence below.

`DashboardProjectsView` presents an alphabetically sorted, scrollable catalog with project-colored folders/names, row delete controls, and a fixed Add project footer. It owns creation-sheet and native deletion-confirmation presentation. Adding uses the shared dialog without changing selection or inventing time. Deletion routes through `WorkspaceModel.deleteProject`: settle elapsed recording, persist the removed ID, and switch a deleted active selection to No project. Timer phases and committed task text are preserved; future running time is unassigned. Deleting an inactive project leaves the current session context intact. Timesheet/Calendar retain historical metadata and time, and Timesheet removal/Undo does not restore a deleted catalog project. Projects hides week controls and shows a project count; switching Dashboard pages retains the browsed week.

`ActiveTargetHeader` and `TimesheetView` own picker and creation-sheet presentation. The target border stays neutral; clicking task text opens `TaskSuggestionPicker`. `FocusTaskEditor` owns its window-local name/search draft; typing never changes recording. Return, dismissal, leaving Focus, or a timer action commits through the workspace; Escape cancels, while picking a saved row discards the draft and atomically selects that task/project without starting timers. The menu searches task/project names and presents one flat list directly beneath the input, with inline project-colored folder/name labels and pin controls. Pinned tasks stay first; there are no separate pinned/recent sections or inset suggestion cards. Selecting a project never forces the task field into focus. `ProjectPicker` owns transient search/hover/focus state and searches the shared catalog by name. Its Create action closes the popover and opens `ProjectCreationDialog`, which owns only draft name/color/error state. Cancel discards creation drafts. `WorkspaceModel.createProject` trims names, requires 1–80 characters, rejects case/diacritic-insensitive duplicate names and invalid colors, assigns a UUID, and saves the catalog without inventing time entries. Focus selects the created project without automatically opening or selecting task text; Timesheet adds it to the displayed week without changing the active timer project. `DesignSystem/FocusProjectStyle.swift` maps Codable project accents to named color assets; the neutral accent is reserved for unassigned time. `TimesheetPreviewData` supplies numeric sample data exclusively for previews.

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

`AppleMusicLibraryView` opens a 620 × 720 sheet without changing the music card’s allocation. The shell supplies its viewport through the environment; the sheet clamps to viewport width minus 48 and height minus 64 (620 × 586 at the minimum window). Each sheet owns its search/selection/paging and an `AppleMusicLibraryModel`, sharing only the player’s serial controller. Songs and playlists load in 50-item pages; search is debounced 350 ms. Search reads names/IDs and song artists/albums in bulk, then filters locally with case/diacritic-insensitive matching and returns a page. Metadata reads happen on the serial actor and check cancellation between calls and while filtering. Music’s native search command returns -10004 under the read-only sandbox grant on this installation, so Keep does not use it or expand to library-write access. The controller bounds search text to 200 characters and follows `source 1 → library playlist 1` for songs and the source’s user playlists for playlist browsing, matching Music’s exposed element hierarchy. Music accepts song ranges but rejects playlist range reads (-1708), so playlists use indexed object references. Native absolute ordinals use the correct descriptor type and Foundation’s host representation. Runtime native IDs include the playlist context when needed and never enter an archive; selecting a song plays its native object, and a playlist can be opened or explicitly played. Request generations and sheet task cancellation fence old results; failed reads offer Open Music/Retry, and empty libraries/results are explicit. Browse never starts playback; it observes the current Music selection and starts the shared status refresh without claiming ownership of already-playing audio. Playback Retry retains the failed library selection.

The app-owned one-second refresh reads actual state, title/artist, stable track identity, position/duration, shuffle, and repeat. Native current-track artwork is cached when available, bounded to 12 MiB, and forwarded to the shared wallpaper decoder. Missing/delayed covers retry after two seconds for the first few attempts, then every 15 seconds; changing identity resets that retry schedule. Missing artwork does not stop audio. The sheet shows available cover art even with a custom wallpaper and exposes play/pause, previous/next, volume/mute, seeking, shuffle, and repeat off/all/one. Selecting Track artwork in Settings uses the same cover for the card/backdrop/palette. Play first applies Keep’s saved volume; skips retain paused intent. Transient Music read failures retain the status observer. An eight-second recovery grace shows Loading with a native spinner, preserving play intent and current metadata instead of flashing Retry; status reads stay at one-second intervals during grace, then back off to 15 seconds. A Play response that is still stopped/paused also remains Loading until playback starts or grace expires. Persistent failures show the real error, while permission denials bypass grace; a read failure immediately after a native command also starts observation. A later status restores metadata/artwork without another Play. Permission failures stop the observer instead of repeatedly asking for consent. All native commands remain off the main actor, with cancellation and generation fences. Playback continues across tabs/windows. Provider switching and quitting pause only an engaged Music session; termination awaits the bounded release event. Music’s account, subscription, local library, and cloud availability determine which items can play.

`MusicPlayerModel` owns runtime `AppleMusicAccess` state independently of preference persistence. Settings shows a Permissions section even when invalid preferences block edits. Opening the visible Settings tab or returning from System Settings checks access only if Music is already running. The controller probes actual playback-state and library-count events with `kAEDoNotPromptForUserConsent`, distinguishing unrequested and denied access without wildcard permission preflights. Explicit Allow Music access launches Music if needed and permits the normal macOS prompt; it never plays, changes provider, or applies volume. Denied access links to Privacy & Security → Automation, and a recovered grant reconnects status observation for the selected Apple provider. Hidden mounted Settings must not initiate probes. Permission status is not archived. SDK behavior was checked against installed AppleEvents declarations and [Apple’s Automation guidance](https://support.apple.com/en-hk/guide/mac-help/mchl108e1718/mac) on 2026-10-06.

Full streaming-catalog search, recommendations, and library modification are outside this bridge. Apple’s native MusicKit catalog support requires enabling the MusicKit App Service for Keep’s matching App ID and development team; see [automatic token generation](https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api). No private key or developer token is embedded, and no remote developer-account settings are changed.

Settings and wallpaper ownership:

- `KeepApp` owns one `AppPreferences` and one `WallpaperLibrary`, shared across windows independently of timer/task stores. Settings selection uses the same mounted viewport as Focus and Dashboard. Its title and sections share a horizontally centered column capped at 900 points; rows can stack at narrow widths. Shared `KeepControls` supplies rounded paper buttons/inputs and native menus with hover/focus/disabled states; appearance uses explicit selected buttons. Appearance includes Dark mode and an “A little glass” subsection. Its continuous native SwiftUI Slider is the same control used for music volume, with a 44-point control area and theme tint. The subsection includes a live player preview sharing the same model and artwork, so adjustments are visible immediately without changing tabs. Default appearance remains Light; System resolves the native application’s `effectiveAppearance` through the observable `SystemAppearance` KVO adapter in `App/KeepAppearance.swift`; `keepAppearance` gives the shell and Music library sheet an explicit Light/Dark preference. Window overrides do not become the source for System. Native changes update the SwiftUI content across windows without recreating views or losing drafts. Sheets/popovers inherit the selected appearance. Named assets define dark variants.
- `SettingsPersistence` stores a validated Codable archive in `keep.preferences.v1`: appearance, wallpaper source, read-only folder bookmark/display name, order/interval/automatic rotation/loop, material/glassiness, saved channel metadata, and selected channel ID. Updates save immediately; invalid loads disable editing and preserve the original data with Retry. No signed audio URLs or image bytes enter this archive. Provider and volume persist through optional validated archive fields; playback/queue and drafts remain runtime-only.
- Native `fileImporter` chooses a folder. `WallpaperLibrary` creates/resolves app-scoped read-only security bookmarks, refreshes stale bookmarks, and balances scoped access. Folder scans and ImageIO thumbnail decoding run off the main actor, skip hidden files/symlinks/subfolders, and bound thumbnails to 2048 pixels. Cancellation and generation checks reject stale folder/image results. Missing folders, empty lists, or unreadable images show actionable Settings errors and retain the bundled visual fallback.
- The app owns a single rotation task regardless of the number of windows. Folder rotation defaults to automatic, sequential, every minute, and looping. Intervals are 30 seconds, 1, 5, or 15 minutes. Shuffle visits each image once per cycle and avoids an immediate repeat between cycles. Turning looping off stops on the final image; manual Next can begin another cycle. Changing configuration cancels/restarts the applicable load/rotation; shutdown cancels both tasks.
- Wallpaper sources are bundled Cozy corner, My folder, and Track artwork (Audius or Apple Music). The persisted `audius` raw value is retained for backward compatibility. `MusicTrack` carries validated HTTPS artwork and optional artist-channel metadata; `WallpaperLibrary` fetches the current track artwork only when that source is selected, using an ephemeral URLSession with a 20-second timeout. It validates HTTPS URLs/statuses, rejects responses over 12 MiB, and decodes 2048-pixel thumbnails off the main actor with cancellation/generation checks. One decoded NSImage is shared across all windows; missing/failed artwork falls back to Cozy corner on both surfaces. Native artwork bytes use the same off-main ImageIO thumbnail/wash/palette pipeline. One cached native cover serves the library sheet and, when selected, the card/backdrop without duplicate decoding; native and folder load tasks are independently canceled/fenced. Artwork advances with tracks; folder rotation options apply only to folder images.
- The player’s passive channel menu lists saved artists/playlists plus All lofi. The heart saves/unsaves the selected artist/playlist, or the current track’s artist when browsing All lofi. Its outline/filled state comes from the existing preferences archive; unsaving here does not stop playback. A separate saved-list button expands the bottom controls upward with a 250 ms animation (no motion when Reduce Motion is enabled). The drawer is local to each card, remains open through channel playback/track changes, and collapses only when toggled. Clicking a saved row explicitly starts/resumes that source; repeated clicks on an already playing source do not restart it. Opening favorites does not change the card’s 288-point minimum or its allocated size. A vertically bounded `ViewThatFits` shows the list above transport controls when both fit; otherwise the list replaces the track/transport area and puts the heart/toggle in its heading. Playback continues while controls are hidden. Only the saved-list area scrolls; toggling never adds outer Focus scroll overflow. Audius attribution sits at the top-left of the artwork. A provider menu retains passive Audius source selection. The Focus music card also opens Zen.
- Settings resolves pasted HTTPS Audius links via `/v1/resolve`, accepts only public artist/playlist resources, deduplicates by kind/resource ID, and offers Play/removal. Playback loads `/users/{id}/tracks` or `/playlists/{id}/tracks` through the existing access filters and native player. Source changes release the old queue/item and fence canceled callbacks. Choosing through the passive source menu never autoplays; Settings Play and saved-drawer rows explicitly start/resume it. The selected saved source reopens without networking/autoplay; removing it through Settings returns to All lofi.
- `MusicGlassPanel` uses an explicitly aligned copy of the player artwork behind the transport, cropped to the controls’ rounded bounds. It receives the full artwork size/inset so the crop remains aligned as the card grows. Glassiness continuously reduces artwork blur (24 points to zero) and paper opacity (one to zero), with a permanent appearance-specific readability wash (stronger in Dark to protect cream text over bright artwork). At zero and with Reduce Transparency it uses opaque paper. Frosted uses this artwork-backed treatment; Liquid Glass adds native `glassEffect(.clear)` so a more opaque native material cannot substitute the outer window’s colors for the player image. Glassiness never changes playback or the outer backdrop. Settings binds the standard SwiftUI Slider directly to AppPreferences.glassiness, retaining persistence, percentage feedback, native tracking, and corrupt-load edit protection. Decorative shell, section, and glass borders opt out of hit testing so they cannot intercept control input.

Further providers and notifications remain separately scoped work. See `docs/decisions.md`.

### Habits

`KeepApp` owns one main-actor observable `HabitStore` shared across windows, independently of workspace recording, daily tasks, and music. `HabitPersistence` validates and saves the complete `HabitArchive` in UserDefaults under `keep.habits.v1` after each mutation. Definitions persist before their first log. Stable UUIDs identify habits; logs are unique by habit/day. The archive rejects invalid goals/date ranges/frequencies, duplicate identities/logs, orphan or rest-day logs, and invalid amounts. A failed load preserves the saved bytes and blocks changes until Retry succeeds; failed saves retain in-memory changes and offer Retry. Live storage starts empty; verification fixtures are in-memory only.

A habit has a trimmed 1–80-character name, a selected habit icon, a start date, optional inclusive end date, and a goal: **Daily check-in** (0/1) or **Daily target** (positive minutes/times per day). Seven selectable weekday circles set the frequency; all days are selected initially, at least one is required, and older archives without weekdays remain daily. Targets allow 1–1,440 minutes or 1–10,000 times. An amount log stores a nonnegative integer up to 1,000,000; zero removes the log, a partial amount does not count complete, and meeting/exceeding the goal counts the habit once on that day. Editing progress is manual and allowed only on scheduled dates through today. Nothing automatically completes a habit from elapsed timer time. Explicitly checking its projected daily task updates the same habit log.

Habit dates reuse `TaskDay`'s Gregorian civil keys, with the local calendar/timezone and Monday-first weeks. Calendar arithmetic handles DST, leap days, and month/year boundaries. Saved keys stay on their original civil day after a timezone change. Formatting uses the same calendar/timezone as the keys. Browsed week/day, activity mode, selected habit, stats month, and sheet drafts are window-local; following Today updates across midnight through the existing workspace display refresh. No second ticker or recorder is introduced.

Activity shows the full current year in Monday-first week columns. Monthly daily intensity counts completed habits (0/1/2/3/4+); Weekly fills one square per completed goal, capped at seven with exact total labels. Adjacent-year dates are hidden and future dates disabled. Choosing a past/current tile navigates weekly progress. Activity, progress and selected-habit stats share one surface; progress fits seven days and stats stack below on narrow windows. Check-ins toggle directly; amount goals open a numeric sheet with a target shortcut and zero-to-clear. The fixed shell viewport scrolls vertically.

Stats derive from the saved logs, with no stored totals. A runtime habit/day query index is rebuilt on loading and updated with log changes so every visible cell does not rescan the complete history; the index is not persisted. Month completion rate uses scheduled days through today, excluding future days and dates outside the habit range. Lifetime totals count completed days, including previous months. Current/best streaks count consecutive scheduled check-ins, skipping rest days. While today is a rest day or its goal is pending, current streak can end at the latest previous scheduled date; a missed due day breaks it. After the habit end date, current streak is zero while best streak retains history. Weekday matching uses the Gregorian civil key rather than a timezone-dependent instant. The stats calendar can correct prior daily progress; its month totals/rate follow the browsed month while current/best streaks remain as of today. Definition editing/deletion, reminders, recurrence rules beyond weekday selection, and sync remain outside this implementation.

`HabitActivitySnapshot` prepares annual civil dates, labels and exact daily/weekly counts from validated logs. HabitStore caches it by civil day/timezone/locale and invalidates it on definition/log changes or Retry. Monthly/Weekly selection reuses the snapshot instead of recalculating and formatting a year in the view body; accent contrast and tile size resolve once per body. The grouped mode switch follows Dashboard styling. HabitDateField reuses the styled TaskDatePicker calendar (with a Choose date confirmation), and KeepCheckboxStyle supplies the theme-consistent end-date/task checkbox. Empty habit circles retain visible outlines even when future/rest days are disabled.


## 6. Artwork, appearance and layout

Visual intent and tokens live in `docs/style.md`; named color assets are authoritative and KeepTheme references them. System appearance observes the native application's effective appearance, independently of explicit window overrides. Popovers/sheets inherit the shell selection. Artwork changes must preserve mounted content, drafts and geometry.

One WallpaperLibrary delivers the decoded image, blurred texture and runtime palette across windows. It prepares a small clamped-edge Core Image wash off the main actor rather than applying window-sized blur. MusicArtworkView shares the selected image/fallback between the player and backdrop. ArtworkPaletteSampler downsamples the existing decode, deriving ambient/supporting colors without additional fetches, per-view scans or saved palette state. Transparent images yield no palette; grayscale uses its average. Existing generation/cancellation fences apply to all outputs. KeepTheme blends artwork into opaque panel/timer bases with contrast limits; project accents retain hue while adjusting lightness for readable Light/Dark labels. Bundled artwork provenance is in `docs/music-artwork.md`.

ZenModeModel is window-local with inactive/entering/active/leaving phases. Focus commits its draft before entering. ZenWindowBridge reads its owning NSWindow through a noninteractive view and observes entry/exit/close without replacing SwiftUI's delegate. Enter native full screen only if needed, wait for pending entry before a rapid Exit, leave Zen on native exit, and preserve pre-existing full screen on Exit Zen. The normal shell stays mounted but hidden from input/accessibility. Zen reuses the shared wallpaper, workspace and player; no state is copied/restarted or persisted by the mode. Its wallpaper has small white music controls at bottom-left and timer readouts at bottom-right, stacked at narrow widths, with a subtle bottom readability fade. Reset/break actions are in timer context menus. Exit and Escape remain available; library sheets use the shared player and viewport.

Layout constraints:

- Default 1000 × 900; minimum 680 × 650; verify wide 1710 × 1080 as well. The panel has 16-point outer margins and 24-point inner padding, independent of selected tab/content length.
- Below 900 points navigation uses labeled/tooltipped icons. Below 820, normal Focus timer/support pairs stack. Tables/Calendar keep a 900-point minimum and scroll horizontally; other long content scrolls within the shell.
- Focus receives its available viewport as minimum height. Music/tasks have 288-point minimums and fill remaining space in taller windows; short windows scroll. Task lists and music favorites scroll internally without changing outer geometry.
- KeepScrollView preserves native overlay scrolling with thin, transparent tracks. CardStyle adds padding/rounding, not fixed maximum height. Timer digits have stable widths and explicit phase labels.
- Inputs/actions expose labels, visible focus and native shortcuts. Reflow completed-focus controls instead of clipping them. Decorative overlays never intercept input.
- MusicGlassPanel aligns a crop of the actual card artwork beneath its controls. Glassiness reduces blur/paper opacity, retains a readability wash, and uses solid paper at zero or under Reduce Transparency. Liquid Glass adds the native treatment; Settings uses the same native Slider as volume.

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
| Music automation | `com.apple.Music.playback` and `com.apple.Music.library.read` scripting targets, Apple-events automation entitlement, and usage description in Debug/Release |
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

Run Zen transition and native attachment/notification checks in hidden windows without changing Spaces:

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  keep/Features/Zen/Models/ZenModeModel.swift \
  keep/Features/Zen/Views/ZenWindowBridge.swift tests/ZenModeChecks.swift \
  -o /tmp/keep-zen-checks
/tmp/keep-zen-checks
```

Run the silent music/preferences checks:

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  $(rg --files keep -g '*.swift' | rg -v 'KeepApp.swift') \
  tests/MusicPreferencesChecks.swift -o /tmp/keep-music-preferences-checks
/tmp/keep-music-preferences-checks
```

All checked-in check sources live in `tests/`; choose the matching command above. Older temporary harnesses have been removed, so historical receipts do not imply their source/commands are available today.

Verification history belongs in `docs/decisions.md` under RECEIPTS. The latest work has unsigned builds, focused standalone checks, and native offscreen screenshots; this does not establish release signing, actual Automation consent/subscribed playback, live full-screen animation, native slider dragging, complete keyboard/VoiceOver operation, or onscreen Liquid Glass compositing. Use isolated fixtures for UI checks and silent playback adapters for music. Never treat a historical command outcome as a current run.

## 9. Maintaining this document

Update responsibilities, ownership, dependencies, build workflow and verified constraints when source changes. Keep current behavior distinct from future scope. Agent rules belong in AGENTS.md, visual intent in style.md, and decisions/history/verification receipts in decisions.md. Avoid duplicate histories, icon inventories, or incidental styling details here.
