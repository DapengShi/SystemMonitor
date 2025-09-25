# Design-004: Detail View Appearance Modes

- Related RFC: [RFC-004: Detail View Appearance Modes](../RFCs/RFC-004-detail-view-appearance-modes.md)
- Status: Draft
- Authors: Codex
- Updated: 2025-09-25

## Overview
This design translates RFC-004 into implementation steps for adding day, night, and follow-system theming to the detail window. It introduces a centralized theming controller, palette structs for each mode, and UI affordances for selecting an appearance while keeping existing layouts untouched. The work spans color token management, persistence, and targeted updates in detail subviews (`DetailView`, `ProcessListView`, overview cards).

## Scope & Constraints
- **In scope**: refactoring palette management, wiring SwiftUI environment data flow, persisting user preference, updating all detail subviews to consume the new palette, contrast validation, preview updates.
- **Out of scope**: redesigning layouts, extending theming to the menu bar popover, adding custom color pickers, or modifying data sources feeding the detail view.
- **Constraints**: zero regressions in behaviour, maintain SwiftUI preview functionality, avoid new dependencies, and keep changes backward compatible with macOS 13+.

## Architecture
### Theme Model
- Introduce `enum DetailAppearanceMode: String, CaseIterable, Identifiable` with cases `.day`, `.night`, `.system`. Each case exposes a localized display name and SF Symbol name for UI affordances.
- Provide a `DetailAppearanceSelection` value type bundling the mode and derived palette (useful for previews/testing).

### Theme Controller & Environment
- Create `final class DetailThemeController: ObservableObject` with:
  - `@Published private(set) var palette: DetailThemePalette`
  - `@Published var mode: DetailAppearanceMode`
  - `func update(mode:)` to mutate persisted mode and recompute the palette.
- Inject `@Environment(\.colorScheme)` (from SwiftUI) into the controller to translate `.light`/`.dark` to day/night when mode is `.system`.
- Define `struct DetailThemeKey: EnvironmentKey` with default referencing a singleton controller. Expose `extension EnvironmentValues { var detailTheme: DetailThemeController }`.
- `SystemMonitorApp` (or detail scene entry) instantiates the controller and places it in the environment (`.environment(\.detailTheme, controller)`), ensuring previews can also supply mock controllers.

### Palette Definitions
- Replace static `Palette` enum with:
  ```swift
  struct DetailThemePalette {
      let background: Color
      let panel: Color
      let card: Color
      let border: Color
      let primaryText: Color
      let secondaryText: Color
      let accentPrimary: Color
      let accentWarning: Color
      let accentSuccess: Color
      let rowEven: Color
      let rowOdd: Color
      let rowSelected: Color
      let shadow: Color
      let gradients: Gradients

      struct Gradients {
          let cpu: LinearGradient
          let memory: LinearGradient
          let networkDown: LinearGradient
          let networkUp: LinearGradient
          let process: LinearGradient
      }
  }
  ```
- Provide factory methods: `DetailThemePalette.day()`, `DetailThemePalette.night()`. Each ensures text/background contrast meets WCAG AA; store precomputed gradients to avoid runtime recomposition.
- Expose convenience computed values (`tableHeaderText`, `paginationTint`) to minimize direct color arithmetic in views.

### Persistence & System Hooks
- Use `@AppStorage("detailAppearanceMode")` in the entry view (e.g., `DetailViewContainer`) to persist the selected mode. On init, create the controller with the stored value.
- Observe `NotificationCenter` for `NSApplication.didChangeEffectiveAppearanceNotification` (or rely on SwiftUI's `colorScheme` change) to recompute the palette when system appearance flips while in `.system` mode.
- Provide `DetailThemeController` initializer that accepts `mode` and `systemColorScheme` (default optional) for unit testability.

## UI Changes
- Add a segmented control or menu to the detail header (`DetailView` top-right) using `Picker(selection:detailTheme.mode)` over `DetailAppearanceMode.allCases`. Use `.segmented` style when width allows; fall back to `Menu` for compact layout (conditioned on frame width or macOS size class).
- Replace hardcoded `Palette.*` references in `DetailView`, `DetailOverviewSection`, `ProcessListView`, and helper views with `let theme = detailTheme.palette`. For text colors currently using `.white.opacity`, map to `palette.primaryText` or `palette.secondaryText` with appropriate opacity adjustments baked into the palette.
- Update button styles to use `palette.accentPrimary`/`palette.accentWarning`. Ensure disabled states adjust opacity using theme-aware colors rather than `.gray`.
- Update drop shadows and dividers with palette-provided tokens to maintain consistent contrast in day mode.

## Migration & File Layout
- Rename `DetailPalette.swift` to host `DetailThemePalette`, initial palette factories, and `DetailAppearanceMode` definitions. Optionally break out into `DetailTheme.swift` if clarity improves.
- Introduce `DetailThemeController.swift` under `Sources/SystemMonitor/Support/` (or `Views/Detail/Support/`) to centralize observable logic.
- Ensure previews define lightweight fixtures:
  ```swift
  struct DetailView_Previews: PreviewProvider {
      static var previews: some View {
          DetailView(...)
              .environment(\.detailTheme, PreviewThemes.night)
          DetailView(...)
              .environment(\.detailTheme, PreviewThemes.day)
      }
  }
  ```
- Provide `PreviewThemes` helper that instantiates `DetailThemeController` with fixed palettes to avoid relying on `@AppStorage` inside previews.

## Data & State Flow
1. User opens detail view; `SystemMonitorApp` injects a shared `DetailThemeController` built from persisted mode and current color scheme.
2. Views reference `@Environment(\.detailTheme)` and read `palette` values for styling.
3. When user changes the picker, `DetailThemeController.update(mode:)` fires, writes to `@AppStorage`, and recomputes `palette`.
4. If mode is `.system`, controller listens to `colorScheme` changes; switching macOS appearance triggers `updatePalette(for:)` that publishes the new palette, causing SwiftUI re-render.
5. Any subview derived state (gradients, selection highlights) updates automatically via published palette.

## Accessibility & QA
- Validate color contrast using macOS accessibility inspector or third-party contrast tools. Document final ratios in PR notes.
- Confirm dynamic type and reduced motion settings respect existing behaviours; theming should not interfere with animations.
- Ensure palette change animates smoothly; consider wrapping palette updates in `withAnimation(.easeInOut(duration: 0.2))` if transitions feel abrupt.

## Implementation Steps
1. **Scaffold Theme Types**: Define `DetailAppearanceMode`, `DetailThemePalette`, and day/night palette factories. Provide test fixtures.
2. **Build Controller**: Implement `DetailThemeController`, environment key, and preview helpers. Add limited unit tests for palette selection (optional but recommended once test target exists).
3. **Persist Mode**: Wire `@AppStorage` in app entry. Ensure default is `.system` and migration from legacy palette is seamless.
4. **Refactor Detail Views**: Replace `Palette` references across `DetailView`, `DetailOverviewSection`, `ProcessListView`, and helpers with theme-driven values.
5. **Add UI Control**: Insert picker/menu in header; update layout constraints to avoid overlap with existing elements.
6. **Contrast Tuning**: Adjust palette constants based on visual QA; capture screenshots for both day/night with sample data.
7. **Docs & Guides**: Update `USER_GUIDE.md` or `INTERFACE_GUIDE.md` to mention appearance options and include preview imagery.
8. **Validation**: Run `swift build`, `swift run SystemMonitor`, manually test switching modes and macOS appearance toggles.

## Testing Strategy
- Manual regression: exercise detail view in all modes, verify persistence across relaunch, and check palette updates when macOS toggles light/dark.
- Automated (future): add snapshot/unit coverage once test target exists (e.g., verifying controller returns day palette when mode `.system` + `.light`).
- Previews: confirm day/night previews compile and display accurate colors.

## Risks & Mitigations
- **Incomplete palette adoption**: Some components might retain old colors. Mitigate with audit checklist and SwiftUI grep for `.white.opacity` in detail namespace during code review.
- **Performance concerns**: Palette recomputation should be lightweight; cache repeated gradients and avoid complex animations.
- **User confusion**: Picker placement must be discoverable. Provide tooltip or label (e.g., `Appearance`) and document in guides.

## Open Questions
- Should the selected manual mode cascade to the menu bar window, or remain scoped to detail view until a broader theming initiative? (default: scope locally)
- Do we need a high-contrast palette variant beyond system-provided increase-contrast settings? Pending accessibility review.
- Where should shared appearance utilities live if future modules adopt them (`Sources/SystemMonitor/Appearance` vs current detail-specific folder)?
