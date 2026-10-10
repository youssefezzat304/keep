# Keep — Architecture

Keep is a native macOS 15+ focus workspace built with SwiftUI in one Xcode application module (`keep`). Focus, Dashboard, habits, Stats and Settings share local data; Zen and the menu bar expose the same timers and music.

## 1. Application

`Sources/Keep/App/KeepApp.swift` assembles the shared models, workspace windows, menu-bar scene and shutdown handling. `AppShellView` composes feature views and keeps inactive tabs mounted to preserve presentation state.

## 2. Source layout

- `Sources/Keep/Core/`: value types, timer rules, reporting and history calculations.
- `Sources/Keep/Services/`: shared observable models, persistence and native/provider adapters.
- `Sources/Keep/UI/`: feature views and window-local presentation models; `DesignSystem/` owns shared themes and controls.
- `Sources/Keep/Support/PreviewData/`: isolated example fixtures.
- `Resources/` and `Configuration/`: assets, plist, entitlements, third-party notices and public update configuration.
- `Tests/` and `Tools/`: standalone checks, build and release tooling.
- `website/`: independent Next.js marketing site, outside the app bundle.

## 3. State ownership

`KeepApp` owns workspace, tasks, habits, music, preferences, wallpapers, backups and updater models shared across windows. Views own navigation, drafts, filters and Zen presentation. Closing workspace windows does not stop app-owned timers or playback; relaunch starts timers idle and music without autoplay.

## 4. Time recording

`WorkspaceModel` coordinates independent Pomodoro and Flow timers and one recorder. Timer actions, project/task changes and time edits settle recording before mutation. Running Flow takes priority; otherwise Pomodoro focus counts. Breaks contribute no Pomodoro time, and overlapping timers never double-count. `FocusTimer` uses `ContinuousClock`; display refreshes are separate from timing truth. Dashboard and Stats read the same recorded history.

## 5. Storage and exports

Projects, sessions, daily totals, tasks, habits and preferences persist in validated local UserDefaults archives. Views use store actions rather than writing archives directly. Shared `SnapshotCapture` settles recording and copies consistent values for CSV/ZIP exports and backups. Export encoding and file operations run off the main actor; restore uses a shared gate and recovery journal.

## 6. Integrations

Audius streams through URLSession and AVPlayer; Apple Music control uses scoped macOS Automation. Wallpaper loading is shared across windows. Sparkle 2 handles Release update checks through a signed appcast and archives; Debug checks are disabled. There is no Keep backend, account system or sync.

### Optional iCloud backup

Opt-in iCloud Documents backup uses coordinated files and metadata-confirmed upload status. Developer ID provisioning and signed two-Mac verification remain unconfirmed.

## 7. Build configuration and capabilities

`keep.xcodeproj` owns the target/scheme, Debug/Release configurations and Sparkle package resolution. Swift defaults to main-actor isolation. The app is sandboxed with network, selected-file, bookmark and Music Automation capabilities. Inspect the project and resource files for exact settings. Default window size is 1000 × 900; minimum is 680 × 650.

## 8. Development and verification

Run from the repository root with full Xcode installed:

```sh
Tools/build.sh --check UpdaterChecks
Tools/build.sh --configuration Release --ad-hoc
Tools/package-release.sh --tag v1.0.0
python3 Tests/ReleaseToolsChecks.py
```

Use the configured app version for the release tag and each script's `--help` for options. Checks run in isolated app bundles; there is no Xcode test target. Build products stay in ignored `build/` and `dist/`. Packaging creates a DMG, signed Sparkle appcast and checksums; it does not publish, install or notarize. Local compilation does not verify macOS 15 execution or real update installation.
