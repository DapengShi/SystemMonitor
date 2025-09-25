# RFC-002: Process Collector Modularization

- Status: Draft
- Authors: Codex
- Created: 2025-09-25
- Components: Sources/SystemMonitor/ProcessCollector.swift, Sources/SystemMonitor/Processes/*, SystemStats wiring

## Context
`ProcessCollector` currently owns syscall orchestration, per-process metric computation, host CPU sampling, caching, and integration with external tools such as `nettop`. The file exceeds 450 lines, combines low-level Darwin interactions with presentation models, and contains time-based throttling that is difficult to reason about in isolation. This coupling makes incremental changes risky and blocks unit testing of critical logic (CPU math, disk/network deltas, permission fallbacks).

## Goals
- Preserve the existing public API (`ProcessCollector.snapshotProcesses(limit:)`) while splitting responsibilities into focused components.
- Introduce protocol-oriented seams for host CPU ticks, process enumeration, metric math, and network sampling to enable dependency injection and testing.
- Continue reusing sysctl buffers and caches so the refactor does not regress performance.
- Document concurrency and ownership rules for caches and external resources.

## Non-Goals
- Alter the UI surface or change thresholds for high CPU or memory warnings.
- Replace the `nettop`-based network sampler (only isolate it behind an abstraction).
- Adopt async/await or new threading primitives beyond the existing serial queue.
- Expand the bridging header with new C shims; stay within the current API set.

## Current Pain Points
- **Monolithic implementation**: Mixing models, caching, syscall code, and metric math causes cognitive overload and accidental cross-dependencies.
- **Testing barriers**: No way to stub host tick data or network totals; validating bug fixes requires manual end-to-end runs.
- **Concurrency risks**: Cache mutations and sysctl buffer lifetimes are hidden within a single file, making synchronization assumptions opaque.
- **Error handling**: Permission-denied paths and `nettop` failures are interwoven with success logic, reducing observability.

## Proposed Architecture
### Module Layout
- `ProcessTypes.swift`: Define `ProcessFlags`, `ProcessInfo`, `HostMetrics`, and internal cache structs with concise documentation.
- `ProcessEnumerator.swift`: Manage sysctl calls and buffer reuse, returning `[kinfo_proc]` snapshots. Conform to `ProcessEnumeratorProtocol` for mocking.
- `HostCPUSampler.swift`: Encapsulate `host_processor_info` calls, track tick deltas/core counts, and expose `hostDeltaSeconds()`.
- `ProcessMetricsCalculator.swift`: Provide pure helpers for CPU percent, cumulative CPU, memory, disk, and network rate math.
- `NetworkUsageSampler.swift`: Wrap `nettop` invocation, throttling, and parsing. Return `[Int32: (bytesIn: UInt64, bytesOut: UInt64)]` via `NetworkUsageSamplerProtocol`.
- `ProcessCollector.swift`: Shrink to orchestration—coordinate enumerator, samplers, and cache updates behind the existing API.

### Protocol Surfaces
```swift
protocol ProcessEnumeratorProtocol {
    mutating func snapshot() throws -> [kinfo_proc]
}

protocol HostCPUSamplerProtocol {
    mutating func deltaSeconds() -> Double?
}

protocol NetworkUsageSamplerProtocol {
    mutating func sampleIfNeeded(reference: Date) -> [Int32: (UInt64, UInt64)]
}

protocol ProcessMetricsCalculating {
    func instantaneousCPU(percentFrom taskInfo: proc_taskinfo?, previous: CachedProcess?, hostDelta: Double?, cores: Int, fallback: Double) -> Double
    func cumulativeCPU(totalTime: UInt64, startTime: UInt64, currentAbs: UInt64, fallback: Double) -> Double
    func memoryPercent(residentBytes: UInt64, totalMemory: UInt64) -> Double
    func diskRates(previous: rusage_info_v6?, current: rusage_info_v6, elapsed: Double) -> DiskRates
    func networkRates(previous: (UInt64, UInt64)?, current: (UInt64, UInt64)?, elapsed: Double) -> NetworkRates
}
```
Concrete implementations live beside the protocols, but extracting them clarifies responsibilities and enables targeted tests.

### Caching & Lifetimes
- `ProcessCollector` retains PID-indexed caches, delegating buffer ownership to `ProcessEnumerator` so allocation logic stays co-located with sysctl usage.
- Access to caches remains confined to `collectorQueue`. Protocol methods that mutate internal state (e.g., buffer growth) will be marked `mutating` and invoked within the queue to preserve thread safety.
- Network sampler stores its own `lastSampleDate`, removing timestamp tracking from the collector and letting tests override the interval.

### Error Handling Strategy
- Propagate enumerator and sampler errors as debug logs while returning empty snapshots to maintain parity with current behavior.
- Standardize permission-denied handling in one place, tagging resulting `ProcessInfo.flags` cleanly.
- Provide optional hooks (future work) to expose sampler failures to the UI once monitoring is desired.

## Implementation Plan
1. **Type extraction**: Move data models and cache structs into `ProcessTypes.swift`. Update imports and access levels (internal for caches, public for UI-facing types).
2. **Enumerator module**: Introduce `ProcessEnumerator` with reusable buffer management. Update collector to hold one instance and request snapshots.
3. **Host sampler**: Extract host tick bookkeeping into `HostCPUSampler`. Replace local state in collector.
4. **Metrics calculator**: Move CPU/memory/disk/network math into a stateless helper struct. Adjust collector call sites to use the calculator.
5. **Network sampler**: Isolate `nettop` invocation, interval gating, and parsing logic into `NetworkUsageSampler`. Inject via protocol to collector.
6. **Collector consolidation**: Refactor `ProcessCollector` to orchestrate dependencies, update caches, and assemble `ProcessInfo` instances. Ensure API and behavior parity through inline assertions/logging during development.
7. **Documentation & cleanup**: Update `AGENTS.md` (developer notes) and add inline comments only where orchestration remains non-obvious.

## Migration & Testing
- Manual validation remains primary: `swift run SystemMonitor` plus `python3 cpu_stress_test.py` to check CPU/memory trends before and after refactor.
- Once splits exist, add targeted unit tests in `Tests/SystemMonitorTests` for metric calculator and `NetworkUsageSampler.parse` to prevent regressions.
- Monitor performance by comparing snapshot latency and memory usage against current implementation using lightweight logging.

## Risks & Mitigations
- **Performance regressions**: Keep buffer reuse in enumerator; benchmark snapshots to confirm equal or better timing.
- **Interface drift**: Maintain `ProcessInfo` semantics; verify SwiftUI views require no changes.
- **Concurrency errors**: Document queue ownership and keep mutable protocol methods confined to `collectorQueue` to avoid races.
- **Dependency injection overhead**: Provide default implementations so production code remains simple while enabling tests to supply mocks when needed.

## Open Questions
- Should `ProcessCollector` expose initializer overloads to inject mocks, or rely on factory helpers inside `SystemStats`?
- Do we persist `NetworkUsageSampler` interval as configurable state for power users?
- Are additional metrics (e.g., energy impact) worth scoping into the calculator now that the structure is modular?

## Rollout Checklist
- [ ] Land refactor in the order described above, verifying each phase with manual sampling.
- [ ] Add README snippet pointing to new module layout for contributors.
- [ ] Update future PR template to reference RFC-002 when touching collector components.
