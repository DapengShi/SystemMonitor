# Design-002: Process Collector Modularization

- Related RFC: [RFC-002: Process Collector Modularization](../RFCs/RFC-002-process-collector-refactor.md)
- Status: Draft
- Authors: Codex
- Updated: 2025-09-25

## Overview
This design document translates RFC-002 into an actionable implementation plan. The refactor targets `ProcessCollector` by splitting its responsibilities across smaller, composable components while maintaining the observable behaviour consumed by SwiftUI. We will add protocol seams for system sampling and metric calculations, isolate the `nettop` dependency, and clarify ownership of caches and buffers so the codebase can support future unit tests.

Primary outcomes:
- Preserve `ProcessCollector.snapshotProcesses(limit:)` (and any existing public types) while reorganising internals.
- Introduce new helper types under `Sources/SystemMonitor/Processes/` that align with their respective concerns (enumeration, host metrics, per-process math, network sampling).
- Provide dependency-injection points so tests and future features can supply mocks without altering production wiring.

## Scope & Constraints
- **In scope**: source reorganisation, new Swift files, protocol definitions, encapsulating existing logic (sysctl, mach time conversions, `nettop`).
- **Out of scope**: UI changes, metric semantics, replacing `nettop`, async/await adoption, new C bridging APIs.
- **Performance constraint**: maintain current sampling throughput by reusing buffers and caches; no additional allocations on the hot path beyond those necessary for the modular split.

## Component Breakdown
The refactor creates the following Swift types (all internal unless otherwise noted):

- `ProcessTypes.swift`
  - Houses `ProcessFlags`, `ProcessInfo`, `HostMetrics`, and `CachedProcess` (internal) to centralise shared models.
  - Adds lightweight docs describing field expectations and invariants (percent ranges, byte semantics).

- `ProcessEnumerator.swift`
  - Implements `ProcessEnumeratorProtocol` with methods to fetch `[kinfo_proc]` via sysctl.
  - Owns the `UnsafeMutableRawPointer` buffer and handles resizing, leaving `ProcessCollector` agnostic to allocation details.

- `HostCPUSampler.swift`
  - Implements `HostCPUSamplerProtocol`; wraps `host_processor_info` and retains previous tick totals.
  - Exposes `mutating func deltaSeconds() -> Double?` returning host delta seconds (nil when unavailable).

- `ProcessMetricsCalculator.swift`
  - Defines `ProcessMetricsCalculating` with pure helper methods for CPU percent, cumulative CPU, memory, disk, and network rates.
  - Concrete `ProcessMetricsCalculator` struct is stateless to facilitate unit tests.

- `NetworkUsageSampler.swift`
  - Implements `NetworkUsageSamplerProtocol`; reacts to time gating, invokes `nettop`, parses output, and returns `[Int32: (UInt64, UInt64)]` totals.
  - Owns throttling state (sample interval, last sample timestamp) and isolates parsing helpers.

- `ProcessCollector.swift`
  - Shrinks to orchestration: uses dependencies to build `ProcessInfo` and maintain caches.
  - Retains `collectorQueue`, `cachedProcesses`, `networkTotals`, and public `snapshotProcesses(limit:)`.

### Supporting Types & Namespaces
- `DiskRates` and `NetworkRates` simple structs returned by the calculator for readability.
- Internal `ProcessCollectorDependencies` struct or initializer parameters to wire concrete implementations from `SystemStats`.

## Data Flow
1. `ProcessCollector.snapshotProcesses(limit:)` executes on `collectorQueue`.
2. `HostCPUSampler.deltaSeconds()` runs first to capture host delta information for CPU calculations.
3. `ProcessEnumerator.snapshot()` returns the current `[kinfo_proc]` buffer, reusing allocations.
4. `NetworkUsageSampler.sampleIfNeeded(reference:)` generates per-PID network totals when the sample window elapses.
5. For each process:
   - Fetch or reuse `CachedProcess` entry.
   - Collect per-PID data (task info, rusage, usernames, command lines) using existing helper functions.
   - Delegate CPU/memory/disk/network math to `ProcessMetricsCalculator`.
   - Assemble `ProcessInfo` and update caches.
6. Remove stale cache entries for PID values no longer present.
7. Return sorted `ProcessInfo` array; limit applied as before.

```
collectorQueue -> HostCPUSampler -> ProcessEnumerator -> NetworkUsageSampler
                                  \-> ProcessMetricsCalculator
                                    \-> ProcessCollector cache updates -> ProcessInfo array
```

## Implementation Steps
1. **Model Extraction**
   - Create `ProcessTypes.swift` with shared structs and option sets.
   - Move computed properties (`cpuUsage`, `isHighCPU`, etc.) here to keep `ProcessCollector` lean.
   - Update imports where the types are used (views, SystemStats).

2. **Enumerator Module**
   - Add `ProcessEnumeratorProtocol` and `ProcessEnumerator` concrete implementation.
   - Move buffer allocation/resizing logic from `ProcessCollector.fetchKinfoProcBuffer` into enumerator.
   - Provide `mutating func snapshot() -> [kinfo_proc]` returning an array or optional slice; keep `ProcessCollector` interactions identical.

3. **Host CPU Sampler**
   - Extract `captureHostDeltaSeconds` and `currentHostTickTotals` into `HostCPUSampler`.
   - `ProcessCollector` retains an instance and calls `deltaSeconds()` per snapshot.

4. **Metrics Calculator**
   - Relocate math helpers (`computeCumulativeCPUPercent`, `computeDiskRates`, `computeNetworkRates`, `convertMachToSeconds`) into `ProcessMetricsCalculator`.
   - Adjust them to accept `CachedProcess` data as arguments, returning computed doubles or small structs.

5. **Network Sampler**
   - Move `updateNetworkTotalsIfNeeded` and `parseNettop` into `NetworkUsageSampler`.
   - Provide `sampleIfNeeded(reference: Date) -> [Int32: (UInt64, UInt64)]` and store the last sample date internally.

6. **ProcessCollector Rebuild**
   - Refactor `ProcessCollector` initializer to accept dependencies with sensible defaults:
     ```swift
     init(enumerator: ProcessEnumeratorProtocol = ProcessEnumerator(),
          hostSampler: HostCPUSamplerProtocol = HostCPUSampler(),
          networkSampler: NetworkUsageSamplerProtocol = NetworkUsageSampler(interval: 5),
          metricsCalculator: ProcessMetricsCalculating = ProcessMetricsCalculator())
     ```
   - Replace direct method calls with dependency usage, keeping the queue and caches internal.
   - Update caching logic to align with new component outputs.

7. **Wiring & Call Sites**
   - Update `SystemStats` (or equivalent entry point) to instantiate `ProcessCollector` using the new initializer.
   - Ensure other modules continue to call `snapshotProcesses` unchanged.

8. **Documentation & Comments**
   - Add targeted comments where concurrency or ownership is non-obvious (e.g., enumerator buffer lifetime).
   - Update `AGENTS.md` references if necessary to point to the new module layout (per RFC checklist).

## Threading & Concurrency
- `ProcessCollector` remains the only type touching shared caches. All mutating methods must execute on `collectorQueue`.
- Dependencies that maintain internal mutable state (`ProcessEnumerator`, `HostCPUSampler`, `NetworkUsageSampler`) are invoked only from the collector queue; document this assumption in their doc comments.
- Any public methods exposed for testing should clearly state non-thread-safe usage.

## Error Handling & Telemetry
- Dependency methods return optionals or throw when low-level calls fail; `ProcessCollector` catches/filters errors and sets `ProcessFlags` (`.permissionDenied`, `.networkUnavailable`).
- Wrap `nettop` invocation failure in a single logged warning per interval to avoid log spam; leave network rates at zero when unavailable.
- Maintain current silent fallback semantics (empty arrays) to prevent UI regressions, but consider hooking into `os_log` for diagnostics.

## Testing Strategy
- Add future unit tests under `Tests/SystemMonitorTests` using protocol mocks:
  - `ProcessMetricsCalculatorTests` verifying CPU/disk/network math given synthetic inputs.
  - `NetworkUsageSamplerTests` for parsing sample `nettop` output and interval gating.
  - `ProcessCollectorTests` (integration-light) with fake enumerator/host sampler to confirm cache pruning and flag handling.
- For manual testing, repeat existing flows: `swift run SystemMonitor` under idle + `python3 cpu_stress_test.py`, compare metrics with Activity Monitor.

## Migration & Rollout
- Perform refactor in phases matching the implementation steps, landing incremental PRs if desired.
- After completing the modular split, run packaging scripts (`swift build`, `swift build -c release`, `sh package_app.sh`) to ensure distribution unaffected.
- Update README snippet or contributor notes highlighting the new `Sources/SystemMonitor/Processes/` subtree.

## Open Questions
- Should dependency injection be exposed publicly or via internal factory to prevent accidental misconfiguration?
- Do we want configuration knobs (e.g., custom network sampling interval) exposed via `SystemStats` now or later?
- Is additional telemetry (success/failure counters) required for future diagnostics?

