# Reporting exports

Settings → Export has its own window-local controls. Choose Calendar, Timesheet or Stats; both From and Through are included and Through cannot be later than today. Defaults are Calendar, Monday through today, and all projects. Historical/deleted projects and No project remain selectable. Calendar and Stats can filter normalized task names within one project; Timesheet has no task attribution. These choices never change the reporting tabs or persist after closing a window.

Export captures a fixed request and immutable data after settling the single recorder. Timers and music continue. Preparation, CSV encoding, ZIP packaging and disk I/O run off the main actor. Cancel stops preparation; cancelling the native save sheet is neutral. Restore locks prevent capture and invalidate pending work. Failed required-store loads/saves block reporting with Retry rather than reporting empty data. Calendar/Timesheet require workspace data; Stats also requires tasks, habits and validated preferences. Backups still require all four stores and use the unchanged `.keepbackup` schema.

## Encoding

CSV files use UTF-8, English headers, ISO civil dates, locale-independent numeric values and CRLF row endings. Fields containing commas, quotes or newlines are quoted, and embedded quotes are doubled. User-authored text starting with `=`, `+`, `-` or `@` after leading whitespace, or starting with a tab/CR/LF, gets an apostrophe prefix to prevent spreadsheet formula evaluation. This may be visible in CSV readers that do not interpret spreadsheet escaping. Numeric fields stay numeric, including negative comparison differences. Empty datasets keep their headers.

Rows have stable ordering: Calendar by saved civil day/start instant/session ID, Timesheet by saved day/project ID, daily/bucket/hour/weekday reports chronologically, distribution by grouping ID, and habits/targets by stable IDs. Times are seconds unless a column or target unit says otherwise. Boolean values are `true`/`false`; missing values are empty fields.

## Calendar CSV

`Keep-Calendar-YYYY-MM-DD-to-YYYY-MM-DD.csv` contains one row per matching real recorded session:

| Columns | Meaning |
| --- | --- |
| `session_id`, `recording_id` | Saved segment and recording identities |
| `civil_day` | Saved Gregorian civil attribution; not recomputed from the export timezone |
| `project_id`, `project_name`, `project_deleted` | Current catalog metadata when available; historical metadata otherwise |
| `task`, `timer_source` | Recorded text and `flow`/`pomodoro` source |
| `start`, `end` | ISO timestamps with the saved timezone's offset at each endpoint, including DST changes |
| `timezone`, `duration_seconds` | Saved timezone identifier and actual numeric interval duration |

No sessions are synthesized from adjusted totals or completion events. Flow/Pomodoro overlap retains the recorder's Flow priority. Midnight segments retain their distinct saved days.

## Timesheet CSV

`Keep-Timesheet-YYYY-MM-DD-to-YYYY-MM-DD.csv` has one row per saved project/day entry, including zero entries. Columns are `civil_day`, `project_id`, `project_name`, `project_deleted`, `adjusted_timesheet_seconds`, `recorded_focus_seconds`.

Adjusted values come from saved entries. Recorded values sum actual session intervals for that project and saved day, using the shared Timesheet projection rules. Their difference is not identified as a known manual adjustment: older entries may have no session coverage. Sessions without a saved entry do not create an extra Timesheet row.

## Stats ZIP

`Keep-Stats-YYYY-MM-DD-to-YYYY-MM-DD.zip` contains only generated CSV reports. Foundation's coordinated `.forUploading` directory snapshot provides ZIP packaging; this does not upload anything. Stats uses the existing `StatsSnapshot.make` calculation with a custom date range. Full-range daily contributions are independent of the activity grid's single displayed year.

| File | Contents and scope |
| --- | --- |
| `metadata.csv` | Version 1, capture UTC instant, inclusive dates, reporting timezone, project/task filters, units, comparison cutoff, bucket grouping, formula protection and scope notes |
| `summary.csv` | Recorded total, active days, average per active day, previous equivalent total/difference, current/best focus streaks, tracked Pomodoros and coverage; adjusted totals and date-only task counts remain separately named |
| `focus_daily.csv` | Every selected civil day, including zero days and years outside the activity grid |
| `focus_buckets.csv` | Daily up to 31 selected days; weekly up to 180 days; monthly beyond 180 days, matching Stats Custom |
| `distribution.csv` | Projects, or normalized task groups within a chosen project; deleted status retained |
| `focus_weekdays.csv` | Monday–Sunday contributions using saved civil dates |
| `focus_hours.csv` | Hours 0–23 in each session's recorded timezone; repeated DST hours contribute twice and nonexistent hours contribute zero |
| `adjusted_totals.csv` | Same columns as Timesheet; selected project/dates, independent of task filters |
| `tasks.csv` | Saved ordinary-task and completion counts for every selected day; **all tasks; date scope only**, excluding projected habit rows |
| `habits.csv` | Habit ID/name, scheduled opportunities, completions/rate and current/best streaks; **all habits; date scope only** |
| `weekly_targets.csv` | Global/project/habit aspiration, minimum, progress and units for the **current Monday–Sunday week**, independent of historical range or project/task filters |

Pomodoro counts are real once-only completion events. `pomodoro_coverage` is `unavailable` when coverage does not overlap the selected period, `partial` when it starts after that period begins, or `tracked` when it covers the period. Unavailable counts are blank; a tracked zero is numeric zero. `pomodoro_coverage_start` preserves the actual start instant when known. Counts before coverage are never estimated.

Habit completion requires its full daily target on a scheduled day. Rest days do not add opportunities or completions; existing Stats streak rules remain unchanged. Weekly habit target progress matches HabitStore's saved weekly amounts, including amounts retained after schedule changes. Project/global progress uses recorded focus across all tasks. Global goals have no separate minimum, so their minimum field is blank. Time-based project/global targets use seconds; habit targets use `minutes`, `times` or `check-ins` as specified in `unit`.

## Saving and verification

Artifacts are staged in a private, unique temporary directory. The asynchronous native save sheet chooses the destination; coordinated atomic writing preserves an existing destination if preparation/reading fails. Panel-granted access and any additional scoped access are released, no destination bookmark is retained, and staging is removed after success, cancellation or failure. Success means a local save completed, including when the selected folder happens to be in iCloud Drive; it does not mean a cloud upload completed.

Debug and Release enable `com.apple.security.files.user-selected.read-write` through Xcode's `ENABLE_USER_SELECTED_FILES = readwrite`. Wallpaper bookmarks remain explicitly read-only. See [Apple sandbox guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) and [Foundation ZIP snapshot guidance](https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions/foruploading).

Build the existing scheme, then run:

```sh
python3 Tools/run-app-checks.py ExportChecks BackupChecks CacheChecks StatsChecks SessionRecordingChecks ExportPresentationChecks
```

`ExportChecks` uses isolated defaults, deterministic clocks, temporary files and injected panel/file adapters. It verifies reporting values, protected stores, scope distinctions, encoding, ZIP contents, DST/cross-year attribution, concurrent recording, restore fencing, cancellation, overwrite protection and cleanup. `ExportPresentationChecks` renders all three datasets at default/narrow sizes in Light/Dark, checking native viewport bounds. `KEEP_EXPORT_INTERACTIVE=1` opens its in-memory Export fixture for 90 seconds for keyboard/save-panel inspection, without accessing live archives or music.

Signed end-to-end save/overwrite checks, VoiceOver reading/focus and Developer ID release verification must also be performed on a normal signed installation. CSV/ZIP are reporting formats; `.keepbackup` remains the recovery format. PDF, ICS, import and scheduled exports are outside this version.
