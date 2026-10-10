# Keep — Decisions

Only the ten most recent decisions are retained, oldest first. See `AGENTS.md` for documentation ownership and retention rules.

### D070 — Music player and personal Zen wallpapers (2026-10-08)

- [USER] Highlight the music player and personal Zen wallpapers using images the user will provide. The initial 500,000+ lo-fi/ambient claim is superseded by the user's follow-up: use music copy without a count for now.
- [CODE] A dedicated music section describes Audius discovery/saved public artists and playlists, the Mac Music library and shared playback controls. Zen explicitly describes selecting a personal folder of images or MP4 videos. Wallpaper files were initially pending; supplied assets are integrated under D071.
- [CODE][TOOL] The genre-specific catalog count remains UNCONFIRMED and is omitted. `AudiusClient.lofiTracks()` requests 30 results; public artist/playlist channels extend that selection. Audius’s overall catalog size does not establish a lo-fi/ambient count or Keep’s playable selection. No music or wallpaper runtime behavior changed.

### D071 — Supplied live wallpaper previews (2026-10-08; superseded by D072)

- [USER] Use the four MP4 wallpapers supplied in `website/public/live wallpapers/` for the website.
- [CODE] Zen has a four-choice live wallpaper preview, with explicit play/pause, muted inline looping and viewport-based playback. Reduced Motion, data saving and disabled JavaScript retain still posters; explicit Play can opt into motion. The existing actual native Zen capture remains available in an expandable preview. No web imitation of native app controls is introduced.
- [CODE] `npm run wallpapers` uses installed FFmpeg and existing Sharp to create silent 720p fast-start H.264 derivatives, WebP posters and thumbnails in `public/media/wallpapers/`. Original files are unchanged. Only the selected video loads when its preview enters view. The local static-preview server supports MP4 byte ranges for WebKit playback. No native runtime, release or hosting behavior changes.

### D072 — Restore the original Zen screenshot (2026-10-08)

- [USER] Remove the live wallpapers from the website and return to the original screenshot.
- [CODE] Zen again displays the original responsive native capture directly. Removed the chooser/disclosure, preview component, styles, manifest, generation command/script, generated derivatives, video-specific preview-server handling and retired interaction checks. Personal-wallpaper feature copy and supplied original MP4 files remain. This supersedes D071’s website presentation; native app behavior is unchanged.

### D073 — Product README (2026-10-08)

- [USER] Follow the structure of the vorssaint-utils README, include Keep’s logo and screenshots, omit the donation section, and recommend a license.
- [CODE] Root README now introduces implemented features, free pricing, local storage/permissions, installation status, build commands and canonical documentation. Nine PNG assets under `docs/assets/readme/` reuse the existing icon and eight isolated native captures. GitHub has no public release as of this update. `LICENSE.md` is empty; a license recommendation does not select or apply one.

### D074 — MIT license (2026-10-08)

- [USER] License Keep under MIT, superseding D073’s pending license selection.
- [CODE] Added the standard MIT text to `LICENSE.md` with copyright 2026 Youssef Abdelrahim (name from repository commit metadata). README links to the license; third-party notices remain unchanged.

### D075 — Remove auxiliary documentation (2026-10-09)

- [USER] Remove unnecessary standalone guides from the pushed repository and let agents inspect implementation when details are needed.
- [CODE] Preserved the user's deletion of the backup, update, export and music-artwork guides. Removed their stale links and tool references; canonical architecture, decisions and style remain. Documentation no longer repeats the local signing account or iCloud container identifier in those architecture sections. Runtime identifiers and configuration are unchanged; deleting files does not rewrite existing Git history.

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
