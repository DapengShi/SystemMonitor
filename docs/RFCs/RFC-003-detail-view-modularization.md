# RFC-003: Detail View Modularization

- Status: Draft
- Authors: Codex
- Created: 2025-09-25
- Components: Sources/SystemMonitor/Views/DetailView.swift, Sources/SystemMonitor/Views/Detail/

## Context
`DetailView.swift` currently spans ~1,000 lines and blends SwiftUI layout, view-state management, palette values, process table logic, and reusable subviews into a single file. This monolithic structure slows down iteration, increases the risk of regressions when touching isolated areas, and makes it difficult to reuse components (e.g., stat blocks) in other contexts. Compared to other views in the project, DetailView lacks clear boundaries between overview metrics, process table rendering, and shared styling primitives.

## Goals
- Reduce `DetailView.swift` into focused modules that separate layout scaffolding, overview cards, and process table rendering.
- Preserve existing UI behaviour and styling while enabling component reuse and local previews.
- Introduce lightweight view models or helper structs where state (sorting, pagination, expansion) can be encapsulated outside the primary view body.
- Improve testability by making it feasible to add SwiftUI previews or future unit tests for individual subcomponents.

## Non-Goals
- Redesign the UI or change visual styling beyond what is necessary to decouple components.
- Introduce new data sources or modify `SystemStatsObservable` APIs.
- Add new feature flags for layout changes; the split should be behaviourally identical to users.

## Current Pain Points
- `DetailView` mixes formatters, color palette, state variables, process-tree logic, and subview declarations, making navigation difficult.
- Reusable subviews (e.g., `StatBlock`, `UsageBar`, `MetricPill`, `ProcessRowView`) cannot be previewed or reused without dragging the entire file into scope.
- Pagination and expansion logic intertwines with SwiftUI layout code, complicating future refactors or bug fixes.
- Lack of module boundaries limits contributions from other developers who only need to adjust one section (overview vs. table).

## Proposed Architecture
### File Layout
Create `Sources/SystemMonitor/Views/Detail/` and divide responsibilities:
1. `DetailView.swift` (trimmed)
   - Retains top-level view struct, state properties, and orchestrates child components.
   - Moves color palette and formatting utilities to dedicated files.
2. `DetailPalette.swift`
   - Holds color/gradient constants and any shared styling tokens.
3. `DetailOverviewSection.swift`
   - Contains overview grid layout and reusable subviews (`StatBlock`, `UsageBar`, `MetricPill`).
   - Adds SwiftUI previews for cards/metric pills.
4. `ProcessListView.swift`
   - Encapsulates process table, pagination buttons, `ProcessRowView`, and helper models (`DisplayProcess`, column widths).
   - Exposes bindings/callbacks for selection, expansion, and kill actions.
5. `DetailHelpers.swift`
   - Hosts utility functions (formatters, network bar calculations, load averages) shared across sections.

### State & Data Flow
- `DetailView` continues owning state (`selectedProcess`, `expandedProcesses`, `searchText`, etc.) but delegates rendering to child views via bindings or small view models.
- Consider introducing `ProcessDisplayViewModel` that computes filtered/paginated rows, isolating data prep from SwiftUI `body`.
- `ProcessListView` should receive:
  - `rows: [DisplayProcess]`
  - Pagination info (`currentPage`, `totalPages`, callbacks`)
  - Selection bindings and handlers for expand/collapse, kill confirmation triggers.

### Styling & Utilities
- Palette values migrate to `DetailPalette`. Adjust child views to accept palette constants via injection or static access.
- Reusable formatters (timestamp, bytes, percent) centralised in `DetailHelpers` so tests/previews can call them without pulling in the full view.

## Implementation Plan
1. **Scaffolding**: Create `Views/Detail` directory and move palette + helper structs into new files, updating imports.
2. **Overview Extraction**: Split overview grid into `DetailOverviewSection` with `StatBlock`, `UsageBar`, `MetricPill`. Keep API surface identical and expose injection points for metrics.
3. **Process List Extraction**: Move process table code into `ProcessListView`, along with `ProcessRowView`, `DisplayProcess`, column constants, and context menu logic. Provide necessary bindings.
4. **ViewModel Optionality**: Evaluate if pagination/expansion logic can become a struct/class (e.g., `ProcessListViewModel`) to reduce state duplication.
5. **Trim DetailView**: After extraction, ensure the main file primarily wires sections and manages alerts/higher-level state.
6. **Preview & Testing**: Add SwiftUI previews for new components with sample data; verify `swift build` and run manual UI smoke tests.

## Risks & Mitigations
- **Behavioural Drift**: Moving code may accidentally change styling. Mitigate with side-by-side UI checks and snapshots/screenshots for review.
- **State Synchronization**: Passing bindings between `DetailView` and new components may introduce loops or inconsistent state. Clearly document ownership and use `Binding`/callbacks judiciously.
- **Scope Creep**: Keep the split focused; avoid redesigns or extra features during this refactor.

## Rollout Strategy
- Implement in incremental PRs aligned with plan steps (palette/helpers, overview extraction, process list extraction).
- After each step, run `swift build` and `swift run SystemMonitor` to ensure the UI matches existing behaviour.
- Update CONTRIBUTING or developer docs if new component structure affects future contributions.

## Open Questions
- Should pagination/filtering move to a dedicated view model now, or remain in `DetailView` until tests are ready?
- Do we expose overview cards as standalone views for potential reuse in other windows (e.g., a dashboard)?
- Is there value in adding Snapshot or UI tests once components are modularised?
