# Keep — Visual Style Guide

Keep follows a **cozy retro editorial** direction: a quiet focus journal with warm paper surfaces, autumn colors, clear typography, and softly rounded cards.

Preserve the reference guide's editorial restraint while drawing the palette and warmth from `reference/main-theme.jpg`. The colors below are reference-inspired design choices, not exact sampled values. The image informs atmosphere, not a prescribed dashboard layout.

Keywords: **cozy · warm · editorial · autumnal · calm · tactile · understated**.

## 1. General direction

Let typography, warm neutrals, deliberate spacing, and restrained accent colors carry the identity. The active focus target and timer should be easy to find; tasks and music should feel supportive rather than compete for attention.

Use broad cream surfaces and terracotta emphasis. The outer window backdrop takes its colors from the music artwork, heavily blurred into a soft gradient-like wash; keep the main panel opaque with a quiet tint from the same artwork for readable controls. Sage, butter yellow, and mist blue provide quiet secondary variation. Keep the interface comfortable for long focus sessions.

## 2. Color palette

Use semantic tokens rather than independent colors in each view.

| Token | Light value | Role |
| --- | --- | --- |
| `background` | `#F7D2B8` | Soft peach fallback beneath the artwork backdrop |
| `paper` | `#FCF7EB` | Warm cream primary workspace |
| `surface` | `#FFFCF6` | Lighter cards, fields, and transient surfaces |
| `foreground` | `#332D29` | Warm charcoal primary ink |
| `secondaryForeground` | `#51463E` | Supporting text and icons |
| `mutedForeground` | `#74665B` | Metadata and helper text on light surfaces |
| `mutedWarm` | `#E8D7BF` | Neutral chips, inactive fills, and quiet details |
| `warmHighlight` | `#F4DEA4` | Butter-yellow emphasis and selected content |
| `accent` | `#E77D59` | Terracotta/coral primary action and active emphasis |
| `accentForeground` | `#332D29` | Dark labels and icons on terracotta |
| `accentStrong` | `#A3472F` | Dark terracotta text, links, or an alternate filled action |
| `accentStrongForeground` | `#FFFCF6` | Light content on the darker terracotta fill |
| `sage` | `#C6D8BE` | Gentle supporting card fill or completion background |
| `sageForeground` | `#43563C` | Text and icons on sage |
| `mistBlue` | `#D6E6E7` | Quiet secondary panel or informational fill |
| `mistBlueForeground` | `#405A5C` | Text and icons on mist blue |
| `border` | `#DECDBB` | Decorative card separators and subtle frames |
| `controlBorder` | `#95816F` | Boundaries needed to identify interactive controls |
| `focusRing` | `#6E3022` | Visible keyboard focus on light surfaces |
| `danger` | `#A13F32` | Destructive actions and error text on light surfaces |

The base terracotta is intentionally soft. Use dark ink on it: small white text on the base coral does not provide enough contrast. Use the deeper `accentStrong` fill when a light foreground is needed.

Use `mutedForeground` primarily on `paper` and `surface`; use stronger ink for text on peach or colored fills. The quiet `border` is decorative, not a substitute for a sufficiently visible interactive boundary.

## 3. Semantic color usage

Centralize colors in named asset-catalog colors or a shared theme namespace under `keep/DesignSystem/`. Choose one source of truth and have any helpers reference it.

Named color assets are the source of truth. `keep/DesignSystem/KeepTheme.swift` exposes semantic references to them; use those references in views.

Project identity uses 30 selectable colors: the existing terracotta, sage, mist blue, and butter yellow, plus 26 muted warm, green, blue, purple, and neutral hues in `Project*.colorset` assets. `FocusProjectStyle` maps the saved accent to its asset. These colors identify projects. Match the folder icon and project names in the active target, picker, and Timesheet to their project hue; adjust lightness for readable shades in Light and Dark. Keep other text/actions on the semantic palette above. Color selection uses a visible checkmark and named accessibility labels.

```swift
Text("Start focus")
    .foregroundStyle(KeepTheme.ink)
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
    .background(KeepTheme.accent, in: RoundedRectangle(cornerRadius: 12))
```

`AccentColor` and the other colors used by the first draft are populated. Keep theme additions in the same asset/namespace pattern rather than declaring independent palettes in feature views.

Avoid scattered RGB literals, generic `.red`/`.blue` card fills, and opacity adjustments that accidentally weaken text contrast. A palette change should be possible through shared tokens.

## 4. Typography

Use two complementary roles:

1. A restrained serif for editorial headings and occasional prominent numbers.
2. A clean sans-serif for controls, task content, metadata, and navigation.

Start with native system fonts rather than adding font dependencies. SwiftUI's system serif design can supply the editorial role; the default system design supplies functional text. Custom fonts require a clear visual reason, suitable licensing, and reliable fallbacks.

```swift
Text("Today's focus")
    .font(.system(.largeTitle, design: .serif))

Text("Current task")
    .font(.body)
```

## 5. Typographic character

Prefer expressive but calm headings, regular or medium utility text, and a clear hierarchy. Use subtle tracking for occasional short labels.

Avoid decorative scripts, futuristic display fonts, excessive uppercase, and a large number of font weights. The cozy palette should not make the interface childish.

## 6. Body text

Comfort and legibility take priority over density. Start around 15–17 points for ordinary workspace content, with larger sizes for extended reading or explanatory text. Use semantic text styles where appropriate and allow multiline content to wrap.

Give longer text comfortable line spacing. Do not shrink task text or helper text to make a rigid card fit; adapt the layout instead.

## 7. Micro-labels and metadata

Use understated sans-serif captions for session mode, task counts, elapsed time labels, and music details. A starting range is 12–13 points, with sufficient contrast on the actual surface.

Examples:

```text
CURRENT TASK
POMODORO
ELAPSED TIME
```

Use uppercase sparingly. Avoid pale reference-image labels that become difficult to read at real application sizes.

## 8. Expressive numbers and timers

The timer is a primary visual anchor. Use generous sizing that adapts to the available window space. A serif can work for static statistics, but running timer digits should prioritize easy scanning and stable widths.

```swift
Text("25:00")
    .font(.system(size: 72, weight: .regular))
    .monospacedDigit()
```

Treat the size as a starting point, not a universal fixed value. Do not announce every second to assistive technologies or animate every digit change decoratively.

## 9. Flat visual treatment and layout

Use solid fills, quiet borders, clean shapes, and generous negative space. The feeling of paper should come from cream color and typography, without literal paper textures.

Within Keep's existing shell, establish a clear progression from navigation to active target to timer to supporting cards. Do not copy the reference image's sidebar, profile, holiday lists, or illustrations unless separately requested.

Prefer an 8-point spacing rhythm, with 16–24 points inside cards and 24–32 points between major regions. Adapt spacing to window size rather than stacking fixed widths and heights that cause clipping.

Check the default 1000 × 900 window, the previous 900 × 800 size, and smaller supported sizes. Reflow or provide scrolling when content cannot fit comfortably.

## 10. Corners

Use soft rounding that echoes the image without turning every control into a pill.

| Role | Starting radius |
| --- | --- |
| Compact fields and small controls | 8 pt |
| Buttons | 12 pt |
| Cards | 20 pt |
| Large workspace surfaces | 24–28 pt |

The existing 12-point button and 20-point card radii fit this direction. Use pills only for compact statuses or selections where the shape is useful.

## 11. Shadows

Most cards need no shadow. Separate regions with warm surface colors, spacing, and occasional borders.

Use a soft, low-opacity warm shadow only when a popover, menu, or dialog needs layering. Avoid heavy dark outlines.

The outer artwork color wash and the music card are explicit exceptions to the otherwise flat treatment: the user requested controls floating on a blurry card over cozy artwork. Use a crop of the actual player artwork behind its controls, aligned with the image beneath, rather than a native material that picks up the outer window backdrop. Glassiness runs from solid paper to clear artwork by reducing both blur and paper opacity continuously; retain an appearance-specific readability wash, stronger in Dark so cream text remains readable over bright images. Liquid Glass adds Apple’s clear glass treatment over the artwork-backed panel. Respect Reduce Transparency with an opaque paper fallback in the active appearance, and keep text readable regardless of the artwork behind it. Glassiness is a continuous native slider with a warm theme-colored track. Decorative borders must not intercept pointer input.

Music favorites use an outline heart for unsaved sources and a filled heart for saved sources. Use circular hover/focus backgrounds for the heart and clean `list.bullet` icon. The saved-list button expands the glass panel upward within the card’s existing bounds, revealing a scrollable artist/playlist list. When space is tight, the list replaces track details and transport controls; keep the toggle visible in its heading and keep playback running. Larger cards show the list and transport together. Never grow the artwork card or outer page to accommodate favorites. Use a gentle 250 ms expansion/collapse and honor Reduce Motion. Selecting a saved listen starts playback and leaves the list visible until the same icon is toggled again. Place Audius attribution at the top-left of the artwork and the passive source menu in a 46-point circular bookmark button at the top-right, matching timer corner controls.

The window backdrop uses the same selected image and fallback as the player. Blur it enough that objects and edges disappear; clamp image edges before blurring to avoid blank window edges. Generate a small blurred texture off the main actor and scale it smoothly to fill the window. Light appearance adds a subtle paper wash, while Dark adds an espresso tint. Keep panel margins and opacity unchanged. Blend a small ambient tint into the paper panel, and blend distinct sampled artwork hues into the terracotta Pomodoro and sage Flow fills. Breaks keep a butter base with an ambient tint. Use lighter or darker semantic bases according to appearance and limit tinting before it weakens text contrast; labels still distinguish the timers.

## 12. Buttons and controls

- Use terracotta with dark ink for the main action.
- Use cream or warm-neutral fills for secondary actions.
- Use sage or a clear checkmark for completed states.
- Keep destructive actions distinct from ordinary terracotta actions through wording and the `danger` token.
- Provide visible hover, pressed, selected, disabled, and keyboard-focus states.

Use native `Button`, `Toggle`, text fields, and other controls for behavior and accessibility. If a custom `ButtonStyle` is needed, centralize it in the design system and preserve keyboard operation and focus feedback.

Settings uses a centered column, rounded paper menu buttons and fields, terracotta selected appearance choices, and native switches. Use the same warm buttons in the task calendar: roomy weekday/date cells, a terracotta selection, a Today dot, and muted adjacent-month dates. Keep the calendar inside a native popover while styling its contents in SwiftUI. Avoid the default graphical date-picker chrome.

Dashboard uses a compact Timesheet / Calendar switch with rounded paper surroundings and terracotta selection. The weekly Calendar keeps cream hour-grid surfaces, fine warm rules, subtly shaded weekends, and a terracotta Today marker. Session blocks use soft project-color fills, readable ink, a narrow colored edge, and restrained task/project/duration text. Keep the weekday headers visible above the scrolling timeline; clearly label sample sessions while the Calendar remains a visual draft.

Avoid glossy fills, oversized shadows, and subtle color changes as the only indication of interaction. Make pointer targets comfortable, generally around 36–44 points high for primary controls.

## 13. Selection, tasks, and session emphasis

Use `warmHighlight` for restrained selected-content emphasis. Use sage with readable ink for completion or supportive status. Use terracotta to identify the active session or selected navigation item sparingly.

Task completion should also have a checkmark or explicit state. Pomodoro and flow modes need labels, not just different colors. Keep selected task titles legible even when struck through.

## 14. Graphics and data visualization

If statistics are implemented, use simple bars, lines, dots, or progress rings. Label values and states directly, and use the same semantic palette as the rest of the app.

Reserve terracotta for the main metric and use sage, butter yellow, or mist blue as supporting series where contrast permits. Add symbols, labels, or patterns when color alone would be ambiguous.

Avoid pseudo-3D charts, gradient fills, excessive decoration, and speculative analytics widgets.

## 15. Icons and illustrations

Prefer consistent SF Symbols for functional controls. Use a restrained weight and scale, and provide accessible labels for icon-only actions.

The reference's autumn illustrations contribute warmth, but illustrations are optional. If requested, keep them flat, simple, and within the warm palette; they should never obstruct timer information or task controls.

## 16. Motion

Use brief, quiet state transitions, generally around 120–200 milliseconds. Motion should explain selection, expansion, or a session state change.

Avoid bouncing controls, continuous decorative movement, and animated countdown digits that distract from focus. Respect the system Reduce Motion preference and provide an immediate-state alternative where appropriate.

## 17. SwiftUI implementation

Use SwiftUI composition and shared design-system components rather than a parallel styling framework.

- Keep global color, typography, spacing, and radius choices centralized when reused.
- Evolve `CardStyle` and `PrimaryButton` for shared appearance rather than duplicating their styling in every feature view.
- Keep feature actions outside shared styling components.
- Prefer flexible frames, layout priorities, and sensible wrapping over fixed card heights that crop content.
- Preserve useful previews with realistic long task names and representative states when behavior exists.

Do not add a web renderer, Tailwind, CSS tokens, or shadcn/ui to implement this visual guide. Its semantic-token principles translate to SwiftUI and asset catalogs.

## 18. Appearance modes

Settings offers Light, Dark, and System. Light is the default and keeps the palette above; System follows macOS. Named assets supply explicit dark variants. Popovers and sheets inherit the shell’s selection.

| Semantic asset | Dark value |
| --- | --- |
| Background / Paper / Surface | `#211A17` / `#2C2522` / `#342C28` |
| Foreground / SecondaryForeground / MutedForeground | `#F4ECDF` / `#D8C8B9` / `#B9A79A` |
| MutedWarm / WarmHighlight | `#4C3E34` / `#584726` |
| AccentColor / AccentStrong | `#864732` / `#E9A386` |
| Sage / SageForeground / MistBlue | `#344B3A` / `#D9E8D0` / `#30484B` |
| Border / ControlBorder / FocusRing | `#59483E` / `#AA8D76` / `#F3BD8F` |

Dark appearance uses espresso surroundings, brown paper, cream ink, and muted coral/sage fills. AccentStrong becomes a light coral for readable links/actions on dark surfaces. Do not reuse light pastel panels behind cream text. The music control surface keeps sufficient warm tint over arbitrary artwork; Reduce Transparency always forces opaque paper in the active appearance.

## 19. Native macOS behavior

Custom appearance should preserve native usability: keyboard navigation, focus, standard shortcuts where applicable, text selection, menu behavior, and appropriate accessibility semantics.

Use native menus, popovers, and dialogs when they provide useful behavior. Adapt their surrounding typography and tokens where supported without replacing them solely to force a visual treatment.

## 20. Accessibility

- Target at least 4.5:1 contrast for ordinary text and 3:1 for large text.
- Provide at least 3:1 contrast for essential control boundaries, icons, and focus indicators against adjacent colors.
- Keep keyboard focus visible and interactions keyboard-operable.
- Use meaningful labels, state descriptions, and semantic controls for VoiceOver.
- Support system accessibility settings, including Reduce Motion and Increase Contrast where relevant.
- Never encode task completion, mode, selection, or errors through color alone.

Verify actual foreground/background combinations, including hover and disabled states. Pastel decorative fills do not excuse unreadable text or invisible controls.

## 21. Things to avoid

- Neon colors, cold blue/purple AI gradients, and gradient text.
- Glass effects, gloss, heavy shadows, and fake depth.
- Saturated red and blue placeholder cards as finished styling.
- Excessive badges, pills, icons, and decoration.
- Literal paper textures, ornate serif text, or cartoon styling throughout the UI.
- Low-contrast pale text copied from the reference image.
- Layout changes made solely to imitate unrelated reference content.

## 22. Final style test

Before completing a UI change, check that it feels like a calm focus journal: peach surroundings, cream workspace, warm ink, terracotta emphasis, soft supporting colors, and restrained editorial typography.

The timer and active task should be immediately clear. Supporting areas should be readable, comfortable, and quiet. Confirm the appearance in the affected window sizes and states before calling the visual work complete.
