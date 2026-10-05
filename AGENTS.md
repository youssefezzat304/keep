# Keep — Codex Project Guidance

Keep is a native macOS focus workspace built with SwiftUI. Its interface brings together an active project or task, Pomodoro and flow timers, a music area, and a task area.

This file defines the working agreements for Codex in this repository. Distinguish the existing UI prototype from implemented product behavior.

## 1. Project goals

Build a small, reliable focus experience before expanding the product or infrastructure.

The intended core flow, based on the current interface, is:

1. Choose the project or task to focus on.
2. Start a Pomodoro countdown or a flow timer.
3. See the active session and its controls clearly.
4. Use the supporting task and music areas when their behavior is implemented.

This flow describes the direction suggested by the interface, not completed functionality or a full product specification. See `docs/architecture.md` for the verified implementation state and `docs/decisions.md` for durable decisions and unresolved questions. Do not describe placeholders as working features.

Detailed session history, statistics, notifications, music integrations, accounts, and sync require their own scoped work. Do not add them merely because they could be useful. Project/day time totals and manual edits now persist locally.

## 2. Technology and architecture

- Swift and SwiftUI.
- A native macOS application managed through Xcode.
- Asset catalogs and SwiftUI previews.

Read `docs/architecture.md` for source boundaries, current dependencies, and build configuration. Verify relevant settings in `keep.xcodeproj/project.pbxproj` before making compatibility decisions.

Preserve the native SwiftUI approach. Do not add a web stack, package manager, backend, or cross-platform framework without an explicit architectural need agreed with the user.

## 3. Read the canonical documents

Before non-trivial work, read:

- `docs/decisions.md` — durable decisions, current snapshot, and open questions.
- Relevant sections of `docs/architecture.md` — implemented structure, responsibilities, and constraints.
- `docs/style.md` before UI or styling work — canonical visual direction and design tokens.
- The source files affected by the task; use the architecture document as a map, not a substitute for inspecting code.

Use the exact lowercase documentation paths. Do not create root-level duplicates or uppercase alternatives. There is no separate product specification yet; do not invent requirements to fill that gap.

When documentation and implementation disagree, inspect the source, distinguish intended behavior from current behavior, and correct stale factual documentation within the task's scope. Flag unresolved product or architectural conflicts. The style guide owns visual intent; use shared theme tokens rather than treating incidental colors as new palette decisions.

## 4. Code quality

- Prefer simple Swift code and the smallest coherent change that satisfies the task.
- Preserve repository conventions and avoid unrelated refactors.
- Reuse existing components where appropriate.
- Remove dead code created by the change; do not leave commented-out alternatives.
- Model meaningful states with explicit types and enums rather than unrelated Boolean flags.
- Avoid force unwraps, forced casts, and silently discarded errors.
- Keep user-facing error messages actionable and separate from diagnostic logging.
- Never represent placeholder behavior as a completed feature.

## 5. SwiftUI and state ownership

- Keep views focused on presentation, composition, and user interaction.
- Keep reusable UI in `DesignSystem`; keep feature-specific UI and logic with its feature.
- Introduce models or services when behavior warrants them, without creating speculative architecture.
- Use `@State` for view-owned state, bindings for state passed to child views, and observation when shared feature state requires it.
- Give each piece of state a clear owner; avoid duplicate sources of truth.
- Pass action closures into reusable controls instead of hard-coding feature actions or print statements.
- Avoid expensive work and side effects in `body`.
- Use structured concurrency for asynchronous work and handle cancellation and view lifecycle changes.
- Respect the project's actor-isolation settings. Keep UI mutations on the main actor and avoid blocking it with I/O or heavy work.
- Prefer native SwiftUI controls and behavior; use AppKit bridges only when a concrete macOS requirement calls for them.

## 6. Focus-session behavior

When timer behavior is requested:

- Model idle, running, paused, and completed states explicitly where applicable.
- Define the relationship between Pomodoro and flow sessions before coupling their state.
- Derive elapsed or remaining time from an appropriate clock and recorded timing state. Do not assume every UI timer tick arrives on time.
- Treat display refreshes separately from the source of timing truth.
- Define pause, resume, reset, completion, sleep, and wake behavior for the requested scope.
- Avoid duplicate ticking tasks and cancel work when its owner ends.
- Make session completion and any notifications predictable and testable.

Pomodoro and flow controls are independent and may run concurrently. Recorded time uses a single app-owned recorder: running Flow takes priority; otherwise only Pomodoro focus counts. Manual Pomodoro breaks never add Pomodoro time. Route timer actions, project changes, and Timesheet edits through `WorkspaceModel` so elapsed time is settled before state changes. Preserve these rules. Consult `docs/architecture.md` for the implemented timing semantics and state lifetime.

Do not add notification permissions, background services, persistence, or music-provider integrations as incidental parts of a visual task.

## 7. Dependencies

Before adding a dependency:

1. Check SwiftUI, Foundation, and other existing Apple frameworks.
2. Check whether the repository already supplies the capability.
3. Verify compatibility with the installed toolchain and deployment target.
4. Prefer a small, maintained package that materially simplifies the work.
5. Explain meaningful dependency additions in the final response.

Use Swift Package Manager through the project's Xcode workflow when needed. Preserve generated package-resolution files when packages are introduced. Do not introduce CocoaPods, Carthage, or Node tooling for ordinary development.

## 8. Commands and Xcode workflow

Run commands from the repository root using the workflow in `docs/architecture.md`. Confirm available schemes before relying on them. A local unsigned build checks compilation; it does not validate release signing, sandbox permissions, or distribution.

Use the actual configured checks; do not claim nonexistent test, lint, or formatting commands passed. Prefer adding Swift files to the appropriate existing directory rather than unnecessary manual edits to the filesystem-synchronized Xcode group.

Do not commit DerivedData, build products, or personal Xcode user state. Preserve unrelated user changes.

## 9. Accuracy, recency, and sourcing

For SDK availability, framework APIs, package compatibility, distribution requirements, or other time-sensitive facts:

- Establish the current date and inspect the installed Xcode/SDK versions as needed.
- Prefer Apple documentation, installed SDK declarations, and upstream package documentation matching the project version.
- Use available documentation tools such as Context7 only when they cover the relevant library.
- Verify changing or uncertain technical claims with authoritative sources.
- Do not research unrelated topics when the repository already provides the needed answer.

Do not raise or lower the deployment target just to make an example compile without considering the product's compatibility requirements.

## 10. Remote services and production safety

Use read-only remote operations unless the task authorizes a mutation. Inspect before destructive actions and use a dry run when available.

Do not publish releases, change remote repositories or infrastructure, send messages, delete production data, or incur paid API usage without authorization. Existing authorization in the session applies; do not request it repeatedly.

Ordinary local edits, builds, and reversible verification are part of the development workflow.

## 11. Secrets, privacy, and capabilities

- Never print or commit credentials, access tokens, signing secrets, or private keys.
- Do not dump the entire environment or request secrets in chat when a safer authenticated workflow exists.
- If credentials become necessary, use an appropriate secure configuration or Keychain workflow; do not embed private credentials in the shipped app.
- Keep private local configuration out of Git.
- Treat imported files, URLs, and remote responses as untrusted input; validate at their boundaries using appropriate Swift types and decoding.
- Request only capabilities needed by the task. Preserve sandbox and signing settings unless a requested feature requires a documented change.
- Do not log personal task content or session data unnecessarily.

## 12. Host tools and containers

Use the native macOS/Xcode workflow. Ordinary app development does not require containers, Dockerfiles, or service infrastructure.

Do not install system packages or change the selected Xcode installation without user authorization. Inspect the current toolchain first and explain any actual requirement that cannot be satisfied with installed tools.

## 13. Reading documents and references

Read enough of a source to understand the relevant context. Do not infer unseen content or invent product requirements.

Inspect visual references when a task depends on their appearance. Use `docs/style.md` for semantic design rules and the images for visual context; do not copy unrelated reference content into Keep. The reference images are local and Git-ignored, so do not assume they exist in every checkout.

## 14. Baseline workflow and planning

For a non-trivial task:

1. Determine the goal and acceptance criteria from the request and repository.
2. Read `docs/decisions.md` and the relevant sections of `docs/architecture.md`.
3. Read applicable guidance, relevant source, and `docs/style.md` for visual work.
4. Identify affected feature, design-system, and project boundaries.
5. Resolve uncertainty from the repository before asking unnecessary questions.
6. Implement the smallest coherent change.
7. Verify behavior and appearance at the appropriate level.
8. Update the canonical documents when implementation or new findings change durable project knowledge.

Use a short execution plan for complex work. Ask for clarification when a material product or architectural choice remains unresolved; continue independent work where possible.

## 15. Continuity ledger

The canonical continuity ledger is `docs/decisions.md`. Read it for non-trivial work. Do not maintain a second ledger.

Update it for meaningful product, architecture, constraint, or implementation-direction changes. Record existing implementation as `[CODE]` evidence; do not turn a suggestion or inference into an approved `[USER]` decision.

Use these sections as needed:

```text
[SNAPSHOT]
[DECISIONS]
[PROGRESS]
[DISCOVERIES]
[OUTCOMES]
[WORKING SET]
[RECEIPTS]
```

Keep the snapshot to roughly 25 lines and the active working set to roughly 12 paths. Record ISO dates and provenance tags (`[USER]`, `[CODE]`, `[TOOL]`, or `[ASSUMPTION]`). Mark unknowns `UNCONFIRMED`. Preserve superseded decisions explicitly rather than rewriting history.

Keep recent milestones and command outcomes concise. Compress older history; do not store transcripts, raw logs, or a micro-task checklist.

## 16. Testing and verification

- For source changes, run an appropriate Xcode build when the installed toolchain supports the project.
- For timer state, persistence, or other significant domain logic, add or run focused tests that verify behavior rather than implementation details.
- For UI changes, inspect the affected SwiftUI previews or running app at relevant window sizes, including the default size documented in `docs/architecture.md` and a narrow window.
- Check keyboard operation, focus visibility, labels, contrast, text clipping, and appearance modes affected by the change.
- Avoid adding tests solely for reversible documentation or cosmetic edits.
- Fix errors introduced by the change without expanding into unrelated refactoring.
- Report exactly what ran. If verification is blocked, state the toolchain or other limitation and what remains unverified.

## 17. Documentation ownership

- `AGENTS.md` owns agent working agreements.
- `docs/architecture.md` owns the source map, component responsibilities, state and data ownership, build workflow, and verified implementation constraints.
- `docs/decisions.md` owns durable decisions, current snapshot, significant findings, and unresolved questions.
- `docs/style.md` owns visual language, palette, typography, and UI implementation guidance.
- Source and `keep.xcodeproj` provide evidence of the actual implementation and build configuration.

As understanding of Keep improves, make `AGENTS.md` and `docs/architecture.md` clearer within the same task:

- Replace vague guidance with specific rules supported by source or explicit user decisions.
- Update architecture when responsibilities, state ownership, dependencies, setup, or constraints change, or when a significant discovery corrects an earlier description.
- Update agent guidance when a discovery changes how future work should be done.
- Keep current implementation, agreed direction, and open questions distinct. Remove obsolete statements and consolidate duplicates.
- Record the evidence or durable decision in `docs/decisions.md` when meaningful.

Do not edit every document after every task. Routine cosmetic changes and trivial fixes do not require ledger entries. Keep stable working rules here and detailed implementation facts in architecture so they can be maintained in one place.

## 18. Definition of done

A task is complete when the requested change is implemented, relevant verification has run, new errors are addressed, and necessary documentation is updated.

The final response should state what changed, where, how it was verified, and any material limitation. Do not claim completion of functionality that remains a placeholder or verification that did not run.

## 19. Current project direction

Focus and Timesheet share the app-owned `WorkspaceModel` and project catalog. Recorded project/day totals and manual edits persist locally; timer runtime and task-list state are not restored after quitting. Keep numeric fixtures in `keep/Features/Timesheet/PreviewData/` for previews only. Never seed the live ledger with sample history or store separately calculated totals.

Preserve one recorder and one persistence owner across tabs and windows. Test overlap, focus/break exclusion, edits during recording, project changes, day boundaries, and reloads when changing recording behavior. Do not reintroduce direct timer bindings that bypass settlement.

Preserve the native macOS focus-workspace structure. Follow `docs/style.md` for the cozy editorial visual direction. Treat the reference images as inspiration rather than a mandate to reproduce their page structure.

Do not replace established technologies or introduce speculative features as part of unrelated work.

## 20. Commit messages

After a completed code or documentation task, suggest one concise Conventional Commits message:

```text
<type>(<optional scope>): <short imperative description>
```

Examples:

```text
feat(timer): add Pomodoro pause and resume
fix(session): preserve elapsed time after wake
docs: add project guidance and cozy visual style
```
