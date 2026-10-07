# Keep — Decisions and Continuity

## [SNAPSHOT]

- 2026-10-07 [CODE] Sparkle 2.10 is integrated for Release update checks with Settings/application-menu controls, a six-hour schedule, signed feeds/archives, sandbox installer support and timer-aware restart settlement. Debug updates stay disabled. Public feed targets GitHub releases; no release/feed has been published. See D049 and `docs/updates.md`.

- 2026-10-07 [CODE] Stats is active with recorded focus charts, project/task filters, custom dates, completion history, date-scoped task/habit summaries, always-visible streaks and optional all-project weekly goals. Completed Pomodoros use the finishing target; old history is never estimated.

- 2026-10-05 [CODE] Goal: native macOS focus workspace; existing UI includes an active target, Pomodoro and flow panels, and task/music areas.
- 2026-10-07 [CODE] The leaf menu panel shares both timers, today's task/habit checkboxes, selected-provider playback/volume and a sliding project/recent-task/name picker. Its fixed main page keeps timer/music controls visible, with internal task/picker scrolling. Start both / Stop both works in the menu and main app. It follows Keep appearance with default timer colors. Settings saves visibility/status timer choice and offers native Start on login. Habit information supports name/icon editing with all other definition fields locked. Recording/playback continue after closing workspace windows.
- 2026-10-06 [CODE] Current state: Dashboard contains the saved editable Timesheet, a weekly Calendar with session time editing/deletion, and a Projects catalog with add/delete; mock sessions are removed. Focus records project time into an editable seven-day Timesheet with locally saved totals and weekly row removal/Undo. Flow takes recording priority; Pomodoro has saved duration/iteration settings and manual uncounted short/long breaks. Support cards fill taller windows; tasks have saved per-day lists with date navigation and completion/add/delete controls. Music streams public Audius lofi/saved sources through AVPlayer and controls Apple Music via the Mac’s Music app with an in-Keep library browser/search, current artwork, seeking/shuffle/repeat; provider and volume persist. Today’s task rows launch Focus, Flow, or both with a shared active title; the task selector remembers project-linked activity and pins. Zen fills native full screen with the selected wallpaper, minimal timer readouts and a small music bar, preserving their runtime state. Settings manages Music Automation access and saves Light/Dark/System appearance, folder/track wallpapers, rotation, glassiness, and artist/playlist channels. The outer background is a blurred wash of the player’s artwork; the panel/timers take contrast-limited artwork tints. Music has a heart toggle and an animated saved-source drawer; project names/icons share readable project hues. Appearance includes the glass subsection and a native glassiness slider below its live preview and material picker; music volume retains its slider. Compact navigation uses icons, scrollbars share thin transparent tracks, and Habit tracker saves goals/progress with weekday frequency, a centered full-year monthly/weekly activity grid, compact weekly check-ins, and selected-habit stats on one surface; due habits also appear in daily Tasks with shared completion.
- 2026-10-05 [USER] Documentation lives in `docs/architecture.md`, `docs/decisions.md`, and `docs/style.md`; root `AGENTS.md` defines working rules.
- 2026-10-05 [USER] Keep agent guidance and architecture clearer as understanding of the project improves.
- 2026-10-05 [CODE] Created projects, project/day totals, and edits persist in local preferences. A shared creation dialog offers a name and 30 colors. Music supports public Audius streaming and scoped playback control of the Mac’s Music app; Sparkle is now the first third-party package, and there is no Xcode test target. Daily-task and session-recording standalone checks are checked in; earlier timer/workspace check sources have been removed; new silent music/preferences checks are checked in.
- 2026-10-06 [USER] Visual direction: cozy palette and quiet layouts, with lighter, friendly rounded headings replacing the earlier formal serif direction (D040).
- 2026-10-05 [CODE] Timers/project selection/ledger, music, saved daily tasks, and habits are app-shared; appearance/music preferences and channel selection persist; provider/volume restore without autoplay; timer/music runtime, committed task text, task-day selection, and window-local editor/input drafts are not restored on relaunch. Recorded session metadata persists with daily totals. Stats is implemented under D044; export remains excluded.

## [DECISIONS]

### D001 ACTIVE — 2026-10-05 [USER]

Keep documentation in the existing lowercase `docs/` files and refine root `AGENTS.md` and `docs/architecture.md` as project understanding improves.

Ownership: agent rules in `AGENTS.md`, implemented structure and constraints in architecture, durable context here, and visual language in style. Avoid duplicate root-level or uppercase alternatives.

### D002 ACTIVE — 2026-10-05 [USER]

Provide two independently playable/stoppable timers: Pomodoro and flow. They may run concurrently; actions on one must not change the other.

### D003 PARTIALLY SUPERSEDED BY D008 — 2026-10-05 [CODE]

For the first draft, Stop preserves time, Continue resumes it, and Reset starts fresh. Pomodoro uses 25 minutes; flow has no time limit. Timing uses `ContinuousClock`, including sleep, with state local to each window. No persistence or automatic break cycles are introduced.

### D004 PARTIALLY SUPERSEDED BY D013 — 2026-10-05 [USER]

The music area previews later lofi/ambient playback with cozy artwork and controls floating on a blurry card. This panel is an exception to the flat visual language; actual audio remains out of scope.

### D005 PARTIALLY SUPERSEDED BY D013 AND D015 — 2026-10-05 [CODE]

Use explicit light appearance for the first palette implementation. Keep Stats, Settings, and music playback controls disabled rather than implying unfinished functionality works.

### D006 SUPERSEDED BY D008 AND D018 — 2026-10-05 [USER]

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

### D012 PARTIALLY SUPERSEDED BY D014 — 2026-10-05 [USER]

Extend the music and tasks cards to the bottom on larger/full-screen windows. Make tasks deletable and add an × to remove Timesheet rows, matching the reference.

2026-10-05 [CODE] Support cards grow from a 288-point minimum to fill the space above the footer, with scrolling for short windows. Task × buttons remove window-local drafts. Timesheet × buttons remove the project's entries in the displayed week after settling recording, save immediately, and offer one-step Undo. Catalog projects and other weeks remain intact. Timers continue recording subsequent time; Undo adds removed history back alongside that new time. Undo history lasts for the current app run.

### D013 PARTIALLY SUPERSEDED BY D022 — 2026-10-05 [USER]

Integrate Audius lofi music through native Apple AVPlayer, with play/pause, volume, loading, and connection-error states. D004's cozy artwork/frosted controls and D005's light palette remain; disabled music playback is superseded.

2026-10-05 [CODE] One app-owned music model shares playback across tabs/windows independently of timers. Play discovers public, accessible lofi tracks and resolves temporary signed HTTPS streams without credentials; no startup autoplay/network call. Previous/next and track completion navigate/wrap the queue while retaining paused intent. UI displays title/artist and Audius attribution, volume/mute, actual playing/buffering, and actionable Retry. Unavailable stream lookups skip stale metadata within a bounded queue. Generation checks, cancellation, timeouts, and termination cleanup protect playback lifecycle. Sandbox outgoing network access is enabled in both build configurations; no microphone access or external SDK is added. Queue, playback, and volume remain runtime-only.

### D014 ACTIVE — 2026-10-05 [USER]

Allow reviewing tasks for past/specific days and navigating forward to plan tasks beforehand.

2026-10-05 [CODE] Added previous/next day arrows, a native date-picker popover, and Today. Lists/completion states are independent by civil day and saved locally in `keep.tasks.v1` through one app-owned DailyTaskStore. Each window owns its selected day and unfinished input per day. Today follows midnight; browsed dates remain pinned, and calendar arithmetic handles DST. Task mutations capture the rendered day and stable ID; deleting/checking cannot affect another date. Live lists start empty; prototype examples are preview-only. Invalid saved tasks block edits and offer Retry without overwriting data. This supersedes D012's window-local task-list lifetime; task × controls and growing cards remain.

### D015 ACTIVE — 2026-10-05 [USER]

Activate Settings with Light/Dark/System appearance; select a wallpaper folder, configure wallpaper looping, display Audius artwork, and control music-card glassiness. Save Audius channels for quick access, supporting both artist profiles and playlists.

2026-10-05 [CODE] A separate app-owned validated `keep.preferences.v1` archive saves appearance, wallpaper/material preferences, read-only folder bookmarks, channels, and selected source. Semantic asset dark variants and inherited popover appearance replace the forced light shell. One app-owned wallpaper library scans/decodes off the main actor and rotates sequentially or without-repeat shuffle at 30 seconds/1/5/15 minutes; automatic rotation and looping can be disabled, and manual Next can restart a cycle. Bundled artwork remains the fallback. The current track’s HTTPS Audius artwork changes with tracks. Frosted/native Liquid Glass controls map glassiness to material/tint; Reduce Transparency forces solid paper. Settings resolves public Audius profile/playlist links; the player menu recalls saved sources and saves the current artist. Selection/restoration never autoplays; explicit Play uses the chosen source. Corrupt preference loads protect existing data and offer Retry. Debug/Release add app-scoped bookmarks while retaining sandbox/read-only/network capabilities. D005’s forced light appearance/disabled Settings are superseded; Stats remains disabled.

### D016 ACTIVE — 2026-10-05 [USER]

Replace the solid background behind the main panel with the music player’s artwork, very blurred like a gradient so the window takes on its colors.

2026-10-05 [CODE] `MusicArtworkView` supplies the same decoded folder/Audius image or CozyCorner fallback to the player and shell backdrop. The app-owned wallpaper library now also fetches/decodes remote artwork once, with timeout/validation/cancellation checks; images remain runtime-only. `ArtworkWash` produces a heavily Gaussian-blurred 64-pixel texture off the main actor with clamped edges. `ArtworkBackdrop` smoothly fills the window with it and adds light/dark washes. It is noninteractive and present behind all tabs without changing panel size/margins or content identity. The opaque main panel retains semantic colors. This supersedes D015’s use of per-card AsyncImage for remote artwork; artwork-source settings remain unchanged.

### D017 ACTIVE — 2026-10-05 [USER]

Restyle the task date picker and Settings controls to match Keep, center Settings, and fix Glassiness so it makes the player controls clearer and more transparent rather than emphasizing the outer backdrop.

2026-10-05 [CODE] Settings now shares a centered 900-point column, rounded paper menu buttons/inputs, selected appearance buttons, native switches, and a live player preview in the glass section. The calendar uses styled SwiftUI date buttons in a native popover, month arrows, a Today dot/action, and a validated YYYY-MM-DD jump field. Calendar arithmetic respects the first weekday, leap dates, and DST; day buttons support arrow focus navigation. `MusicGlassPanel` aligns an explicit copy of the player image with the transport and continuously reduces blur/paper opacity toward clear; an appearance-specific wash protects legibility, and Reduce Transparency stays opaque. Liquid Glass uses the clear native finish. This supersedes D014’s default graphical DatePicker and D015’s material-thickness/tint mapping; saved settings and task-day behavior remain unchanged.

### D018 PARTIALLY SUPERSEDED BY D021 — 2026-10-05 [USER]

Rename the top-level Timesheet tab to Dashboard, add a Timesheet / Calendar switch, and build a weekly Calendar in Keep’s cozy style. Both views live inside Dashboard. The user chose a visual draft with sample sessions rather than adding session recording.

2026-10-05 [CODE] Dashboard owns shared week navigation and mounted Timesheet/Calendar viewports. Timesheet retains saved daily totals, edits, project creation, removal, and Undo. Calendar displays a labeled sample week with seven weekday/date headers, sample daily/week totals, a scrollable 24-hour grid, project-colored task blocks, hour zoom, and read-only sample details. The weekday sample pattern repeats when browsing weeks and never enters the ledger. Real session timestamps, calendar editing, and timer/calendar integration remain outside this scope. This supersedes D006’s exclusion of Calendar as a navigation alternative; the recorded ledger remains aggregate-only.

### D019 ACTIVE — 2026-10-06 [USER]

Tint the timers and main panel from the background artwork, respecting Dark mode; fix the glassiness slider’s pointer tracking. Add outline/filled music hearts and an animated saved artist/playlist list inside the music card. Selecting a saved source starts playback without closing the list. Match the folder icon and project names to the selected project color.

2026-10-06 [CODE] The existing decoded-image pipeline now supplies a runtime sRGB palette; the shell and timers blend its colors into appearance-aware semantic bases with text-contrast limits. Project labels/icons adjust lightness while preserving their hue. A continuous NSSlider bridge and noninteractive decorative borders replace the glassiness control’s previous interaction path. Hearts use the existing saved-channel archive, unsaving without stopping playback. A card-local drawer expands/collapses upward, honors Reduce Motion, and explicitly plays saved rows while staying open. No recording, archive format, or provider requests changed. D015’s passive source menu still does not autoplay; drawer row clicks are explicit Play actions.

### D020 ACTIVE — 2026-10-06 [USER]

Music heart/list hover backgrounds must be circular; use a clean list icon without an outline circle. Favorites must occupy existing card space at every window size, replacing track/transport details when necessary, and remain open after a source is selected. Move Audius attribution to the top-left artwork badge and make the existing top-right source menu a circular icon for now.

2026-10-06 [CODE] The music card keeps a constant 288-point minimum. A bounded vertical `ViewThatFits` chooses a list-plus-transport layout or a compact list with visible heart/toggle; only the list scrolls. Its local expansion state does not affect card/page dimensions. This supersedes D019’s initial 460-point expanded minimum. Saved-source playback and passive-menu behavior remain unchanged.

### D021 PARTIALLY SUPERSEDED BY D029 — 2026-10-06 [USER]

Clear Calendar mock data and connect it to real timers. Merge “A little glass” into Appearance, enlarge the glassiness slider’s grab area, remove persistent working-on outlines/text selection, use compact icon navigation and consistent thin transparent-track scrollbars, and add Habit tracker beside Dashboard.

2026-10-06 [CODE] The single workspace recorder now saves actual `RecordedSession` intervals alongside existing daily totals. Continuous ticks coalesce, while project/task/source changes, pauses, removals, and midnight separate segments. Flow retains recording priority and Pomodoro breaks stay uncounted. Calendar reads saved intervals and live duration/details; sample code is removed. Older archives load without sessions, and manual totals do not invent timestamps. Weekly removal/Undo includes sessions. Task text is app-shared runtime state, committed once from an explicitly opened local editor before timer actions or leaving Focus; project selection never forces task text into focus. Appearance contains the glass subsection with a 28-point thumb/44-point tracking area. `KeepScrollView` supplies native overlay scrollbars with rounded 5-point thumbs and transparent tracks. Navigation is icon-only below 900 points with accessible names/tooltips. Habit tracker opens an honest placeholder; tracking behavior was not requested. This supersedes D018’s sample-only scope and D007/D014’s window-local committed task text.

### D022 PARTIALLY SUPERSEDED BY D023 AND D032 — 2026-10-06 [USER]

Add a small Audius / Apple Music switcher beside the provider badge. Integrate Apple Music using the best feasible connection experience, save the last music volume across relaunch, replace the music-card bookmark with the supplied four-chevron zen icon without implementing zen mode, and add task-row Focus, Flow, and both-timers play controls. Focus/Flow colors follow their cards; both stays neutral across themes.

2026-10-06 [CODE] Provider and volume are optional validated additions to `keep.preferences.v1`, preserving old archives and protected invalid loads. Audius source selection moves into the provider menu; its drawer remains available. Apple Music uses the account/selection already in the Mac’s Music app, with normal Automation access on explicit Play and scoped `com.apple.Music.playback` events on a serial actor. Keep controls play/pause, previous/next, Music’s own volume, and current title/artist; songs/playlists and sign-in remain in Music via Open Music. It does not use MusicKit developer tokens, read the library, change system output volume, or show Apple Music catalog/artwork inside Keep. Switching/restoring providers stays passive; quitting awaits release of engaged Music playback. Native Apple Music playback with an active subscription remains UNCONFIRMED. The top-right four-chevron symbol is disabled. Task actions commit the editor then atomically settle/assign/start through WorkspaceModel, preserving the shared current project/task and Flow priority. Focus leaves breaks without resetting cycle progress; the other timer is unchanged. Both’s fill/ink use fixed neutral assets; keyboard focus and accessibility actions expose the task controls. This supersedes D013’s runtime-only volume and D020’s top-right source-menu placement.

### D023 PARTIALLY SUPERSEDED BY D024 — 2026-10-06 [USER]

Make the three task timer controls circles with only a play arrow. Bring Apple Music control, songs/playlists, artwork, search, and as much feasible control as possible into Keep.

2026-10-06 [CODE] Task controls retain their colors, labels, focus, shortcuts, and timer semantics with 30-point circles and a single arrow. The native Music bridge gains read-only library access: a window-local sheet browses/searches songs and playlists in bounded pages, opens playlist contents, and explicitly plays native selections. Now-playing controls include transport, volume, seeking, shuffle, and repeat; Retry retains the requested selection. Native artwork is decoded once through WallpaperLibrary, available as a sheet thumbnail while custom wallpapers stay selected, and reused for Track artwork (the older `audius` preference value remains compatible). Browse/Play may launch Music in the background, while selecting/restoring providers remains passive. Sign-in stays in Music. Full Apple streaming-catalog search/recommendations require MusicKit App Service setup for Keep’s App ID/team and remain unimplemented; no keys, new dependencies, developer-portal mutations, or library writes were added. This supersedes D022’s Music-only selection and missing Apple artwork/browsing. Actual subscription playback remains UNCONFIRMED.

2026-10-06 [USER] MusicKit is not yet enabled for Keep’s App ID.

### D024 PARTIALLY SUPERSEDED BY D025 — 2026-10-06 [USER]

Prefer screenshot verification over extensive live app control. Remove the Music dialog’s discovery/account footer, make it taller and slightly wider, fix card synchronization after a library song selection, and add Music control/read permission management in Settings.

2026-10-06 [CODE] The dialog prefers 620 × 720 and clamps to the shell viewport for the minimum window. Transient Music status failures now recover automatically with bounded backoff, including a failed read after a native command; late native artwork retries without replaying audio. Settings owns a Permissions section backed by runtime MusicPlayerModel access state and real scoped read probes. Passive probes suppress prompts and never launch Music; explicit access requests may launch it but never start audio/change volume/provider. Denied access opens Automation settings, and a recovered grant reconnects the selected Apple provider. Permission UI remains available when invalid saved preferences block editing. This supersedes D023’s fixed smaller sheet and stop-on-first-read-failure observer. Actual system permission prompts and subscribed playback were not exercised in this update.

### D025 ACTIVE — 2026-10-06 [USER]

Replace the brief error flash when playing a Music song with a loading animation during recovery, and explain what MusicKit can add to Keep.

2026-10-06 [CODE] Native Music start/read recovery has an eight-second grace, retaining Loading/play intent/current metadata with spinners in the card and library sheet. A not-yet-playing start snapshot remains Loading. Recovery reads use the normal cadence during grace, and persistent failures retain Retry/backoff. Permission errors remain immediate. This refines D024’s recovery observer without changing providers or introducing MusicKit. Migration to MusicKit is not an approved implementation decision.

### D026 ACTIVE — 2026-10-06 [USER]

Add a Projects tab beside Timesheet and Calendar, with project addition and deletion and a folder/list layout based on the supplied reference.

2026-10-06 [CODE] Projects uses existing project colors, alphabetical rows, shared creation dialog, and a native deletion confirmation. Deletion persists catalog tombstones while retaining recorded Timesheet/Calendar history. Deleting the selected project settles prior time and selects No project; independent timers keep their phases and future recording is unassigned. An unused created project persists without adding time or changing selection. All built-in projects may be deleted and remain removed after relaunch; No project is reserved for recording and is not a deletable catalog entry. The optional v1 field supports legacy archives; invalid IDs block loading/edits. Week browsing survives page switching; Projects hides week controls.

### D027 ACTIVE — 2026-10-06 [USER]

Fix System appearance following macOS only in the title bar while app content stays Light.

2026-10-06 [CODE] A small observable native application-appearance adapter resolves System independently of window preferences and observes `effectiveAppearance` changes. The shared appearance modifier supplies an explicit SwiftUI preference at the shell and Music sheet, replacing nil-preference clearing. Explicit Light/Dark, default Light, saved preferences, view identity, drafts, and playback remain unchanged.

### D028 ACTIVE — 2026-10-06 [USER]

Use `waveform.mid` for the music provider control; add task/project memory and pinning in the task selector, based on the recent-activity reference. Remove the requested idle music prompt, Focus slogan, Pomodoro settings explanation, Timesheet/Calendar slogans, and glassiness explanation.

2026-10-06 [CODE] The explicit task popover owns a window-local draft, searches saved task/project activity, and groups pinned tasks above recent ones with colored project labels. Recording actions remember nonblank task/project pairs, and pins survive relaunch in the optional workspace `taskActivities` archive. Selecting a suggestion settles the previous interval and restores both task/project without starting or stopping timers. Pin changes settle timing too. Legacy activity derives from actual recorded sessions; deleted projects are excluded and invalid archives block mutations. Daily task records and the current runtime task remain separate.

### D029 PARTIALLY SUPERSEDED BY D030 — 2026-10-06 [USER]

Implement Habit tracker with a GitHub-inspired monthly/weekly intensity grid based on completed habits, a weekly activity list with an adjacent stats panel, and an Add habit dialog for name, icon, start/end dates, and a renamed check-in or amount goal with minutes/times per day.

2026-10-06 [CODE] Goals are Daily check-in and Daily target, with optional inclusive end dates and manual past/current progress. One app-owned HabitStore saves definitions/logs separately in keep.habits.v1, validates archives, and protects failed loads. Amounts below the target remain partial; meeting/exceeding it counts once. Stats derive month/all-time completions, eligible-day rate, and current/best civil-day streaks. The right-side month calendar also edits progress; narrow layouts stack stats below the list. This supersedes D021's Habit placeholder only. No recurrence schedule, reminders, definition editing/deletion, timer integration, or sync is added.

2026-10-06 [ASSUMPTION] SUPERSEDED BY D030: Initial Monthly/Weekly modes displayed one month/week at a time while the year-overview preference was unconfirmed.

### D030 PARTIALLY SUPERSEDED BY D031 — 2026-10-06 [USER]

Show the whole current year in centered, smaller activity squares matching the references. Add seven selectable weekday dots to habit creation for specific days or every day. Add more color, fit weekly progress to its seven day columns, give stats more space, and merge the three cards into one surface with faded separators.

2026-10-06 [CODE] Monthly mode shows January–December daily completion intensity; Weekly mode shows stacked weekly totals scaled to the busiest week. One paper surface contains the activity grid and a compact 480-point weekly list beside stats (up to 560 points), stacking below 900 points. Habit icons/rows and metrics reuse varied existing accents with readable ink. Frequency persists with definitions, defaults legacy habits to all seven days, rejects rest-day progress, and affects eligible-day rates and streaks. Rest days do not break a streak; missed due days do. This supersedes D029's single-period assumption and lack of weekday frequency; reminders, editing/deleting definitions, other recurrence rules, timer integration, and sync remain outside scope.

### D031 ACTIVE — 2026-10-06 [USER]

Polish Habit controls, date pickers and checkbox; make habit check-in circles more visible, correct the misleading filled weekly column and slow mode switching, add scheduled habits to Tasks, restrict task timer launches to Today, and show suggestions normally in the task selector rather than in a separate list.

2026-10-06 [CODE] Weekly squares now count completed goals directly (one per goal, capped at seven), superseding D030’s peak-relative bars. The activity view reuses a cached annual snapshot of dates/counts/labels and resolves tile size/contrast once per body. Creation uses Keep’s styled calendar and paper checkbox; empty/future/rest circles have visible borders. DailyTaskStore projects due habits from the app-owned HabitStore without duplicated records; explicit checks meet/clear the same habit log, while future habit checks are blocked. Removing an occurrence hides that day only in the backward-compatible task archive. Today-only launch controls/actions recheck the day on activation. The selector has one flat inline task/project list, preserving pin ordering and saved project selection. This supersedes D022’s launch controls on historical dates and the previous absence of habit/task integration.

### D032 PARTIALLY SUPERSEDED BY D033 — 2026-10-06 [USER]

Activate the music-card chevron as Zen mode: fill the screen with the wallpaper while keeping timers and music available. Replace the broken glassiness control with Apple’s native slider, matching music volume. This supersedes D022’s deferred Zen placeholder and D021’s custom enlarged glassiness thumb.

2026-10-06 [CODE] Zen is window-local, commits the Focus draft, shares workspace/music/wallpaper owners, and uses native full-screen transitions observed without replacing SwiftUI’s delegate. Exit Zen or Escape preserves recording/playback and only returns to windowed mode if Zen entered full screen. Compact glass controls support Light/Dark and Reduce Transparency. Settings now binds a standard SwiftUI Slider directly to saved glassiness; the custom NSSlider bridge/cell is removed.

### D033 PARTIALLY SUPERSEDED BY D035 — 2026-10-06 [USER]

Make Zen as minimalist as the supplied wallpaper/music-overlay reference. Compress style.md and architecture.md by roughly 30–40%, removing incidental icon details and repetition while preserving essential development context.

2026-10-06 [CODE] Zen uses small white timer readouts at bottom-right and music transport/volume/metadata at bottom-left; narrow layouts stack them. Readability comes from a bottom fade rather than large cards. Reset/break controls live in timer context menus; Exit/Escape, loading/Retry, Music library access, shared runtime owners, and native window transitions remain. The unused card presentation variants/material helper are removed. Architecture keeps ownership, persistence/timing/provider constraints and build/check commands; duplicate verification history remains solely in this ledger. Style keeps semantic palette, layout, accessibility and feature intent without icon inventories or code samples.

### D034 PARTIALLY SUPERSEDED BY D035 — 2026-10-06 [USER]

Add the favorite and saved-playlists buttons to Zen so artists/playlists can be saved and chosen without leaving the mode.

2026-10-06 [CODE] Zen's Audius row uses the existing saved-channel archive and favorite target rules. A compact themed popover lists saved artists/playlists; selecting one explicitly plays it through the shared player, retains the picker and leaves timers/Zen intact. Unsaving does not interrupt playback. Apple Music retains its existing library browser; no library-write capability is added.

### D035 ACTIVE — 2026-10-06 [USER]

Remove Zen’s black bottom fade and Exit button, restore Escape exit, and replace the saved-playlists popover with an inline glass card like the music player.

2026-10-06 [CODE] Wallpaper brightness is unchanged by Zen. Escape is handled by the existing window bridge with a scoped local event monitor, independent of SwiftUI focus; modified keys, inactive/other windows and library sheets retain native behavior. The saved-list card expands above music transport and uses MusicGlassPanel with its full-screen artwork origin, existing glassiness and Reduce Transparency behavior. This supersedes D033’s bottom fade/Exit button and D034’s popover presentation.

### D036 ACTIVE — 2026-10-06 [USER]

Remove the Audius listens submenu from the provider menu. Put All Lofi permanently first in the playlist list, available before saving any artist/playlist.

2026-10-06 [CODE] Normal and Zen lists have a built-in All Lofi row followed by saved sources. MusicPlayerModel owns their explicit Play action: selecting All Lofi clears the prior source queue and saved selection without removing favorites; repeated selection retains playback, paused selection resumes, and failed selection retries. Next remains scoped to the chosen source. All Lofi is not stored in the archive. This supersedes the passive source submenu described in D020.

### D037 ACTIVE — 2026-10-06 [USER]

Move Calendar's explanation/zoom below the grid; exit Zen by double-clicking artwork; remove project-row subtitles and automatic task focus. Allow Calendar session deletion and start/end edits. Diagnose the glass slider without fixing it.

2026-10-06 [CODE] Session details validate time fields in the recorded day/timezone, including a midnight endpoint. Workspace mutations settle active recording, adjust Timesheet by the duration delta (floor zero), preserve timer phases/manual adjustments, and rotate the recorder ID to protect edited/deleted blocks from subsequent ticks. Deletion requires confirmation. Passive task titles no longer participate in keyboard focus; actionable controls and accessibility actions remain. Zen's background accepts double-click without adding an Exit control. This supersedes D021's read-only Calendar limit.

### D038 PARTIALLY SUPERSEDED BY D043 — 2026-10-06 [USER]

Widen the Working on card and add a Start both button.

2026-10-06 [CODE] The card is 450 points wide with a neutral labeled launch button beside the target details. It commits the draft, starts/resumes both timers for the current project/task (including unnamed targets), preserves running progress and Flow recording priority, and exits breaks into focus without clearing cycle progress. Breaks show Start focus + flow; running focus plus Flow disables the action. The Flow leaf and individual controls are unchanged. No shortcut was added.

### D039 PARTIALLY SUPERSEDED BY D042 — 2026-10-06 [USER]

Add a leaf menu-bar item with controls for both timers, today's tasks and the music player. Do not allow provider switching there. Add Settings for menu-bar behavior and selecting Pomodoro or Flow in its label.

2026-10-06 [CODE] A native SwiftUI MenuBarExtra shares the existing workspace/task/music owners, with independent timer controls, Start both, manual break launch, read-only ordinary/scheduled-habit tasks, selected-provider transport/volume and Open Keep/Quit. Appearance and error/Retry states are inherited. Optional preference fields default older archives to a visible leaf plus Pomodoro; Settings also offers icon only and hiding the item without stopping timers/music. The bounded panel scrolls long content. Actions use the committed task; editor drafts remain window-local.

2026-10-06 [TOOL] A TimelineView inside the native status label stalled the isolated fixture on the installed toolchain. Reading the workspace's existing display checkpoint restored responsive input and live timer text without a second ticker. Native status captures verified leaf + Pomodoro, leaf + Flow and leaf-only output.

### D040 PARTIALLY SUPERSEDED BY D043 — 2026-10-06 [USER]

Fix the menu-bar panel collapsing on click and replace the formal editorial font with a lighter, friendly font inspired by the supplied rounded sans-serif reference.

2026-10-06 [CODE] The native menu panel has a concrete 380 × 600 scroll viewport. The previous ViewThatFits/flexible-height scroll fallback accepted zero-height native proposals; native hosting measurement reproduced 0–1-point heights. Shared KeepTheme.headingFont replaces serif headings, the wordmark and static statistics with native rounded regular/medium type while preserving sizes, colors and workspace geometry.

### D041 ACTIVE — 2026-10-06 [USER]

Make the menu panel follow Keep's dark-mode choice and use the app's default timer colors. Add Start on login in Settings. Put Edit on the right of habit information, opening the original creation dialog with only name and icon editable.

2026-10-07 [CODE] The shared appearance modifier resolves both presentation and content scheme; menu rows reuse default coral/sage/butter tokens. App-owned LoginItemModel uses SMAppService.mainApp, with macOS status as the source of truth, explicit registration/removal, pending approval/error recovery and visible/active refresh. HabitStore.updateIdentity validates and saves name/icon while preserving ID, dates, goal, weekdays and logs; the original dialog shows saved values with other fields disabled. No archive schema, helper or entitlement changes.

### D042 PARTIALLY SUPERSEDED BY D043 — 2026-10-07 [USER]

Allow project/recent-task selection and task naming from the menu bar. Clicking the current task slides the entire control page left to a picker with Back. Allow checking and unchecking tasks there.

2026-10-07 [CODE] MenuBarTargetPicker searches project/task names and retains pin-first recent ordering. A panel-local FocusTaskEditor commits names through WorkspaceModel; project/recent selections settle recording without autoplay. Back/Escape/dismissal cancels drafts. Both pages share the fixed viewport, with inactive input/accessibility excluded and Reduce Motion respected. Native task toggles use the shared DailyTaskStore/HabitStore and revalidate stable origin/actual day before completion. D039's read-only task list is superseded; provider controls and shared owners are preserved.

2026-10-07 [USER] Refine the menu picker by removing Use task name and placing recent tasks above projects. Make its control-page target header resemble the main Working on card. [CODE] Return remains the name commit action; the header uses a project-colored folder tile, caption, project/task and neutral combined-timer action without a chevron.

### D043 ACTIVE — 2026-10-07 [USER]

Move the menu's combined timer button below its timer cards and prevent scrolling of the main page. Put a Quit Keep icon beside Open Keep, remove idle music filler, and pad recent-task rows while allowing the task page to scroll. Start both must also stop both through the same control in the menu and main app.

2026-10-07 [CODE] The menu has a fixed 380 × 680 viewport; Today’s task list fills/scrolls the available middle area and the target picker remains scrollable. Transport/mute/volume share one permanent row. The power icon quits through native app termination; a compact issues popover preserves error/Retry access without growing the page. Both combined controls expose Stop both whenever Pomodoro (focus or break) and Flow run; otherwise they start/resume focus and Flow. WorkspaceModel.stopBothTimers settles recording once, preserves elapsed time and cycle, and saves. Existing startBothTimers stays an explicit launch action for other callers. D038's disabled-running action and D042's in-header menu action are superseded.

### D044 ACTIVE — 2026-10-07 [USER]

Implement Stats with recorded focus totals/trends, project → multiple task filters, inclusive custom date ranges, equivalent-period comparisons, focus patterns, completed Pomodoros, date-scoped task/habit summaries, an optional weekly goal and optional streaks. Exclude export. Final attribution choice supersedes the initial planning choice: completed Pomodoros belong to the project/task active at completion; recorded minutes retain actual attribution.

2026-10-07 [CODE] Stats is a mounted native destination with window-local query/scroll state, fixed filters and responsive semantic cards/Swift Charts. Pure Sendable snapshots aggregate off-main with cancellation/generation fencing and coalesced pending recording updates. Focus uses actual recorded sessions; adjusted daily totals remain secondary. Tasks exclude projected habits/deleted rows; habits use scheduled full-target check-ins. Preferences save the optional all-project current-week goal and streak visibility. Workspace settlement emits immediately saved completion events with monotonic boundary attribution and unique interval identity, independent of Flow overlap/time edits. Optional archive fields preserve legacy history with explicit coverage; no counts are inferred. D005/D015's disabled Stats state is superseded.

2026-10-07 [USER] Change Where your time went to a segmented ring inspired by the supplied reference. Hover reveals each project's total time; choosing a project switches to its task breakdown. [CODE] Native Charts sectors retain Keep's palette, with a central total/inspected value and clickable time/percentage legend; narrow layouts stack the legend below the ring.

2026-10-07 [USER] Show bar-chart values on hover instead of an expandable Show values list. [CODE] Focus trend, weekday and hour bars show themed date/time callouts on hover, including zero buckets, while retaining keyboard and accessibility inspection.

2026-10-07 [USER] Remove the comparison/recording and Pomodoro-coverage explanation lines beneath the summary cards. Always show streaks and remove the checkbox. [CODE] The streak-visibility preference is retired; older archives remain readable and cannot hide streaks. This supersedes D044’s optional streak presentation; calculations and completion coverage remain unchanged.

2026-10-07 [USER] Style the Stats project list like the task picker. [CODE] A matching searchable paper popover provides single-project selection and Cancel/Apply; applying a different project resets task filters, while reapplying the same project preserves them. All projects, No project and marked deleted history remain available.

### D045 SUPERSEDED BY D046 — 2026-10-07 [USER]

Fix the non-draggable Glassiness slider; changing its mechanism is authorized. [CODE] Settings replaces SwiftUI Slider with GlassinessSlider, a native NSSlider bridge with explicit nonblocking mouse-event tracking, continuous live preview/persistence, grab-offset preservation and clamping. It retains the layout, theme and native drawing, with keyboard controls and percentage accessibility actions. This supersedes D037’s diagnose-only slider scope and the shared SwiftUI-slider mechanism; music volume is unchanged. The original SwiftUI interaction failure has no confirmed framework root cause.

### D046 SUPERSEDED BY D047 — 2026-10-07 [USER]

Replace the Glassiness slider with a percentage text field. [CODE] GlassinessField accepts whole values from 0 to 100, previews and saves valid edits immediately, and restores the last saved value on Return or focus loss for unfinished/invalid input. The stored normalized preference and music-volume slider are unchanged. This supersedes D045’s slider mechanism; its bridge and checks are removed.

### D047 PARTIALLY SUPERSEDED BY D048 — 2026-10-07 [USER]

Fix the full clickable area of selection menus and restore the Glassiness slider. Appearance order is Dark mode → A little glass → Preview → Card material → Glassiness slider. [CODE] KeepSelectionMenu explicitly includes its padded label/spacer/chevron in the interaction shape and makes its border noninteractive. Settings restores native slider drawing with explicit drag tracking, continuous preference updates, keyboard/accessibility actions and a percentage readout, removing the percentage-field implementation/checks. This supersedes D046; stored glassiness values and music volume are unchanged.

### D048 ACTIVE — 2026-10-07 [USER]

Replace the custom GlassinessSlider with the native SwiftUI Slider already used for music volume and delete unused code. [CODE] Settings binds Slider directly to AppPreferences glassiness, preserving live preview, theme tint, percentage accessibility and the requested preview-before-controls layout. The custom NSSlider bridge and its dedicated event checks are removed. This supersedes D047’s slider implementation; the menu hit-area fix and Appearance order remain.

### D049 ACTIVE — 2026-10-07 [USER]

Use free Sparkle 2 for application updates and the existing `youssefezzat304/keep` GitHub repository for releases.

2026-10-07 [CODE] One app-owned updater uses Sparkle's scheduler and persisted update preferences, with automatic checking on by default every six hours and installation chosen by the user. Settings and the application menu expose manual checks; active/paused timers require a restart confirmation, settle/save through WorkspaceModel, and restart idle. Debug builds cannot update. Shared configuration contains only the public verification key and a stable public GitHub latest-release appcast URL. A dedicated private EdDSA key is held in local Keychain account `com.youssef.keep`; feeds/archives require signatures. App Sandbox stays enabled with Sparkle's documented installer exceptions. Release signing/notarization, first public appcast/archive publishing, secure key backup and actual upgrade verification remain release work; no remote mutation or CI publishing was performed.

## [PROGRESS]

- 2026-10-05 [CODE] Established architecture documentation from all current Swift views, asset definitions, and the Xcode project. Documented actual composition and separated placeholders from functional behavior.

- 2026-10-05 [CODE] Added semantic color assets, generated/bundled music artwork, adaptive card composition, independent timer state, and window-local task add/completion behavior.

- 2026-10-05 [CODE] Added selectable Timesheet UI with four static sample projects, seven weekday/date columns, project/day/week totals, and a horizontally scrollable table. Editing and week controls are disabled.

- 2026-10-05 [CODE] Added a native project popover with search, selected-row checks, hover/focus feedback, and a separate task-name field. Selection and task text remain owned by FocusSessionView.

- 2026-10-05 [CODE] Added app-shared recording with Flow priority, focus/rest intervals, computed totals, editable cells, current/historical weeks, local saving, and a termination flush. Moved project metadata and picker presentation into shared boundaries.

## [DISCOVERIES]

- 2026-10-06 [TOOL] Installed Xcode 27/macOS SDK and Apple’s documentation confirm MusicKit ApplicationMusicPlayer is available on macOS 14+, while SystemMusicPlayer is unavailable on macOS. Swift MusicLibrary add/create/edit methods are also unavailable on macOS, and the installed MusicPlayer API has no volume setter. Catalog/library search, artwork, recommendations and subscription checks are available; app-owned playback is a feasible future direction after App Service setup, but volume/local-library behavior needs a prototype before replacing the existing bridge. Sources: [ApplicationMusicPlayer](https://developer.apple.com/documentation/musickit/applicationmusicplayer), [MusicKit](https://developer.apple.com/documentation/musickit), installed MusicKit.swiftinterface.

- 2026-10-06 [TOOL] Scoped Music library reads require the source hierarchy; playlist ranges fail (-1708), while indexed user-playlist references work. Native song search rejects read-only access (-10004); bulk name/artist/album reads and local filtering work under the existing read-only grant. Keep retains playback + library.read only.

- 2026-10-05 [CODE] Initial draft kept timers/tasks in each Focus view. D008 introduces one app-owned WorkspaceModel for timers, selection, and recording; D014 adds separately saved daily task lists, retaining window-local input/task-name drafts.
- 2026-10-05 [CODE] `PrimaryButton` and `NavBar` receive caller-owned actions. `AppShellView` owns Focus/Timesheet/Settings selection and preserves mounted focus state across tab changes.
- 2026-10-05 [CODE] Timer and supporting-card pairs stack below 820 points; tab content and task lists scroll within the fixed panel. Timer cards share presentation without sharing timing state.

## [OUTCOMES]

- 2026-10-05 [CODE] First visual draft is implemented. Unsigned build and timing checks pass; offscreen layout renders inspected. Live UI verification is unavailable without computer-use permission.

- 2026-10-05 [CODE] Timesheet UI is complete for the requested mock-data scope; week editing/navigation and timer integration remain intentionally unimplemented.

- 2026-10-05 [CODE] Working on picker and task-name UI are implemented with local sample data. Offscreen normal/search/empty/unassigned and narrow layouts inspected; live interaction remains unverified.

- 2026-10-05 [CODE] Timer recording and Timesheet editing/persistence implemented. Build, 24 timer checks, and 84 workspace checks passed, including cross-process persistence. Offscreen running/completed/break, empty/live Timesheet, and editor layouts inspected.

## [OPEN QUESTIONS]

These questions are not blockers for unrelated work; resolve them when the relevant feature is requested.

- 2026-10-05 [CODE] UNCONFIRMED: Calendar drag-and-drop, restoring timer runtime, automatic interval starts, and future notifications. Habit tracking and weekday frequency are implemented under D029/D030; other recurrence rules/reminders/sync remain unrequested. Real session recording is implemented under D021. Current focus/break/sleep/relaunch behavior is documented in D008, D011, and architecture.
- 2026-10-05 [CODE] UNCONFIRMED: project renaming, task-level aggregate editing, and future storage migration. Task text is captured in actual sessions under D021. Project switches currently apply prospectively, and selection preserves task text.
- 2026-10-07 [CODE] Statistics scope is implemented under D044; export remains excluded. UNCONFIRMED: offline audio and account/gated playback. Appearance, music preferences, and saved channels are implemented under D015.

## [WORKING SET]

- 2026-10-05 [CODE] `AGENTS.md`
- 2026-10-07 [CODE] `docs/architecture.md`, `docs/updates.md`
- 2026-10-05 [CODE] `docs/decisions.md`
- 2026-10-05 [CODE] `docs/style.md`
- 2026-10-05 [CODE] `keep/App/`
- 2026-10-05 [CODE] `keep/Models/`
- 2026-10-05 [CODE] `keep/Features/FocusSession/`
- 2026-10-05 [CODE] `keep/Features/Dashboard/`, `keep/Features/Habits/`, `keep/Features/Timesheet/`, `keep/Features/Music/`, `keep/Features/Tasks/`, `keep/Features/Settings/`, and `keep/Features/Updates/`
- 2026-10-05 [CODE] `tests/`
- 2026-10-05 [CODE] `keep/Assets.xcassets/`
- 2026-10-05 [CODE] `keep/DesignSystem/`
- 2026-10-05 [CODE] `keep.xcodeproj/project.pbxproj`

## [RECEIPTS]

- 2026-10-07 [TOOL] Sparkle: resolved SPM 2.10.0; unsigned Debug and Release builds passed (existing App Intents metadata warning only). Passed 38 updater checks, 100 session-recording checks, 18 completion checks, 73 silent music/preferences checks, 17 menu checks and 13 native appearance checks. Updater checks include startup/KVO, separate-process preferences, Debug/configuration gates, Later/paused behavior, exactly-once continuation, save-failure blocking and final Flow-priority settlement. A locally ad hoc signed fixture generated a signed appcast/archive; five CryptoKit checks verified both signatures against the shipped public key, GitHub enclosure URL and tamper rejection. Original unsigned packaging was correctly rejected by Sparkle's code-signature validation. Inspected native Light/Dark Settings at 1000×900, 680×650 and 1710×1080, including scrolled narrow/pending-restart states. Git diff --check and runner syntax check passed. Unsigned fixtures report Sparkle sandbox-extension probe diagnostics; actual signed sandbox installation, public feed delivery, restart/relaunch, physical keyboard/VoiceOver and Developer ID/notarization remain unverified. No remote release, live archives, real music playback or private-key export was used.

- 2026-10-07 [TOOL] Fixed menu/combined stop: unsigned Debug build, 100 session-recording checks (17 new combined-stop checks), 17 menu preference/native-sizing checks and git diff --check passed. Native Light/Dark screenshots inspected long task lists, idle/loading music with track details, breaks and combined Stop, plus main Focus at 1000 × 900 and 680 × 650. Isolated live hosts verified Start → Stop from the same control in the menu and main header, retained elapsed values, shared task completion, fixed main-page accessibility structure and padded recent rows. A later native capture error prevented further live resume/keyboard checks; deterministic resume checks passed. Actual status-item click, full VoiceOver and release signing remain unverified. No live archives, real audio or networking were used.

- 2026-10-07 [TOOL] Menu header/picker refinement: unsigned Debug build, 17 native menu sizing/preferences checks and git diff --check passed. Native Light/Dark renders inspected the header, long names, breaks and reordered picker. Isolated live panel verified recent-first section order, absence of Use task name, Return naming and the relocated combined-timer action. No live archives, audio or network playback were used; actual status-item click and full VoiceOver remain unverified.

- 2026-10-07 [TOOL] Menu picker/completion: unsigned Debug build, 17 menu preference/display/native-sizing, 24 task-activity, 68 daily-task, 47 habit/task and 83 session-recording checks passed. Isolated native panel verified task-title navigation, project filtering/selection, recent-task/project restoration, Return to commit, Escape/Back to cancel, ordinary/habit checks and unchecks, unchanged idle timers, and inactive-page accessibility exclusion. Light/Dark and long-title/no-match picker renders inspected. Actual status-item click, full VoiceOver and release signing remain unverified. No user archives, real audio or networking were used.

- 2026-10-07 [TOOL] Appearance/startup/habit edit: unsigned Debug build; 13 appearance, 15 fake-service login-item, 17 habit-identity, 130 habit and 47 habit/task checks passed (plus the 17 menu sizing checks above). Inspected menu Light/Dark/System under opposing native appearances, default timer/break colors, and default 1000 × 900 / narrow 680 × 650 Habits/Settings. Isolated live habit dialog verified locked goal/schedule/date fields and saved name/icon changes. Login tests never registered the real app; signed-app registration and launch after login remain unverified. No user archives or real audio/network playback were used.

- 2026-10-06 [TOOL] Menu panel/font fix: unsigned Debug build and 17 menu preference/display/native-sizing checks passed. A comparison host reproduced the previous layout accepting 0–1-point height proposals; the fixed host reports a usable 600-point viewport. Inspected native Light/Dark default 1000×900 and minimum 680×650 Focus, Dashboard, Habits, Settings and panel screenshots. Isolated live panel hosting verified scrolling to music/volume/Quit. Actual status-item click remains unverified because the UI tool did not expose the status item; the native-button test action did not open it. No user archives, real audio or network playback were used. Full keyboard/VoiceOver and release signing remain unverified.

- 2026-10-06 [TOOL] Menu bar: unsigned Debug Xcode build, 9 standalone menu preference/display checks, 83 session-recording checks, and 73 silent music/preferences/library/artwork checks passed; git diff --check passed. Native status captures verified leaf + live Pomodoro, leaf + live Flow and icon only, including continuing updates after closing the fixture window. An isolated native panel verified Start both, independent timer stop/reset and music play/pause/mute intent; Light/Dark panel and Settings renders inspected at default 1000×900 and narrow 680×650 shell sizes, plus full Settings layouts. No live archives or real audio were used. Full keyboard/VoiceOver operation, live Apple Music consent/playback and release signing remain unverified.

- 2026-10-06 [TOOL] Start both: unsigned Debug Xcode build and 83 standalone session-recording checks passed. Native offscreen renders checked at 1000×900, 680×650, and 1710×1080 in Light/Dark, including running and break labels and long task text. Live keyboard/VoiceOver interaction remains unverified.

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

- 2026-10-05 [TOOL] Audius unsigned Debug and local ad hoc signed Debug builds passed; sandbox/network-client entitlements inspected. Passed 47 music checks and 180 workspace regression checks. Public API search/stream resolution and native AVPlayer Playing → Pause → Resume verified in a separate sandboxed harness at zero volume. Offscreen idle/playing/loading/error cards and default/wide/narrow layouts inspected; audible output and live UI/keyboard/VoiceOver remain unverified.

- 2026-10-05 [TOOL] Daily-task unsigned Debug build and 56 daily-task checks passed, including date isolation, DST/midnight navigation, leap dates, completion/deletion, protected corrupt loads, and cross-process persistence. Existing 180 workspace and 47 music checks passed. Offscreen today/past/tomorrow/future-empty/load-error tasks, date picker, narrow card, and default/wide/minimum layouts inspected; live input/popover/keyboard/VoiceOver remains unverified.

- 2026-10-05 [TOOL] Settings unsigned/ad hoc signed Debug builds passed; sandbox, network-client, selected-file read-only, and app-scoped bookmark entitlements inspected. Passed 68 music, 63 preference/wallpaper, 180 workspace, and 56 task checks, including cross-process preferences and real image/bookmark loads. Real Audius artist and playlist discovery/play/pause/resume verified in a sandboxed native harness at zero volume. Offscreen default/minimum Settings, full settings content, dark Focus/Timesheet/popover, and solid/frosted music inspected. Live folder importer/menu/keyboard/VoiceOver and onscreen Liquid Glass remain unverified; native Liquid Glass cannot be assessed through the offscreen bitmap harness.

- 2026-10-05 [TOOL] Artwork backdrop unsigned Debug build, 74 preferences/wallpaper checks, and 68 music checks passed. Shared image loading/reuse, URL/source changes, HTTP/decoding failure fallback, and cancellation verified. Native offscreen default/wide/minimum, light/dark, all-tab, folder-artwork, and isolated wash renders inspected; live interaction remains unverified.

- 2026-10-05 [TOOL] Calendar/Settings/glass refinement: unsigned Debug build, 68 daily-task and 74 preferences/wallpaper checks passed. Inspected native light/dark calendars, centered default/wide/minimum/full Settings, and solid/mid/clear music controls. Isolated live preview verified material-menu/appearance selection, actual artwork blur/transparency changes, date-button selection, invalid date blocking, and future/historical task-day selection. No user archives were changed and no audio was played. Popover keyboard/VoiceOver and system Reduce Transparency switching remain unverified.

- 2026-10-05 [TOOL] Dashboard unsigned Debug build passed. Inspected native default/wide/minimum Calendar, dark Calendar, and populated Timesheet renders. Isolated live preview verified view switching, shared week navigation/This week, retained Calendar selection/week across Focus, sample details, zoom, and edited Timesheet totals. Inactive-view controls are absent from the accessibility tree. No live user data was changed or audio played; full keyboard/VoiceOver remain unverified. Calendar uses labeled sample sessions only.

- 2026-10-06 [TOOL] Artwork/favorites unsigned Debug build and 240 temporary palette/contrast checks passed. Inspected default/wide/minimum, warm/cool, and light/dark native renders. Silent in-memory preview verified saved playlist playback intent, heart save/unsave, drawer staying open/collapsing, project selection, appearance, and 45% → 90% glassiness updating the artwork. Pointer drag/full keyboard/VoiceOver remain unverified due native UI-tool window/capture/input failures; no user archives changed or audio played.

- 2026-10-06 [TOOL] Music drawer refinement: unsigned Debug build passed. Silent native preview inspected default 1000 × 900 / narrow 680 × 650 Focus and 600 × 288 / 600 × 560 player cards in Light/Dark. Favorites preserved card bounds and narrow scroll position, switched between compact and list-plus-transport layouts, retained playback/list state through selection/collapse, and updated heart removal. Circular source menu choices worked. Full keyboard/VoiceOver remain unverified after native input/capture failures; no user archives or real audio/network playback were used.

- 2026-10-06 [TOOL] unsigned Debug build and 38 checked-in session-recording checks passed. Checks cover coalescing, captured tasks/projects, Flow priority, focus/break exclusion, pauses, delayed completion, midnight, 23/25-hour DST days, wall-clock jumps, manual totals without invented timestamps, running removal/Undo, legacy archives, reloads, and protected corrupt loads. An isolated in-memory native preview verified actual Flow time and updating session details in Calendar, task-name commit before Play, explicit inline editing without persistent highlight, default/minimum layouts, Appearance’s merged glass subsection, Light/Dark, thin transparent-track scrollbars, and the Habit tracker placeholder. An actual thumb drag changed glassiness from 45% to 73%; final styling retains native tracking and a larger bright thumb. Native UI tools intermittently rejected later drags with noWindowsAvailable; full VoiceOver remains unverified. No user archives were changed or real audio/network playback used.

- 2026-10-06 [TOOL] Provider/task integration: unsigned Debug build passed; 48 session, 68 daily-task, and 17 silent music/preferences checks passed, including separate-process provider/volume reload, legacy/corrupt preferences, denied access/Retry, canceled replies, and task launches during recording/breaks. Native in-memory previews verified provider selection, silent Apple transport, task assignment/Focus/both, Tab/Space/Return shortcuts, and Light/Dark default/compact layouts. A separately ad hoc signed sandboxed harness read Music’s actual playback state using the playback-only entitlement without starting audio. Actual subscribed Apple Music playback/metadata remains unverified; the environment has no playable selection. Pointer hover/scroll and the lower narrow viewport could not be fully exercised because native UI input intermittently returns noWindowsAvailable; full VoiceOver remains unverified. User archives were untouched.

- 2026-10-06 [TOOL] In-Keep Music library update: unsigned Debug build and 42 silent music/preferences/library/artwork checks passed; `git diff --check` passed. Ad hoc signed sandboxed read-only native harness verified two song pages, user playlists, playlist contents, stable native song/playlist references, matching/empty song and playlist searches without playback/library changes. Isolated native previews verified circle-only task controls, Tab/Space/Return Focus/Flow assignment, library navigation/search/empty results/Retry, transport/seek/shuffle/repeat intent, shared cover thumbnail with custom wallpaper, and Light/Dark default 1000 × 900 / minimum 680 × 650 layouts. Actual subscribed playback/current native cover and full VoiceOver remain unverified; no live archives were changed or audio started. MusicKit catalog setup remains pending.

- 2026-10-06 [TOOL] Music sync/permissions refinement: unsigned Debug build and 57 silent music/preferences/library/artwork checks passed; `git diff --check` passed. Regression fixtures verified stopped/delayed native Play responses, read failures immediately after Play and during status refresh, automatic metadata/artwork recovery without a second Play, external song changes, provider cancellation, permission check/request/revocation/recovery, and fenced late access replies. Offscreen native screenshots inspected the larger/default and clamped/narrow dialog, removed footer, Light/Dark Settings, and allowed/denied/unrequested permission layouts. No live UI control, user archives, real permission prompts, or audio were used; actual Automation consent and subscribed playback remain unverified.

- 2026-10-06 [TOOL] Transient-loading refinement: unsigned Debug build and 62 silent music/preferences/library/artwork checks passed; `git diff --check` passed. Added checks that brief startup/read failures never flash Failed, pending native playback preserves loading/Play intent, persistent failures leave the grace window, and permission denial remains immediate. Offscreen dark card/dialog screenshots show native spinners with retained metadata and no Retry banner during recovery. No live UI control or real audio was used. MusicKit capabilities were verified against the installed SDK and Apple documentation; no MusicKit integration or Developer-account changes were made.

- 2026-10-06 [TOOL] Projects unsigned Debug build, 28 project-catalog checks, 48 session-recording checks, and `git diff --check` passed. Native offscreen Light/Dark, long-name, empty-catalog, and three-tab layouts inspected at default/minimum shell allocations. Add/delete persist, recorded history survives deletion/Undo, and running/paused/break timer semantics remain intact. Live sheet/confirmation, scrolling, keyboard, and VoiceOver remain unverified; no user archives or audio were used.

- 2026-10-06 [TOOL] System appearance unsigned Debug build, 10 native offscreen appearance checks, and `git diff --check` passed. A comparison harness using the previous nil-preference behavior failed the Light → System, Dark → System, and repeated-transition checks. Checks cover Light/Dark overrides, Light → System and Dark → System, later native appearance changes, repeated transitions, and two windows sharing preferences. Persistent-window Settings screenshots inspected explicit Light and System Light/Dark at 1000 × 900 and System Dark at 680 × 650. Native changes were simulated through the isolated harness process’s application appearance; macOS settings, live user archives, and audio were untouched. Actual macOS automatic scheduled switching and live sheet/keyboard/VoiceOver interaction remain unverified.

- 2026-10-06 [TOOL] Task suggestions/copy cleanup unsigned Debug build, 24 task-activity checks, 48 session-recording checks, 28 project-catalog checks, and `git diff --check` passed. Checks cover project-linked reuse, pin ordering/reload, blank/break exclusion, atomic task/project selection during concurrent timers, paused selection without autoplay, late-completion pin settlement, legacy session migration, deleted-project filtering, and corrupt-load protection. Native offscreen Light/Dark menu/search/long-title, default 1000 × 900 and narrow 680 × 650 Focus, full Settings, Pomodoro settings, and Calendar screenshots inspected. The installed native symbol lookup confirms waveform.mid exists. No live user archives or real audio were used; actual popover transitions, keyboard/VoiceOver, and pointer scrolling remain unverified.

- 2026-10-06 [TOOL] unsigned Debug build and 91 standalone habit checks passed, covering definition/goal/date validation, inclusive ranges, future blocking, check-in clearing, partial/exceeded targets, completion aggregation, observable UI invalidation, month rates, current/best streaks, leap/DST/week/year boundaries, Gregorian keys, corrupt-load protection/Retry, and separate-process persistence. Native offscreen screenshots inspected Light/Dark default 1000 × 900, narrow 680 × 650, and wide 1710 × 1080 layouts, monthly/weekly grids, empty/populated states, aligned full-width weekly rows, long-name stats, and creation/amount/end-date sheets. All twelve habit SF Symbols resolve in the installed native system. No live UI control, user archives, real audio, or network playback were used; actual sheet/menu transitions, keyboard navigation, pointer scrolling, VoiceOver, and release signing remain unverified.

- 2026-10-06 [TOOL] unsigned Debug build and 130 standalone habit checks passed, including legacy daily archive migration, saved weekday frequency and separate-process reload, rest-day log rejection, scheduled-day rates/current/best streaks, DST, and complete 365/366-day annual grids (including a 54-column year). Native offscreen screenshots inspected Light/Dark at default 1000 × 900, narrow 680 × 650, and wide 1710 × 1080, plus full content, annual weekly bars, and amount/end-date creation with selected weekdays. The annual grid fits all twelve months at narrow widths; weekly rows remain compact and stats expand beside them or stack below. No live UI control or user archives were used. Keyboard navigation, VoiceOver, live sheet transitions, and release signing remain unverified.

- 2026-10-06 [TOOL] Habit/task refinement: unsigned Debug build, 130 habit checks, 68 daily-task checks, 47 habit/task integration checks, 24 task-activity checks, and git diff --check passed. Integration covers due dates/weekdays, shared check-in/amount completion, future blocking, independent manual tasks, observation invalidation, stable mixed-row identity, hidden occurrences, protected corrupt loads, separate-process relaunch, and Today/midnight timer eligibility. Native offscreen Light/Dark screenshots inspected default/narrow/wide Habit layouts, visible empty/disabled circles, themed creation/end-date controls and calendar, Today/past/future Tasks, flat pinned suggestions, and a single-completion weekly grid. Four programmatic mode-binding updates in an isolated native host completed layout in 47–78 ms (including a 10 ms yield), and rendered images confirmed both modes changed; 1,000 cached annual reads took about 3 ms. No live UI control, user archives, audio or network playback were used. Actual pointer/keyboard popover transitions, VoiceOver, and release signing remain unverified.

- 2026-10-06 [TOOL] Zen/native-slider verification: unsigned Debug build and git diff --check passed; 32 Zen model/native bridge checks, 62 silent music/preferences/library/artwork checks, 48 session-recording checks, and 3 isolated glassiness save/reload checks passed. Hidden native windows verified bridge attachment, delegate preservation, scoped notifications, rapid Exit, pre-existing full-screen preservation, and close/detach cleanup without changing Spaces. Native offscreen Light/Dark screenshots inspected Zen within the complete shell at 1000 × 900, 680 × 650, and 1710 × 1080, plus normal Focus and Settings previews at 0/50/100% glassiness. No live app control, user archives, audio, or network playback was used. Actual full-screen animation, Escape/keyboard/VoiceOver operation, native slider dragging, and release signing remain unverified.

- 2026-10-06 [TOOL] Minimal Zen/document compression: unsigned Debug build, 32 Zen checks, 48 session-recording checks, 62 silent music/preferences/library/artwork checks, and git diff --check passed. Native offscreen screenshots inspected Light/Dark default, minimum and wide Zen shell layouts, normal Focus/Settings, paused timers and music errors. No live app control, user archives, audio or network playback was used; actual full-screen animation, pointer/context-menu, keyboard and VoiceOver interaction remain unverified. Architecture shrank from 10,459 to 6,819 words (34.8%); style from 3,260 to 2,208 (32.3%), retaining core constraints and commands.

- 2026-10-06 [TOOL] Zen favorites: unsigned Debug build, 62 silent music/preferences/library/artwork checks and git diff --check passed. Native offscreen Light/Dark screenshots inspected the new music row at default/minimum/wide sizes plus empty and long-name saved-list content. A hidden-window accessibility-action harness could not find SwiftUI's heart in its accessibility tree, so action execution and live popover/pointer/keyboard/VoiceOver remain unverified. No live app control, user archives, real audio or network playback was used.

- 2026-10-06 [TOOL] Bright Zen/Escape/glass refinement: unsigned Debug build, 42 Zen checks, 62 silent music/preferences/library/artwork checks and git diff --check passed. Hidden native checks dispatch Escape through NSApplication’s installed local event monitor and cover active/entering exit, other/inactive windows, modified keys and detachment. Offscreen screenshots inspected bright/no-Exit Zen at default/minimum/wide sizes in Light/Dark, plus separately composed inline glass-card content at 55%/0% glassiness. Programmatic mouse events in a hidden host did not open the drawer; actual expansion/collapse, pointer/VoiceOver operation, full-screen animation and onscreen Liquid Glass remain unverified. No live app control, user archives, real audio or network playback was used.

- 2026-10-06 [TOOL] All Lofi playlist entry: unsigned Debug build, 73 silent music/preferences/library/artwork checks and git diff --check passed. New checks cover empty-catalog Play, saved-source selection, playlist-scoped Next, leaving the playlist for lofi discovery, retained favorites/selection reload, repeat selection without restart, paused resume, provider switching and Retry. Native offscreen Light/Dark screenshots inspected default/minimum/wide Zen and normal Focus, plus separate glass-list content with/without saved favorites. Live menu/drawer/keyboard/VoiceOver interaction remains unverified; no user archives, real audio or network playback was used.

- 2026-10-06 [TOOL] Calendar editing refinement: unsigned Debug build, 74 session-recording checks, 42 Zen checks and git diff --check passed. Session checks include validation, live edit/delete settlement, manual deltas/floor, midnight/DST and reload/protected corrupt archives. Offscreen native Light/Dark default/minimum/wide Calendar and Focus, Timesheet and session-editor screenshots inspected. Slider source/binding and 0/50/100% preview renders respond; this Mac reports Reduce Transparency off. Actual pointer dragging/double-click, live sheet/confirmation, keyboard and VoiceOver remain unverified. Slider unchanged; no confirmed root cause for the reported interaction failure. No user archives, real audio or network playback were used.

- 2026-10-07 [TOOL] Stats: unsigned Debug build passed; 37 Stats aggregation, 18 completion-event, 13 preference/model, 100 session, 28 project-catalog, 24 task-activity, 68 daily-task, 47 habit/task, 130 habit, 17 menu-bar, 73 silent music/preferences, and 13 native appearance checks passed. Checks cover inclusive/custom ranges, matching comparisons, multiple/unnamed/deleted-project task filters, recorded timezone/DST, scheduled habit rates/streaks, completion-boundary attribution, pause/sleep/Flow/settings/Reset, immediate saving, legacy/corrupt archives, cancellation/fencing and cross-process preferences. Inspected 13 native isolated captures (Light/Dark default/narrow/wide, full, empty, filtered, errors, date/task/goal pickers); categorical bands fixed zero-width numeric bar marks. Live computer-use startup failed, and a temporary in-process AX fixture could not activate Month; pointer/keyboard/VoiceOver operation remains unverified. No live user archives, real audio or network playback were used.
- 2026-10-07 [TOOL] Distribution ring: unsigned Debug build, 37 Stats aggregation checks, 13 preference/model checks and diff whitespace check passed. Rendered 14 isolated native layouts, including Light/Dark default/narrow/wide and a multi-task project ring. Inspected the project/task rings and reused contrast-adjusted project shades for readable sectors. Live computer-use startup still fails; live hover/click/keyboard/VoiceOver interaction remains unverified. No recorder, archive or playback behavior changed.

- 2026-10-07 [TOOL] Bar hover callouts: unsigned Debug build, 13 Stats preference/model checks and whitespace check passed; rendered 14 native layouts. Inspected two additional Light/Dark callout previews with an initial-selection fixture, including a zero bucket at the right edge of a narrow chart. Pointer interaction remains unverified because the native computer-use tool is unavailable; the selected previews do not simulate hovering.

- 2026-10-07 [TOOL] Always-visible streaks: unsigned Debug build, 37 Stats aggregation checks, 13 preference/model checks and whitespace check passed. Legacy preferences with the retired streak visibility field remain readable. Rendered 14 native layouts and inspected full Stats content: both requested explanation lines and the checkbox are absent, while streaks remain visible.

- 2026-10-07 [TOOL] Stats project picker: unsigned Debug build, 13 preference/model checks and whitespace check passed; rendered 16 native layouts. Inspected matching Light/Dark project popovers with single selection, wrapped long names and deleted-history labels. Live picker interaction remains unverified because the native computer-use tool is unavailable.

- 2026-10-07 [TOOL] Glassiness fix: unsigned Debug build, 114 native slider event checks, 73 silent music/preferences/library/artwork checks, 13 native appearance checks and whitespace check passed. Drag handlers were driven with local NSEvents across intervening SwiftUI redraws in Light/Dark at 1000 × 900, 680 × 650 and 1710 × 1080; checks cover both directions, immediate saving, bounds, grab offset, disabled controls, keyboard/accessibility and external updates. Inspected six Settings captures. No global pointer events, user archives, Music prompts or playback were used. Live physical pointer/VoiceOver operation remains unverified because native computer-use startup is unavailable.

- 2026-10-07 [TOOL] Glassiness percentage field: unsigned Debug build, 18 input/bounds/persistence checks and whitespace check passed. Rendered and inspected Light/Dark Settings at 1000 × 900, 680 × 650 and 1710 × 1080 with the percentage field visible. Native typing/focus/VoiceOver interaction remains unverified because computer-use startup is unavailable; checks exercise parsing/persistence and offscreen presentation. No user archives, Music prompts or playback were used.

- 2026-10-07 [TOOL] Menu hit-area and glass layout: unsigned Debug build, 114 native slider event checks, 13 native appearance checks and whitespace check passed. Inspected Light/Dark Settings captures at 1000 × 900, 680 × 650 and 1710 × 1080 with preview before controls. Slider checks cover drag directions, continuous saving, bounds, grab offset, external updates, disabled controls and local keyboard/accessibility actions. Live menu clicks, physical slider dragging and VoiceOver remain unverified: computer-use startup still fails. No user archives, global pointer events, Music prompts or playback were used.

- 2026-10-07 [TOOL] Native SwiftUI glassiness slider: unsigned Debug build, 13 native appearance checks and whitespace check passed. Rendered six Light/Dark Settings layouts at default/narrow/wide sizes and inspected representative captures. Confirmed no custom glassiness control or dedicated check references remain in source/current guidance. Physical dragging remains unverified because native computer-use startup is unavailable. No user archives or playback were used.
