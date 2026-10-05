# Keep — Architecture

Keep is a native macOS focus workspace built with SwiftUI. This document describes the verified implementation and the boundaries to preserve as behavior is added. It is not a roadmap or a claim that the displayed features are functional.

## 1. Current implementation

The application is an early UI prototype with one application target and a single root view composition. All current views are stateless: there are no session models, observable stores, action bindings, persistence services, or external integrations.

| Area | Implemented today | Missing behavior |
| --- | --- | --- |
| App window | `WindowGroup` displaying `AppShellView`; default size 900 × 800 | No explicit policy for sharing state across windows |
| Navigation | Home, Stats, and Settings buttons | No route state or destination views; all buttons print `clicked` |
| Active target | `Untitled` label and Change button | No project/task model or picker; Change prints a message |
| Pomodoro | Static `25:00` label and Start button | No countdown or lifecycle; Start prints a message |
| Flow timer | Static `00:00:00` label and Start button | No elapsed-time tracking or lifecycle; Start prints a message |
| Music | Placeholder card | No playback controls, audio source, or provider |
| Tasks | Placeholder card | No task input, list, completion, or storage |
| Design system | Shared button view and card modifier | No central theme or populated accent color; cozy styling is specified in `docs/style.md` |

Navigation, timer, task, and music labels indicate intended UI areas. They do not settle requirements such as timer exclusivity, music-provider choice, or persistence strategy.

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
    KeepApp.swift                  @main entry point, WindowGroup, default window size
    AppShellView.swift             Navigation and focus-workspace composition
  DesignSystem/
    Components/
      NavBar.swift                 Shared navigation presentation
      PrimaryButton.swift          Shared button appearance; placeholder action
    Modifiers/
      CardStyle.swift              Shared card treatment and View.cardStyle extension
  Features/
    FocusSession/
      Views/                       Focus workspace and its constituent panels
  Assets.xcassets/                  AppIcon and AccentColor asset definitions
reference/                         Local, Git-ignored visual references
```

All Swift sources belong to the same application module. Directory boundaries express responsibility, not separate packages or targets. The `keep` source directory is a filesystem-synchronized Xcode group; documentation and reference images sit outside it.

## 3. View composition

```text
keepApp
└── WindowGroup
    └── AppShellView
        ├── NavBar
        │   └── PrimaryButton × 3: Home, Stats, Settings
        └── FocusSessionView
            ├── ActiveTargetHeader
            ├── TimerWorkspaceCard
            │   ├── PomodoroTimerPanel
            │   └── FlowTimerPanel
            └── HStack
                ├── MusicPlayerCard → cardStyle
                └── TasksCard → cardStyle
```

`TimerWorkspaceCard` currently composes two timer panels with padding; despite its name, it does not apply the shared card modifier. `NavBar` currently lives in the design system but hard-codes destination labels. Revisit its ownership or inputs when real navigation is implemented rather than making reusable controls own routing.

## 4. Responsibility and dependency boundaries

| Location | Owns | Keep outside it |
| --- | --- | --- |
| `App` | Launch, window composition, and future app-wide navigation or dependency assembly | Feature timing calculations and provider-specific logic |
| `Features/FocusSession` | Focus UI and future session-specific state, actions, and rules | Generic styles and unrelated feature behavior |
| `DesignSystem` | Reusable presentation, control styles, layout conventions, and theme tokens | Session state, persistence, provider calls, and feature actions |
| `Assets.xcassets` | Named colors and bundled visual resources | Domain behavior and credentials |

The current composition is `App` → feature views and design-system views; feature views reuse the design system. Future business logic should remain independent of the visual components that display it. A shared button should receive an action from its caller.

There is no established MVVM layer, repository abstraction, service container, or package decomposition. Add a model or service only when implemented behavior needs it. Place feature-owned additions with the feature; introduce a shared boundary only when there is a concrete cross-feature need.

## 5. State and data ownership

There is no runtime state flow to document yet: values are literals and actions only print messages. No data is saved between launches.

When behavior is introduced:

- Give each session, active target, and task collection one explicit owner. Child views receive values and bindings or action closures as appropriate.
- Keep elapsed/remaining-time calculations in testable timing logic, separate from display refreshes and SwiftUI layout.
- Record the actual session lifecycle and clock semantics once chosen, including pause/resume and sleep/wake behavior.
- Decide whether state belongs to one window or the whole application before sharing it across the existing `WindowGroup`.
- Document any persistence or external integration at the point it is implemented, including its data boundary and failure behavior.

These are implementation constraints, not existing model or service APIs. Pomodoro/flow exclusivity, target switching during a session, recovery after relaunch, and the music source remain open questions in `docs/decisions.md`.

## 6. Visual implementation and layout constraints

`docs/style.md` defines the target cozy editorial appearance. The current code uses a fixed white shell, gray buttons, red music card, and blue task card. `AccentColor` has an asset entry without color components. There is no `KeepTheme` implementation or explicit appearance policy.

Existing layout constraints include:

- A 900 × 800 default window, without an explicit app-level minimum window size.
- A focus view minimum width of 700 points, with additional nested padding in the shell and feature view.
- A 50-point fixed target-header height and large fixed timer font sizes.
- Side-by-side music and task cards; no adaptive stacking or scroll container.
- A shared card frame constrained to 100–500 points wide and 100–350 points high, with a 20-point corner radius.

These are source-level constraints, not verified reports of visual defects. Inspect previews or the running app when changing layout, especially for narrow windows, long task names, and supporting content growth. Define shared semantic styling in the design system or asset catalog when the palette is implemented.

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
| Info.plist | Generated by Xcode |
| Third-party package products | None |

The language-mode setting does not identify the installed Swift compiler. Project metadata does not prove SDK availability or that a build succeeds on a given machine. Check the installed toolchain when compatibility matters.

There is no test target, configured lint/format tool, persistence framework, backend, or network/music integration. Sandbox settings do not imply that a file-import feature exists; adding capabilities requires a concrete feature need.

## 8. Development and verification

Run commands from the repository root:

```sh
open keep.xcodeproj
xcodebuild -list -project keep.xcodeproj
xcodebuild -project keep.xcodeproj -scheme keep -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/keep-derived-data \
  CODE_SIGNING_ALLOWED=NO build
```

The scheme and target were confirmed with `xcodebuild -list` on 2026-10-05. No compilation or runtime verification was performed for this documentation baseline. The unsigned build command is a development workflow, not evidence of a successful build or release-signing validation.

Use previews or the running macOS app to verify appearance and interaction. Add focused tests when meaningful domain behavior is introduced, then document the actual test target and commands. Do not invent test or lint checks before they exist.

## 9. Maintaining this document

Update this document when new source understanding or implementation changes component responsibilities, view composition, state/data ownership, dependencies, build workflow, or important constraints. Replace stale descriptions, keep supporting paths accurate, and distinguish implemented behavior from proposals.

Put agent working rules in `AGENTS.md`, visual rules in `docs/style.md`, and the reason/history behind durable choices in `docs/decisions.md`. Avoid copying their detailed contents here. Product choices that remain unresolved belong in the ledger rather than being presented as settled architecture.
