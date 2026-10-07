# Keep updates

Keep uses [Sparkle 2](https://sparkle-project.org/), a free, open-source macOS updater, through Xcode Swift Package Manager. The package resolution currently pins 2.10.0. Its license and third-party notices ship in `Resources/ThirdPartyNotices/Sparkle.txt`.

## Runtime

One app-owned `AppUpdater` starts in Release builds and remains alive across windows and the menu panel. Sparkle schedules checks approximately every six hours while Keep is open. Users can disable automatic checks in Settings or check manually from Settings and the Keep application menu. Downloads and installation use Sparkle's standard interface; automatic installation and system profiling are disabled. This is periodic polling, not a push service.

Before installation restarts Keep, running or paused timers require confirmation. Later retains the pending installation and leaves recording/playback running; Settings offers Restart to update. Continuing settles and stops both timers through `WorkspaceModel`, saves history, and then releases Sparkle's continuation. A save failure blocks that continuation. The existing termination delegate releases owned music playback. Timers restart idle after relaunch, consistent with ordinary quitting.

Debug builds never start Sparkle, so development copies cannot replace themselves with a release. Invalid feed/key configuration also disables the updater. Previews construct an unstarted updater. Sparkle owns its persisted update preferences; they are separate from `keep.preferences.v1`.

## Public configuration and private key

`Configuration/Updates.xcconfig` supplies the public HTTPS feed and EdDSA verification key. `Resources/Info.plist` merges those values and Sparkle options into Xcode's generated plist in both configurations. Keep retains App Sandbox and its outgoing-network capability; the installer launcher and the two bundle-scoped Sparkle Mach lookup exceptions are enabled. Downloader.xpc is bundled by Sparkle but is not enabled because Keep already has outgoing-network access.

The configured feed is:

```text
https://github.com/youssefezzat304/keep/releases/latest/download/appcast.xml
```

The private EdDSA key was generated with Sparkle's `generate_keys` and stays in the local login Keychain under account `com.youssef.keep`. Only the matching public verification key is in Git. Make a secure backup before distributing Keep. Do not rotate the key casually after shipping: existing installations trust this public key. Do not put the private key in Git, app resources, chat, logs, or ordinary build arguments. Another release machine needs a secure Keychain import or a protected CI secret using Sparkle's documented key-file/stdin support.

Sparkle's EdDSA key verifies updates; it does not replace Apple's Developer ID signing and notarization for normal internet distribution. The first distributed app must already contain Sparkle and the correct feed/key.

## Publish a release

No release, appcast, GitHub workflow, or remote infrastructure is published by this integration. The feed will become available when a stable GitHub release contains the generated `appcast.xml` asset.

1. Increase `CURRENT_PROJECT_VERSION` for every update; use a monotonically increasing build number. Set `MARKETING_VERSION` for the user-visible version. Keep `com.youssef.keep`, the public key, and the feed URL stable.
2. Archive a **Release** app using the intended Developer ID signing identity. Sign nested Sparkle code through Xcode's normal embedding/signing workflow; preserve framework symlinks and XPC services. Notarize and staple the distribution artifact according to Apple's workflow. Inspect the shipped plist and entitlements, rather than assuming an unsigned Debug build validates distribution.
3. Package the final app as a DMG or ZIP supported by Sparkle. Use a fresh staging folder containing just that release's final archive. Optional release notes can have the same basename with `.md`, `.txt`, or `.html` extension.
4. Resolve the package using the project's Xcode scheme, then generate the feed with the bundled tools. Example for a hypothetical build 2 / tag `v1.1` (replace the tag and staging path):

```sh
xcodebuild -resolvePackageDependencies -project keep.xcodeproj -scheme keep \
  -derivedDataPath /tmp/keep-derived-data
sparkle_tools=/tmp/keep-derived-data/SourcePackages/artifacts/sparkle/Sparkle/bin
"$sparkle_tools/generate_appcast" --account com.youssef.keep \
  --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix https://github.com/youssefezzat304/keep/releases/download/v1.1/ \
  /path/to/release-staging
"$sparkle_tools/sign_update" --account com.youssef.keep --verify \
  /path/to/release-staging/appcast.xml
```

`generate_appcast` signs the archive and embeds a signature inside the XML feed because Keep requires signed feeds. There is no separate `.sig` asset. Embedded notes avoid a separate notes URL. Do not edit the feed or repackage the archive after signing; regenerate and verify if anything changes.

5. Prepare a stable GitHub release with the exact tag used in the download prefix. Upload the final archive and `appcast.xml` as assets before publishing; verify the enclosure filename/URL and build number. Keep this repository and release assets publicly readable. Every future stable release marked latest must include `appcast.xml`, since the installed app follows GitHub's latest-release redirect. Do not publish an unrelated latest release without that asset. Drafts and prereleases do not serve the stable latest endpoint.
6. Verify the public feed and enclosure URLs without authentication, including redirects. Test a real upgrade from the previously distributed app on a separate installation/account: discover → download → verify → install → relaunch. Check active and paused timers, Later/retry, final saved time, music shutdown, offline errors, and tampered-signature rejection. A local unsigned build or generated feed does not establish this end-to-end result.

This simple feed contains the latest compatible release and no deltas. If a later release raises the minimum macOS version or changes supported architectures, preserve older compatible feed entries and their immutable per-tag download URLs before publishing; use Sparkle's multi-version publishing workflow instead of regenerating a one-item feed. Generated outputs and archives belong outside the source checkout.

## Local verification

Build the unsigned Debug scheme using `docs/architecture.md`, then run:

```sh
python3 Tools/run-app-checks.py UpdaterChecks
```

The runner compiles current sources with Sparkle and copies the build's resources/framework into a temporary app with a distinct `local.keep.checks.*` identity. The updater checks validate configuration, Debug gating, exactly-once restart continuation, save-failure blocking, running/paused timer behavior, Flow-priority settlement, and native Sparkle startup/KVO/preference reload. They disable scheduling and never request a feed or install an update. Sparkle's host sandbox-extension probe can report an operation-not-permitted diagnostic in this unsigned fixture; these checks do not validate the signed sandbox installer.

Upstream references: [setup](https://sparkle-project.org/documentation/), [SwiftUI integration](https://sparkle-project.org/documentation/programmatic-setup/), [sandboxing](https://sparkle-project.org/documentation/sandboxing/), [publishing](https://sparkle-project.org/documentation/publishing/).
