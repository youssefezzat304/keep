# Keep — Decisions and Continuity

## [SNAPSHOT]

- 2026-10-05 [CODE] Goal: native macOS focus workspace; existing UI includes an active target, Pomodoro and flow panels, and task/music areas.
- 2026-10-05 [CODE] Current state: stateless UI prototype. Navigation and timer actions print messages; task/music cards are placeholders.
- 2026-10-05 [USER] Documentation lives in `docs/architecture.md`, `docs/decisions.md`, and `docs/style.md`; root `AGENTS.md` defines working rules.
- 2026-10-05 [USER] Keep agent guidance and architecture clearer as understanding of the project improves.
- 2026-10-05 [CODE] No persistence, external integrations, third-party packages, or test target currently configured.
- 2026-10-05 [USER] Visual direction: editorial restraint with the provided image's cozy palette; implementation is pending.
- 2026-10-05 [CODE] Next feature is UNCONFIRMED; this documentation task does not select a roadmap item.

## [DECISIONS]

### D001 ACTIVE — 2026-10-05 [USER]

Keep documentation in the existing lowercase `docs/` files and refine root `AGENTS.md` and `docs/architecture.md` as project understanding improves.

Ownership: agent rules in `AGENTS.md`, implemented structure and constraints in architecture, durable context here, and visual language in style. Avoid duplicate root-level or uppercase alternatives.

## [PROGRESS]

- 2026-10-05 [CODE] Established architecture documentation from all current Swift views, asset definitions, and the Xcode project. Documented actual composition and separated placeholders from functional behavior.

## [DISCOVERIES]

- 2026-10-05 [CODE] `WindowGroup` is present without an explicit cross-window state policy; decide ownership when introducing session state.
- 2026-10-05 [CODE] `PrimaryButton` owns a placeholder print action, and `NavBar` hard-codes labels. Real navigation needs caller-owned actions and routing state.
- 2026-10-05 [CODE] `TimerWorkspaceCard` does not use `CardStyle`; current layout includes fixed dimensions and no adaptive stacking or scrolling.

## [OUTCOMES]

- 2026-10-05 [CODE] Canonical document paths and evidence-based maintenance rules are established. Application behavior remains unchanged.

## [OPEN QUESTIONS]

These questions are not blockers for unrelated work; resolve them when the relevant feature is requested.

- 2026-10-05 [CODE] UNCONFIRMED: whether Pomodoro and flow sessions can run together, and their pause/reset/completion rules.
- 2026-10-05 [CODE] UNCONFIRMED: sleep/wake timing behavior, relaunch recovery, and window-local versus app-wide session ownership.
- 2026-10-05 [CODE] UNCONFIRMED: task/project relationship, target switching during a session, and storage requirements.
- 2026-10-05 [CODE] UNCONFIRMED: music source/provider, statistics scope, and supported appearance modes.

## [WORKING SET]

- 2026-10-05 [CODE] `AGENTS.md`
- 2026-10-05 [CODE] `docs/architecture.md`
- 2026-10-05 [CODE] `docs/decisions.md`
- 2026-10-05 [CODE] `docs/style.md`
- 2026-10-05 [CODE] `keep/App/`
- 2026-10-05 [CODE] `keep/Features/FocusSession/Views/`
- 2026-10-05 [CODE] `keep/DesignSystem/`
- 2026-10-05 [CODE] `keep.xcodeproj/project.pbxproj`

## [RECEIPTS]

- 2026-10-05 [TOOL] `xcodebuild -list -project keep.xcodeproj` succeeded: application target and scheme `keep`; Debug and Release configurations. This is project discovery, not a compilation check.
