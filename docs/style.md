# Keep — Visual Style Guide

Keep follows a cozy, friendly direction: warm paper, autumn colors, clear typography, softly rounded cards, and generous quiet space. `reference/main-theme.jpg` informs atmosphere and palette, not a prescribed page layout.

## 1. Visual hierarchy

Typography, warm neutrals, spacing, and restrained accents carry the identity. The active target and timers are the primary anchors; tasks and music support them. Use a cream workspace over a heavily blurred artwork backdrop. Keep the normal panel opaque with a quiet tint from the same image, so controls remain readable during long focus sessions.

Terracotta identifies important actions and active selections. Sage, butter, mist blue, and existing project accents provide variation without turning every region into a competing accent. Let content and hierarchy determine emphasis. Avoid adding decorative copy, badges, illustrations, or controls solely to fill empty space.

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

## 3. Tokens and project identity

Named asset-catalog colors are authoritative; KeepTheme exposes semantic references. Reuse shared tokens instead of scattered RGB literals, generic color fills, or independent feature palettes. Opacity must not weaken text or interactive boundaries.

Project identity uses the saved accent mapped by FocusProjectStyle. Match project names and folder marks across the active target, picker, Timesheet, Calendar, and project catalog. Preserve hue while adjusting lightness for readable Light/Dark shades. Other text/actions remain on the semantic palette. Color choices need names and an explicit selected state; color alone is insufficient.

Project management uses a standalone terracotta Add project button beside Dashboard’s view switch, matching Add habit. Row edit/delete controls retain accessible labels. Create/edit sheets share Keep’s rounded headings, paper surface and action styles; deletion uses the same treatment. A fixed dark charcoal `ProjectUsedColorRing` marks used colors in both appearances without disabling selection; selected checks and keyboard focus remain separate markers.

Use stronger ink on peach or colored fills. Quiet borders separate decoration; essential controls need the stronger control-boundary token. Preserve the distinction between normal, selected, focused, disabled, and destructive states rather than relying on subtle hue shifts.

## 4. Typography

Use the native rounded system font through `KeepTheme.headingFont` for headings, the wordmark and occasional static statistics. Keep regular or medium weights for a light, friendly feel. Use system sans-serif for controls, tasks, navigation, and metadata. Running timers use clean, stable-width monospaced digits. Custom fonts need a visual reason, licensing, and fallbacks.

Prefer calm expressive headings, regular/medium utility text, and few weights. Use subtle tracking for short labels, uppercase sparingly, and no decorative scripts or futuristic display fonts. Keep the interface relaxed and clear, without heavy or formal display type.

Ordinary content starts around 15–17 points; metadata around 12–13. These are starting ranges, not rigid sizes: preserve readability, wrapping, and comfortable line spacing. Do not shrink task or helper text to fit a fixed card. Timer digits adapt to their available column and should remain easy to scan. Do not animate every digit or announce every second to assistive technologies.

## 5. Layout and surfaces

Use solid fills, quiet warm rules, clean shapes, and negative space. Paper comes from color and typography, without literal texture. Normal Focus progresses from navigation to target to timers to supporting cards. References do not authorize unrelated sidebars, profiles, illustrations, or new features.

Prefer an 8-point spacing rhythm, 16–24 points inside cards, and 24–32 between major regions. Soft rounding starts around 8 points for fields, 12 for buttons, 20 for cards, and 24–28 for large surfaces. Use pills for compact selections/statuses where useful, not every control.

The shell keeps equal outer margins and a fixed viewport across tabs. Below the established breakpoints, reflow headings and stack paired cards; preserve horizontal scrolling for readable tables. Music/tasks grow into taller windows rather than leaving arbitrary empty space. Inner lists scroll without changing outer geometry. Check the default 1000 × 900, minimum 680 × 650, and wide 1710 × 1080 sizes, including long text, empty and error states.

Most cards need no shadow. Separate regions with surface colors, spacing and borders. Use a restrained warm shadow only for layering in menus/popovers/dialogs. Avoid heavy outlines and fake depth. Decorative borders and image layers must never intercept input.


## 6. Appearance and motion

Settings offers Light (default), Dark, and System. Its Updates section uses the same paper card, rounded heading, native switch and themed buttons, with a compact version/last-check display and wrapping status text. Update downloads/install prompts use Sparkle’s standard native UI; Keep’s restart confirmation follows the chosen appearance. Named assets supply dark variants, and sheets/popovers inherit the shell selection. System follows macOS independently of explicit window overrides; keep source implementation details in architecture.md.

| Semantic asset | Dark value |
| --- | --- |
| Background / Paper / Surface | `#211A17` / `#2C2522` / `#342C28` |
| Foreground / SecondaryForeground / MutedForeground | `#F4ECDF` / `#D8C8B9` / `#B9A79A` |
| MutedWarm / WarmHighlight | `#4C3E34` / `#584726` |
| AccentColor / AccentStrong | `#864732` / `#E9A386` |
| Sage / SageForeground / MistBlue | `#344B3A` / `#D9E8D0` / `#30484B` |
| Border / ControlBorder / FocusRing | `#59483E` / `#AA8D76` / `#F3BD8F` |


Dark uses espresso surroundings, brown paper, cream ink, and muted coral/sage. AccentStrong becomes light coral for readable links/actions. Never reuse light pastel panels behind cream text. Music retains enough warm tint for arbitrary artwork and an opaque Reduce Transparency fallback. Zen's white overlay intentionally stays consistent across appearance modes.

Motion should explain selection, expansion or state changes through short, quiet transitions. Favor roughly 120–200 milliseconds; favorites can use a slightly longer gentle expansion. Respect Reduce Motion with immediate alternatives. Avoid bouncing, continuous decoration, or distracting countdown animations. Wallpaper loading and tint changes must not replace content or interrupt input.

## 7. Accessibility and implementation

Target 4.5:1 contrast for ordinary text and 3:1 for large text, essential icons/control boundaries, and focus indicators. Check actual foreground/background pairs, including arbitrary artwork, hover, disabled and selected states. Decorative pastels never excuse unreadable content or invisible controls.

Keep controls keyboard-operable with meaningful labels/state descriptions, native shortcuts, selection and menu behavior. Preserve text selection where useful and respect Reduce Motion, Reduce Transparency, and Increase Contrast. No task completion, timer mode, selection or error may be encoded by color alone.

Use shared SwiftUI components, flexible layouts and realistic long-name/state previews. Keep global styling in DesignSystem; avoid fixed heights that crop content or a parallel styling framework.

Avoid neon, cold decorative gradients, gradient text, excessive badges/pills/icons, literal paper textures, ornate scripts, low-contrast reference text and unrelated page structures. Glass and readability fades are limited to the explicitly described music, backdrop and Zen uses. Before finishing, inspect relevant window sizes/appearances and confirm the active target/timers are clear while supporting areas stay comfortable and quiet.

## 8. Product website

The independent `website/` introduction uses Keep’s light cream and terracotta palette throughout, with self-hosted rounded Outfit typography and generous spacing. Actual native captures carry the product story; do not redraw app screens as HTML mockups or describe placeholders as shipped functionality. Keep the website and its app screenshots light regardless of system preference, with at least 7:1 contrast for body copy. Native theme assets remain the app’s source of truth; web CSS tokens do not replace them.

Introduce features progressively through the sticky desktop screenshot tour, quiet entry reveals and small preview transforms. Preserve normal scrolling and anchor navigation. Mobile, Reduce Motion and disabled JavaScript show each feature screenshot inline. Use light native screenshots, reserve image dimensions, and supply responsive sizes. The page should feel alive while keeping the app itself central. Show Dashboard Timesheet/Calendar, goals and CSV/ZIP exports alongside Focus, habits, Stats, Zen and the menu bar. State that every Keep feature is free; download copy must reflect actual release availability.
