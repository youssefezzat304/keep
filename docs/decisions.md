# Keep — Decisions

Only the ten most recent decisions are retained, oldest first. See `AGENTS.md` for documentation ownership and retention rules.

### D076 — Concise architecture and bounded documentation (2026-10-09)

- [USER] Condense the architecture overview, stop automatic architecture/style edits, and retain only the ten most recent decisions. Put these working rules in `AGENTS.md`.
- [CODE] Architecture is now a short source/state/integration/build overview. `AGENTS.md` permits automatic documentation edits only in this ledger; other documents require an explicit user request. Retained D067–D076 and removed older entries, snapshots and logs without creating an archive.

### D077 — Initial beta release version and archive name (2026-10-09)

- [USER] Use version `0.1.0` for the initial beta and name the disk image `keep-0.1.0.dmg`.
- [CODE] Debug and Release marketing versions are `0.1.0`; the first unpublished build remains `1`. Packaging uses lowercase `keep-VERSION.dmg`, with matching signed appcast URLs and checksums. Local packaging does not publish a GitHub release.
- [CODE] Pre-release delivery remains UNCONFIRMED: the current Sparkle feed resolves through GitHub's stable `releases/latest` endpoint, and the website excludes pre-releases. This version/name change does not select or configure beta feed hosting.

### D078 — Saved Pomodoro presets (2026-10-10)

- [USER] Add Settings/Presets choices to the timer popover, a name field below its subtitle, Save preset to the right of Save, and remove all increase/decrease controls.
- [CODE] Named presets store all four Pomodoro settings in the workspace ledger and existing backups; older archives load with no presets. Names are trimmed, bounded and unique without case/diacritic distinctions. Save applies settings; Save preset stores the entered rhythm without applying it. Presets can be used or deleted. Applying uses the existing workspace settlement path and preserves running/paused interval durations.

### D079 — Growing Pomodoro perimeter progress (2026-10-10)

- [USER] Implement the rectangular visual timer as no border → border.
- [CODE] Pomodoro cards trace a thin inset outline clockwise from the top center using the native continuous rounded-card shape. Progress derives from elapsed time and the current interval duration: idle/reset is empty, pause freezes it, completion is full, and each new focus/break starts a fresh outline. Preset changes retain the active interval's existing duration. The overlay uses shared readable ink, cannot intercept controls and adds no accessibility element; Reduce Motion disables interpolation and uses the existing one-second refresh. Flow and recording rules are unchanged.

### D080 — Original timer sound assets (2026-10-11)

- [USER] Create three notification sounds matching Keep's atmosphere and put them in the existing sounds folder.
- [CODE] Added original synthesized soft mallet cues in `docs/assets/sounds/`: `focus-complete.wav` (descending, 2.30 s), `break-complete.wav` (ascending, 1.95 s), and `flow-reminder.wav` (single quieter tone, 1.70 s). Masters are 48 kHz, stereo, 24-bit PCM with gentle attacks, short room tails and faded boundaries. Existing supplied recordings remain unchanged. These are standalone assets; timer playback, preferences and the optional one-hour Flow reminder are not implemented by this asset task.

### D081 — Active timer selection and menu bar progress (2026-10-11)

- [USER] Show the single running timer in the menu bar regardless of the preferred timer, use the preference when both run, and include Pomodoro's progress outline.
- [CODE] Status selection uses current timer phases, including Pomodoro breaks; when neither runs it retains the preferred readout. Icon only remains an explicit opt-out. The compact readout is a native template image containing the shared perimeter outline, refreshed by the existing workspace clock. The menu panel reuses the outline on its Pomodoro row, with smooth refreshes disabled under Reduce Motion. Pause freezes progress, reset clears it, and a new focus/break gets a fresh outline. Settings explains automatic selection and exposes Flow seconds whenever timer readouts are enabled. No timer or recording semantics changed.

### D082 — Timer visibility and sound reminders (2026-10-11)

- [USER] Add timer controls in Settings for Pomodoro progress and Flow visibility, integrate the three original cues, and make Flow’s top-right icon configure recurring reminders.
- [CODE] Validated preferences and portable backups retain visibility, sound enablement and optional 1–1,440-minute Flow intervals; older archives keep timers visible, completion sounds enabled and Flow reminders off. Progress visibility covers Focus and menu-bar readouts; Flow visibility covers Focus and Zen without stopping recording or removing menu controls.
- [CODE] The existing app-owned timer refresh emits one focus/break completion cue and recurring Flow cues using accumulated running time. Pauses preserve cadence; reset or interval changes start a fresh countdown; late refreshes coalesce missed Flow reminders into one cue, and muted events never replay. Recording priority and completion history remain unchanged.
- [CODE] Bundled WAVs reuse D080’s original bytes. One app-owned native audio player queues concurrent cues and supplies Settings previews/mute controls. These are sound reminders while Keep runs (including with windows closed), without notification banners, OS permissions or scheduling after quitting.

### D083 — Shared timer visibility across surfaces (2026-10-11)

- [USER] Add a Show Pomodoro timer setting and hide every hidden timer from the menu bar.
- [CODE] Both timer visibility preferences now apply to Focus, Zen, status readouts and menu controls. A single visible timer supplies the status readout even if the preferred/running timer is hidden; hiding both leaves the leaf. Icon only remains an explicit opt-out, and the saved preference returns when both timers become visible. Combined start/stop and Pomodoro break actions are absent when their timers are hidden.
- [CODE] Pomodoro visibility defaults on in older settings/backups and persists through existing validated storage and portable restore. Its progress switch retains its value while disabled when Pomodoro is hidden. Hiding affects presentation only; active sessions, recording and sound reminders continue. This supersedes D082’s policy of retaining hidden Flow controls in the menu bar.

### D084 — Task estimates and automatic timed habits (2026-10-12)

- [USER] Implement the accepted plan: right-side task editing and optional estimates, identity-based actual time, minute-habit progress combining manual and recorded minutes, one goal sound without stopping timers, active task/project labels, and future-plan CSV exports. Keep normal Pomodoro intervals; use daily habit goals in planned totals and automatic timed-habit completion status.
- [CODE] Optional task references preserve daily task identity and habitual civil-day occurrences through recording, recent targets, editing and Undo. Ordinary task comparisons include linked work across midnight; habit progress splits by recorded day. Renaming retains attribution, removal detaches subsequent ordinary-task recording, and older unlinked history is never matched by title. Gregorian keys now agree across task, habit and recording stores without rewriting saved sessions.
- [CODE] The read index derives actuals from session deltas; HabitStore combines those seconds with existing manual logs for task rows, activity, streaks, Stats and weekly targets. Automatic minutes are not stored as manual progress. Persisted consumed goal markers prevent replay after mute, corrections, reload and locked backup restore. New original 48 kHz stereo/24-bit `habit-complete.wav` is bundled with existing preview/mute/queued playback.
- [CODE] Task estimates allow blank or 1–1,440 whole minutes. Daily planned totals retain completed rows and include scheduled visible timed-habit goals. Both running cards display task/project context while preserving break and recording-priority notices. The new date-only Task estimates CSV and Stats ZIP report include zero-time estimates, future plans, removed-task recorded history, and separate manual/combined habit columns; unavailable data surfaces recovery errors.
- [TOOL] Ad hoc Xcode build and 763 focused/regression checks passed across task identity, timer recording, habits, sound playback, exports, Stats and backup/restore. Twenty native layouts covered light/dark and default/narrow sizes; native input verified validation, Return save, Escape cancel, rename attribution, manual-minute clearing and active timer labels. Distribution signing and macOS 15 execution were not validated.

### D085 — Annual focus activity independent of Stats dates (2026-10-12)

- [USER] Focus activity must show the whole year independently of the selected week.
- [CODE] Both direct Stats aggregation and the incremental cache now populate every recorded day of the displayed year through today. Project/task filters still apply; period totals, charts, streaks and daily exports retain their date scope. The existing displayed-year selection remains tied to the range’s starting year. Annual tiles outside the selected period can be inspected, and the caption reports the year’s total without date-range qualifiers or numeric grouping in the year.
- [TOOL] Ad hoc Xcode build and 382 Stats, weekly-target, cache, model and viewport checks passed; native renders inspected at 1000 × 900 and 680 × 650 in light/dark. Corrected a Monday-sensitive presentation check to accept an empty current week while verifying loaded annual history.
