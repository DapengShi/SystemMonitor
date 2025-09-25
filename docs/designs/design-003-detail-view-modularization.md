# Design-003: Detail View Modularization

- Related RFC: [RFC-003: Detail View Modularization](../RFCs/RFC-003-detail-view-modularization.md)
- Status: Draft
- Authors: Codex
- Updated: 2025-09-25

## Overview
This document converts RFC-003 into an executable plan for splitting the monolithic `DetailView`. The primary objective is to separate color/styling primitives, overview cards, and process-table logic into reusable components while keeping runtime behaviour identical. The split should leave `DetailView` as an orchestrator that binds `SystemStatsObservable` state to modular SwiftUI views.

## Scope & Constraints
- **In scope**: reorganising SwiftUI subviews, introducing new helper files, lightweight view models, and bindings to decouple concerns.
- **Out of scope**: adding new features, changing layout semantics, altering `SystemStatsObservable` APIs, or redesigning the UI.
- **Constraints**: keep SwiftUI previews simple, maintain test/build compatibility (`swift build`), and avoid adding new dependencies.

## Target Structure
Create `Sources/SystemMonitor/Views/Detail/` with the following files:

1. `DetailView.swift`
   - Retains state (`searchText`, `selectedProcess`, pagination) and high-level layout.
   - Delegates rendering to extracted sections.

2. `DetailPalette.swift`
   - Exposes palette colors/gradients (`Palette`), including static helpers for reuse.
   - Optionally expose typography constants or shadow styles.

3. `DetailHelpers.swift`
   - Houses formatters (`timestampFormatter`, `%` formatting, byte speed), network bar calculations, load average helpers. Functions should be static to allow preview use.

4. `DetailOverviewSection.swift`
   - Contains `DetailOverviewSection` view struct, overview grid composition, and supporting components (`StatBlock`, `UsageBar`, `MetricPill`).
   - Accepts data via simple DTO (e.g., `OverviewMetrics` struct) or binding to `SystemStatsObservable`.

5. `ProcessListView.swift`
   - Encapsulates process table, pagination controls, `ProcessRowView`, `DisplayProcess`, column widths.
   - Exposes callbacks for expansion, selection, kill action trigger, and receives computed rows + pagination metadata.

6. `ProcessListViewModel.swift` (optional but recommended)
   - Encapsulates filtering, sorting, pagination, and tree expansion logic.
   - Provides derived data (`rows`, `totalPages`, `selectedProcess`, `toggle`, etc.) while keeping SwiftUI states as `@Published` or methods returning plain values.

## Data Flow & Interfaces
- `DetailView` initialises a `ProcessListViewModel` (if introduced) using `@StateObject`. The view model accepts `SystemStatsObservable.processes` and local state (search, sort, expansions).
- Overview section receives computed metrics (CPU, memory, network rates, highlight process). Consider a struct:
  ```swift
  struct OverviewMetrics {
      let cpuUsage: Double
      let memoryUsage: Double
      let downloadSpeed: Double
      let uploadSpeed: Double
      let processCount: Int
      let highlightedProcess: ProcessInfo?
      let loadAverages: (Double, Double, Double)?
  }
  ```
- Process list view expects:
  - `rows: [DisplayProcess]`
  - `selection: Binding<ProcessInfo?>`
  - `onToggle: (ProcessInfo) -> Void`
  - `onKillRequested: () -> Void`
  - Pagination control (current page, total pages, `onPageChange` callback).
- Helpers expose pure functions (e.g., `formatPercent(_:)`, `formatBytesPerSecond(_:)`, `networkBarValue(_:)`).

## Implementation Steps
1. **Scaffold Directory & Palette**
   - Create `Sources/SystemMonitor/Views/Detail/`.
   - Move `Palette` enum to `DetailPalette.swift`. Adjust imports to use `Palette` from the new location.

2. **Extract Helpers**
   - Move formatters and helper functions (`timestampFormatter`, `formatPercent`, byte formatting, `truncatedProcessName`, load average) into `DetailHelpers.swift`.
   - Provide static methods or free functions; update usage in `DetailView` and extracted components.

3. **Overview Section**
   - Create `DetailOverviewSection` view that accepts an `OverviewMetrics` struct and `Palette` references.
   - Move `StatBlock`, `UsageBar`, `MetricPill` into this file. Add SwiftUI previews using sample data.
   - Replace original overview grid in `DetailView` with `DetailOverviewSection(metrics: ...)`.

4. **Process List Extraction**
   - Move process table layout to `ProcessListView`, including `ProcessTableHeader`, `ProcessRowView`, `DisplayProcess`, column constants, and context menu actions.
   - Provide properties for `rows`, `sortOption`, `selection`, `expanded`, `onToggle`, `pagination`. Maintain existing keyboard/gesture behaviour.

5. **Introduce ViewModel (optional)**
   - If beneficial, create `ProcessListViewModel` to manage filtering/sorting/pagination. Otherwise keep trimming to private helper methods within `DetailView` and revisit later.
   - Ensure the model exposes derived data without requiring knowledge of SwiftUI.

6. **Trim DetailView**
   - Update main view to compose `DetailOverviewSection` and `ProcessListView`, focusing on binding state and showing alerts.
   - Remove redundant functions now living in helpers.

7. **Previews & Testing**
   - Add sample data view previews for extracted components.
   - Run `swift build` to ensure compilation. Perform manual UI check via `swift run SystemMonitor`.

8. **Docs**
   - Update `AGENTS.md` if necessary to note the new detail view structure.
   - Mention new components in contributor notes or design guidelines if helpful.

## Risks & Mitigations
- **State Drift**: Ensure expansions and pagination do not reset unexpectedly by writing integration checks in `DetailView` or view model tests.
- **Naming Collisions**: Preface new files with `Detail` to avoid conflicts with other views.
- **Preview Maintenance**: Provide simple fixtures for `ProcessInfo` to avoid runtime dependencies when previewing.

## Testing Strategy
- Manual: run `swift run SystemMonitor` and exercise search, pagination, kill dialog, expansion collapse to confirm parity.
- Automated (future): consider unit tests for helper functions and view model once extraction is complete.

## Open Items
- Decide whether to introduce `ProcessListViewModel` immediately or defer.
- Confirm naming (`DetailOverviewSection` vs `OverviewCardSection`).
- Align on sample data fixtures for previews.
