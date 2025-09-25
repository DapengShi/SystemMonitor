# RFC-004: Detail View Appearance Modes

- Status: Draft
- Authors: Codex
- Created: 2025-09-25
- Components: Sources/SystemMonitor/Views/DetailView.swift, Sources/SystemMonitor/Views/Detail/, Sources/SystemMonitor/SystemMonitorApp.swift, Sources/SystemMonitor/Support

## Context
The detail view ships with a fixed neon palette that was tuned for a dark background. It hardcodes `Palette` colors and `.white` opacities throughout `ProcessListView`, overview cards, and supporting subviews. When the app runs in macOS light appearance the detail window remains dark, causing readability issues and failing to respect user preferences or accessibility contrast rules. Teams have requested a day-friendly palette and an option to follow the system setting so the UI is consistent with the menu bar app and the rest of macOS.

## Goals
- Provide dedicated day (light) and night (dark) palettes that keep the UI legible and consistent across detail subviews.
- Offer three appearance modes: Day, Night, and Follow System, with automatic switching when macOS changes appearance.
- Centralize theming tokens to avoid ad-hoc hardcoded colors in `DetailView` and its extracted components.
- Maintain existing layout, typography, and behaviour while improving color contrast and accessibility.

## Non-Goals
- Redesigning layout, typography, or component hierarchy of the detail experience.
- Introducing theme customization beyond the three modes (no per-color pickers or high-contrast variants yet).
- Extending theming to unrelated modules (menu bar, notifications) beyond aligning shared tokens where reused later.

## Functional Requirements
- Persist the user-selected appearance mode and restore it on launch, defaulting to Follow System.
- When Follow System is selected, react to `colorScheme` changes in real time without requiring a restart.
- Expose a single source of truth for palette tokens so all detail subviews respond to mode changes.
- Guarantee text-to-background contrast ratios that meet WCAG AA for primary text in both palettes.

## Proposed Solution
### Appearance Mode Model
- Define an enum `DetailAppearanceMode` (`day`, `night`, `system`) with localized labels and SF Symbol aliases for UI.
- Add `DetailThemeController` (environment object or observable singleton) that exposes the active palette and handles subscription to `colorScheme` changes.
- Store the persisted selection using `@AppStorage("detailAppearanceMode")` in `SystemMonitorApp` so the setting flows through SwiftUI.

### Palette Tokens
- Create `DetailThemePalette` struct inside `DetailPalette.swift` containing tokens: `background`, `panel`, `card`, `border`, `primaryText`, `secondaryText`, `accentPrimary`, `accentWarning`, `selection`, `dividerShadow`.
- Provide static palettes for `day` (neutral grays, blue accents) and `night` (deep slate backgrounds, cyan/orange accents updated for contrast).
- Derive convenience colors (e.g., row stripe, pagination tint) from the palette to keep component code declarative (`palette.selectionRow`, `palette.tableHeader`).

### System Integration
- Inject `@Environment(\.colorScheme)` into the controller; when mode is `.system`, translate `.light` → day palette and `.dark` → night palette.
- Publish palette changes via `@Published var palette` so views update automatically. Keep defaults lazy to avoid recomputing gradients per frame.
- Use SwiftUI `EnvironmentKey` (e.g., `DetailThemeKey`) so subviews can call `@Environment(\.detailTheme)` instead of referencing globals.

### UI Surface Updates
- Replace usages of `Palette.*` and `.white.opacity(...)` inside `DetailView`, `ProcessListView`, overview cards, and footers with values from the injected palette.
- Add a segmented control or menu in the detail toolbar (top-right of the header) allowing users to pick Day, Night, or System. Respect macOS Human Interface Guidelines by using `Picker` with `segmented` style or a trailing `Menu` depending on space constraints.
- Update SwiftUI previews to preview each palette to assist designers.

### Accessibility & QA
- Validate contrast with Calibrated colors (minimum 4.5:1 for body text, 3:1 for auxiliary text). Adjust accent saturation until requirements pass.
- Capture before/after screenshots for both appearances and document manual verification steps in the implementation PR.

## User Experience
- Default state: Follow System. The detail window mirrors macOS appearance when the user changes it in System Settings.
- Day mode: light grey background, dark text, softer accent gradients while maintaining the existing semantic colors (CPU orange, Memory cyan, etc.).
- Night mode: refined dark palette that reduces glare, slightly lowers drop-shadow opacity, and maintains neon accent cues.
- Mode control lives in the detail header; the selection persists between sessions and applies instantly without window reloads.

## Implementation Plan
1. Introduce `DetailAppearanceMode`, `DetailThemePalette`, and environment plumbing in `DetailPalette.swift` (or new `DetailTheme.swift`).
2. Add persistence via `@AppStorage` in the app entry point and pass a `DetailThemeController` through the environment.
3. Refactor detail subviews (`DetailView`, `ProcessListView`, overview components) to consume `@Environment(\.detailTheme)` instead of global palette constants.
4. Build the UI control for switching modes and wire it to update the controller.
5. Adjust colors to meet contrast requirements and update SwiftUI previews to cover each mode.
6. Smoke test `swift run SystemMonitor` in both day and night macOS appearances; document manual checks and capture screenshots.

## Risks & Mitigations
- **Palette regressions**: Visual drift can slip in during refactors; mitigate with per-mode screenshots and designer review.
- **Performance**: Frequent palette recomputation could trigger extra renders; ensure palettes are simple `Color` values and the controller coalesces updates.
- **Inconsistent adoption**: Some legacy components may still hardcode colors; run a focused audit of detail views and add lint notes in the PR description.

## Rollout Strategy
- Ship as a single PR gated behind manual UI validation. Confirm no new dependencies are required.
- Update `USER_GUIDE.md` with a brief note on appearance settings once implementation is finalised.
- If issues surface, allow a quick rollback by reverting the palette controller while keeping enum definitions for future use.

## Open Questions
- Should the manual Day/Night overrides propagate to the menu bar popover or remain detail-only until a broader theming effort lands?
- Do we need an explicit high-contrast mode for accessibility users, or can system-wide increase-contrast settings suffice for now?
- Should we expose palette tokens in a shared module (`Appearance/`) to prepare for future reuse in other windows?
