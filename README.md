# Keep

A native macOS focus workspace with independent Pomodoro and Flow timers, project/task recording, music, daily tasks, habits and local statistics.

## Project layout

```text
Sources/Keep/
  App/          App assembly, shell and lifecycle
  Core/         Value types, timer rules and aggregation
  Services/     Shared stores, persistence and native integrations
  UI/           Feature views, presentation models and DesignSystem
  Support/      Preview fixtures
Resources/      Assets, Info.plist, entitlements and third-party notices
Configuration/ Public update configuration
Tests/          Standalone checks
Tools/          Development tools
docs/           Architecture, decisions, style and release instructions
keep.xcodeproj/ Xcode project and keep scheme
```

This organization follows [vorssaint-utils](https://github.com/vorssaint/vorssaint-utils), adapted to Keep's existing Xcode workflow. Keep remains a single application module.

## Build and check

Open `keep.xcodeproj` in Xcode and choose the `keep` scheme, or run an unsigned local build:

```sh
xcodebuild -project keep.xcodeproj -scheme keep -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/keep-derived-data \
  CODE_SIGNING_ALLOWED=NO build
python3 Tools/run-app-checks.py UpdaterChecks
```

The project targets macOS 15 and newer. The unsigned build checks compilation; release signing, notarization and real update installation require separate verification.

See [architecture and check commands](docs/architecture.md), [decisions](docs/decisions.md), [visual style](docs/style.md), and [Sparkle release setup](docs/updates.md).
