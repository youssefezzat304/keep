# iCloud backup

Keep keeps its working data local. Optional iCloud backup stores immutable `.keepbackup` snapshots in `iCloud.com.youssef.keep/Documents/Backups/<installation UUID>/`. This is backup/explicit replacement, not live synchronization or merging.

## Data and compatibility

Schema 1 is a JSON envelope with an ID, capture timestamp, originating installation UUID, app version, encoded payload and SHA-256 payload checksum. Files are limited to 128 MiB; encoded payloads are limited to 64 MiB. Unsupported schemas, corrupt checksums and invalid per-store archives are rejected before replacement. The payload contains the existing workspace ledger (including catalog edits/deletions, adjusted totals, sessions, suggestions/pins, Pomodoro configuration/completion events and coverage), task archive (including hidden habit occurrences), habit archive and an explicit portable-settings whitelist.

Appearance, wallpaper presentation/rotation, saved Audius sources and selection, provider/volume, menu-bar preferences and the weekly focus goal are portable. Folder bookmarks/names, login/update configuration, permission status, backup configuration, decoded artwork, temporary URLs, caches, playback, timer runtime and current editor drafts are excluded. Restoring preserves this Mac's existing wallpaper folder permission; a missing folder must be reselected through Settings. No backup is produced from a failed/protected store load. Legacy per-store decoding defaults are retained without inventing history. Restoring a ledger without Pomodoro tracking coverage starts coverage at the restore checkpoint, just as a normal legacy load does.

`BackupModel` owns scheduling and presentation for all windows. `BackupLocalFiles` validates and serializes immutable value snapshots and does local file I/O on its actor. Archive value types/validators are explicitly nonisolated; live models remain main-actor isolated. A capture settles the single workspace recorder, forces its save and copies all four values without suspension. Set-backed fields are canonically ordered for stable dirty checks across relaunches.

## Automatic operation and status

Automatic backup defaults off. Explicit enable captures immediately; thereafter a minute-level scheduler checks for an hourly, changed snapshot, including an overdue capture after reopening. Manual backup bypasses the hourly limit. Keep does not install a background helper or wake itself when closed.

One active cloud submission and one latest queued local snapshot bound pending storage. Both are saved in the app's local Application Support `Keep/Backups/Outbox` folder so retry/relaunch reuses the original ID. Disabling automatic backup drops queued automatic work while preserving explicit manual requests; an already submitted iCloud file may finish uploading. Existing pending submissions can be observed after relaunch even when automatic backup is off. Protected or unreadable local backup configuration/outbox files pause new backups without replacing their bytes.

`keep.backup.local.v1` contains device-local opt-in, installation UUID, archived iCloud identity, pending URL, capture/checksum and last-confirmed-upload metadata. It is not included in portable settings or cloud files. Account changes revoke automatic consent and clear account-specific confirmation; pending snapshots are abandoned before explicit use of a new account. Coordinator operations verify the current account before writes/deletions, and UI/model callbacks are fenced by an epoch.

Archived identity tokens are compared using the native token's equality, rather than assuming independently encoded archives have identical bytes. An unreadable identity fails closed and requires renewed consent.

`ICloudBackupStorage` resolves the container off the main thread, uses coordinated reads/writes/deletions and watches `NSMetadataQuery`. A local write means **pending upload**, not success. The upload-confirmed timestamp records when this Mac observed iCloud's uploaded metadata, not an inferred server timestamp. Network-path loss can identify offline state; a satisfactory path never proves upload success. Quota, download and upload errors remain actionable. Restore explicitly requests an evicted file's download and waits for metadata before a coordinated read. Download/preview can be canceled; late results cannot reopen a dismissed preview.

Retention applies only to confirmed uploads in this installation's folder. It keeps the union of the latest 24 versions and the newest version for each of the last 30 UTC days. Other Macs and pending uploads are never pruned.

## Restore and recovery

The picker groups cloud versions by originating installation and also lists validated local pre-restore copies. Filename dates are discovery hints; the validated envelope supplies the confirmation date and contents. The user sees a replacement summary and explicitly confirms stopping timers and pausing music.

Confirmation settles/stops both timers, stops owned music playback, takes an app-wide restore gate and captures recovery data. Before changing any preference key, Keep writes and verifies a raw local recovery journal containing original/candidate archive bytes (including absent-key information); readable current data also gets a portable recovery snapshot. Raw recovery files are local only and preserve corrupt archive bytes without pretending they are valid restore choices.

`BackupRestoreTransaction` persists an uncommitted journal before touching the four existing keys. It flushes preferences through `CFPreferencesAppSynchronize`, verifies the resulting values, writes a committed journal, then removes it. A replacement/flush failure attempts rollback; an unsuccessful rollback leaves the uncommitted journal and gate in place. Once the candidate is durably flushed, marker-write failure leaves recovery to startup instead of attempting a potentially conflicting rollback. At startup, before any stores are constructed, an incomplete journal restores the original values/absences. A committed journal leaves the restored data intact. Failed startup recovery blocks store loading/writes and provides an actionable notice with Quit; it never exposes a writable mixture of archives.

Successful replacement installs validated values in the existing owners, resets both timers and current target, clears Undo, rebuilds history/habit indexes and advances the shared restore generation. Every workspace and menu content subtree is recreated to discard old drafts/sheets/queries. Music provider/source/volume are reapplied passively, without playback, launching Music or authorization prompts. The latest three portable recovery copies and three raw recovery journals are retained locally after successful restores.

## Developer ID setup and release verification

The repository declares iCloud Documents entitlements, container metadata and the Xcode capability. It does not contain an account/team-specific provisioning profile or signing identity. These declarations alone do not establish cloud access.

1. Use the intended paid Apple Developer team. Enable iCloud Documents for the existing explicit App ID `com.youssef.keep`; create/associate `iCloud.com.youssef.keep`. Leave CloudKit, key-value storage and push notifications disabled for this feature.
2. Select that team in Xcode and regenerate the development and **Developer ID** profiles with the container association. Use a Developer ID Application certificate for distribution; do not lower sandbox protection or substitute an ad-hoc signature for integration testing. Keep account-specific team/profile selections in the release signing setup.
3. Inspect the signed app's `codesign -d --entitlements :-` output and embedded `Contents/embedded.provisionprofile` (`security cms -D -i ...`). Verify CloudDocuments and both container identifier arrays match the profile. Follow `docs/updates.md` for Release packaging, notarization and stapling.
4. With disposable test data and an explicitly enabled backup, use two Macs signed into the same test iCloud account. Confirm actual upload, discovery on the second Mac, evicted-file download, validated restore and local recovery. Check offline/reconnect, full quota, denied/unavailable Drive and account changes. Keep must remain usable locally throughout cloud failures.
5. Exercise a signed Release build from the notarized DMG, including its sandbox/profile and Sparkle integration. An unsigned build or fake metadata check does not verify these capabilities.

Apple references: [supported macOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-macos/), [configuring iCloud services](https://developer.apple.com/documentation/xcode/configuring-icloud-services), [container access](https://developer.apple.com/documentation/foundation/filemanager/url(forubiquitycontaineridentifier:)), [upload confirmation](https://developer.apple.com/documentation/foundation/urlresourcekey/ubiquitousitemisuploadedkey), [preference durability](https://developer.apple.com/documentation/corefoundation/cfpreferencesappsynchronize(_:)).

## Local checks

Build the existing unsigned Debug scheme as documented in `docs/architecture.md`, then run:

```sh
python3 Tools/run-app-checks.py BackupChecks BackupPresentationChecks
```

Checks use isolated preference domains, temporary local files, silent music adapters and fake cloud metadata. They never copy live archives into iCloud, request Music access, play audio or change the user's network/iCloud configuration. Native presentation captures are written under `/tmp/keep-backup-renders`. Signed two-Mac transfer, real quota/account switching and physical keyboard/VoiceOver operation remain separate release checks.
