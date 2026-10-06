# Keep — Visual Style Guide

Keep follows a cozy retro editorial direction: warm paper, autumn colors, clear typography, softly rounded cards, and generous quiet space. `reference/main-theme.jpg` informs atmosphere and palette, not a prescribed page layout.

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

Use stronger ink on peach or colored fills. Quiet borders separate decoration; essential controls need the stronger control-boundary token. Preserve the distinction between normal, selected, focused, disabled, and destructive states rather than relying on subtle hue shifts.

## 4. Typography

Use native system serif for editorial headings and occasional static statistics; use system sans-serif for controls, tasks, navigation, and metadata. Running timers use clean, stable-width monospaced digits. Custom fonts need a visual reason, licensing, and fallbacks.

Prefer calm expressive headings, regular/medium utility text, and few weights. Use subtle tracking for short labels, uppercase sparingly, and no decorative scripts or futuristic display fonts. Keep the interface adult and understated.

Ordinary content starts around 15–17 points; metadata around 12–13. These are starting ranges, not rigid sizes: preserve readability, wrapping, and comfortable line spacing. Do not shrink task or helper text to fit a fixed card. Timer digits adapt to their available column and should remain easy to scan. Do not animate every digit or announce every second to assistive technologies.

## 5. Layout and surfaces

Use solid fills, quiet warm rules, clean shapes, and negative space. Paper comes from color and typography, without literal texture. Normal Focus progresses from navigation to target to timers to supporting cards. References do not authorize unrelated sidebars, profiles, illustrations, or new features.

Prefer an 8-point spacing rhythm, 16–24 points inside cards, and 24–32 between major regions. Soft rounding starts around 8 points for fields, 12 for buttons, 20 for cards, and 24–28 for large surfaces. Use pills for compact selections/statuses where useful, not every control.

The shell keeps equal outer margins and a fixed viewport across tabs. Below the established breakpoints, reflow headings and stack paired cards; preserve horizontal scrolling for readable tables. Music/tasks grow into taller windows rather than leaving arbitrary empty space. Inner lists scroll without changing outer geometry. Check the default 1000 × 900, minimum 680 × 650, and wide 1710 × 1080 sizes, including long text, empty and error states.

Most cards need no shadow. Separate regions with surface colors, spacing and borders. Use a restrained warm shadow only for layering in menus/popovers/dialogs. Avoid heavy outlines and fake depth. Decorative borders and image layers must never intercept input.

## 6. Artwork and music

The normal window backdrop shares the player's selected image/fallback, heavily blurred until objects disappear. Clamp image edges before preparing a small off-main texture; scale it smoothly to fill the window. Light adds a paper wash and Dark an espresso tint. Artwork changes preserve panel geometry and mounted content.

Blend quiet ambient artwork color into the opaque panel and distinct supporting hues into the timer fills. Pomodoro focus retains a terracotta base, Flow sage, and breaks butter. Use appearance-aware bases and limit tint before text contrast weakens. Project labels retain their own identity rather than taking arbitrary artwork colors.

The music panel is an explicit exception to the flat treatment. Align a crop of the actual card artwork beneath its controls instead of showing the unrelated outer backdrop through a native material. Glassiness continuously reduces both blur and paper opacity, retaining a readability wash, stronger in Dark. Liquid Glass adds Apple's clear treatment. At zero or under Reduce Transparency use opaque paper in the active appearance. Glassiness uses the same native SwiftUI Slider as music volume, with theme tint and a comfortable control area.

Keep transport controls at the artwork's bottom, provider attribution/switching at the top, and Zen entry available from Focus. Favorites show an explicit saved state. Their drawer expands inside the existing card allocation, stays open while selections play, and collapses only when toggled. Larger cards show list and transport together; constrained cards replace details/transport with the list and retain its toggle. The list scrolls; playback continues. Unsaving never interrupts playback. Provider choices never autoplay. Put All Lofi permanently first in the playlist list, even when no favorites exist; selecting any list row explicitly plays that source. Keep sources out of the provider menu.

## 7. Controls and feature layouts

Use native Button, Toggle, text input, Slider, menus, popovers and dialogs for behavior/accessibility. Centralize reused button/input styles in DesignSystem, pass feature actions from the caller, and preserve keyboard operation and visible focus. Comfortable primary targets are generally 36–44 points high. Selected appearance and main actions use terracotta with appropriate contrasting ink; quiet actions use cream/warm neutrals; destructive actions use distinct wording and the danger token.

Settings is a centered column of paper sections, native switches, and warm fields/menu buttons. Glass controls belong under Appearance, with a shared live player preview. Calendar pickers use roomy themed date cells, clear selection, Today indication, muted adjacent dates, and native popover behavior; avoid inconsistent system graphical-picker chrome.

Dashboard's compact page switch has warm neutral surroundings and a terracotta selection. Calendar uses fine rules, restrained weekend shading, visible weekday headers, and project-colored session blocks with readable task/project/time details. Only real recorded sessions appear; old/manual totals remain in Timesheet without invented timestamps.

Task selection is one flat suggestion list beneath the name/search input, with task/project labels and pin controls; pinned entries come first. Avoid nested suggestion cards or separate recent-activity sections. Keep the working-on card neutral until a control actually receives focus, and show its task as plain text until explicit editing. Do not auto-select text or leave a permanent editor outline.

Only Today's task rows reveal the three circular timer-launch actions on hover or keyboard focus, with accessible equivalents and tooltips. Focus/Flow colors follow their timer surfaces; Both remains fixed neutral across appearance/artwork changes. Reserve action space so text does not shift. Past/future tasks expose no timer launch actions. Completion uses explicit checks as well as color, and struck-through titles remain readable.

## 8. Habit tracker and data

Habit activity, weekly progress and selected-habit stats share one paper surface with faded separators. Center a compact full-current-year grid with month labels and Monday-first columns. Monthly intensity counts completed habits; Weekly fills one square per completed goal, up to seven, with exact counts exposed. Future/rest states are subdued but still visible. Do not scale a lone completion into a filled column.

Weekly progress fits its seven day controls, leaving room for stats alongside; stack at narrow widths. Give habits varied existing project accents and metric surfaces quiet sage, blue, honey, and rose. Keep readable accent ink in both appearances. Empty circular check-in controls have visible outlines; completed and partial states use checks, rings or amounts, not color alone.

Creation uses seven selectable weekday dots with letters/selected states, a theme-consistent goal selector, checkbox and shared calendar. Check-in goals toggle; amount goals expose numeric progress. Use the same grouped activity-mode switch treatment as Dashboard.

Charts use simple bars, lines, dots or rings with directly labeled values/states. Reserve strong emphasis for the main metric and use supporting tokens elsewhere. Add symbols or labels when series colors are ambiguous. Avoid pseudo-3D charts and speculative analytics widgets.

## 9. Zen

Zen is an explicit minimalist exception to the normal paper layout. Fill the screen with the selected unblurred wallpaper, leaving nearly all of it unobstructed. Use a small music transport/volume row and one line of track metadata at bottom-left; compact labeled timer digits and play/pause controls sit at bottom-right. At narrow widths stack these controls without clipping. Keep the wallpaper at its original brightness, without a black fade. Use small white functional text/icons with local shadows and focus/hover feedback; avoid provider badges, headings and promotional copy.

Escape or double-clicking uncovered artwork exits Zen regardless of control focus; omit the Exit button. Timer reset/break actions may live in a context menu; music library browsing remains available where applicable. Audius hearts and a saved-list button stay in the compact music row; their saved list expands above transport in an artwork-aligned glass card, with the same glassiness setting and opaque Reduce Transparency fallback as the normal player. Controls operate the existing timers/player without resetting them. Preserve labels, disabled/loading/error states, Retry, and visible keyboard focus even in this stripped-down layout. Wallpaper remains the visual focus.

## 10. Appearance and motion

Settings offers Light (default), Dark, and System. Named assets supply dark variants, and sheets/popovers inherit the shell selection. System follows macOS independently of explicit window overrides; keep source implementation details in architecture.md.

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

## 11. Accessibility and implementation

Target 4.5:1 contrast for ordinary text and 3:1 for large text, essential icons/control boundaries, and focus indicators. Check actual foreground/background pairs, including arbitrary artwork, hover, disabled and selected states. Decorative pastels never excuse unreadable content or invisible controls.

Keep controls keyboard-operable with meaningful labels/state descriptions, native shortcuts, selection and menu behavior. Preserve text selection where useful and respect Reduce Motion, Reduce Transparency, and Increase Contrast. No task completion, timer mode, selection or error may be encoded by color alone.

Use shared SwiftUI components, flexible layouts and realistic long-name/state previews. Keep global styling in DesignSystem; avoid fixed heights that crop content or a parallel styling framework.

Avoid neon, cold decorative gradients, gradient text, excessive badges/pills/icons, literal paper textures, ornate scripts, low-contrast reference text and unrelated page structures. Glass and readability fades are limited to the explicitly described music, backdrop and Zen uses. Before finishing, inspect relevant window sizes/appearances and confirm the active target/timers are clear while supporting areas stay comfortable and quiet.
