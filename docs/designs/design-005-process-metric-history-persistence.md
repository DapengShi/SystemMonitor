# Design-005: Per-Process Metric History Persistence

- Related RFC: [RFC-005: Per-Process Metric History Persistence](../RFCs/RFC-005-process-metric-history-persistence.md)
- Status: Draft
- Authors: Codex
- Updated: 2025-09-29

## Overview
This design details how to extend SystemMonitor with a lightweight SQLite-backed history store that retains per-process metrics for the past three days. The implementation wires a recording layer into the existing `ProcessCollector` sampling loop, persists structured samples using the `sqlite3` C API, and exposes query hooks for forthcoming UI consumers. Emphasis is placed on minimal footprint, deterministic retention, and isolation from UI threads.

## Scope & Constraints
- **In scope**: storage schema, recorder plumbing, retention policy, error handling/backoff, and public accessors for historical queries.
- **Out of scope**: visualization UI, long-term archival/export, or refactoring existing metric calculators.
- **Constraints**: no third-party persistence dependencies, maintain current sampling cadence, avoid blocking `collectorQueue`, and tolerate intermittent I/O failures without crashing.

## Data Model
### Swift Types
- `struct ProcessMetricSample`: mirrors the persisted columns (`pid`, `parentPid`, `name`, `commandLine`, `username`, CPU metrics, memory metrics, network/disk rates, `threadCount`, `flags`, `residentBytes`, `timestamp`).
- `protocol ProcessMetricsStore`: defines synchronous throwing APIs for appending, fetching, and pruning samples.
- `final class ProcessMetricsRecorder`: owns a background queue, maintains a write cooldown state, and bridges between `ProcessCollector` snapshots and the store.

### SQLite Schema
```sql
CREATE TABLE IF NOT EXISTS process_metric_samples (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    collected_at REAL NOT NULL,
    pid INTEGER NOT NULL,
    parent_pid INTEGER NOT NULL,
    name TEXT NOT NULL,
    command_line TEXT NOT NULL,
    username TEXT NOT NULL,
    cpu_instant REAL NOT NULL,
    cpu_cumulative REAL NOT NULL,
    resident_bytes INTEGER NOT NULL,
    memory_percent REAL NOT NULL,
    thread_count INTEGER NOT NULL,
    network_in_bps REAL NOT NULL,
    network_out_bps REAL NOT NULL,
    disk_read_bps REAL NOT NULL,
    disk_write_bps REAL NOT NULL,
    logical_write_bps REAL NOT NULL,
    flags INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_process_metric_samples_pid_ts
    ON process_metric_samples(pid, collected_at DESC);
CREATE INDEX IF NOT EXISTS idx_process_metric_samples_ts
    ON process_metric_samples(collected_at);
```
- Timestamps stored as Unix epoch seconds (`REAL`).
- Flags stored as integer bitmask (matching `ProcessFlags.rawValue`).

## Architecture
### Storage Layer (`Sources/SystemMonitor/Persistence`)
- New folder `Persistence/` containing:
  - `ProcessMetricSample.swift`: model struct + conversion helpers (`init(processInfo:timestamp:)`).
  - `ProcessMetricsStore.swift`: protocol and error definitions (`enum ProcessMetricsStoreError`).
  - `SQLiteProcessMetricsStore.swift`: concrete implementation using `sqlite3`.
  - `SQLiteDatabase.swift`: reusable wrapper for opening DB, preparing statements, binding values, and executing queries.

### Recorder Integration
- Extend `ProcessCollector` initializer with optional `metricsRecorder: ProcessMetricsRecording?` dependency (new protocol for testability). Default to concrete recorder wired from `SystemStats`.
- Within `snapshotProcesses`, capture `Date()` once, produce `[ProcessInfo]` as today. After array assembled and before returning, call `metricsRecorder?.record(processes:processes, timestamp: date)`. Recorder dispatches to its own serial queue to build samples and invoke store appends.
- Recorder responsibilities:
  - Convert `ProcessInfo` to `ProcessMetricSample` (ensuring string truncation caps, e.g., 1024 chars for command lines).
  - Skip recording if write cooldown active (set when SQLite repeatedly fails). Cooldown resets after a successful write or when timer expires.
  - On successful append, compute `cutoff = timestamp - 72h` and call `store.prune(before: cutoff)`.
  - Optionally schedule `VACUUM` when DB size exceeds configurable threshold (read via `FileManager.attributesOfItem`). Limit to once per 24h.

### Threading & Safety
- SQLite store uses a dedicated serial dispatch queue (`storageQueue`) to synchronize access. All public methods wrap calls to queue-synchronised helpers to avoid concurrent statement usage.
- Recorder queue decouples `ProcessCollector` from disk latency. Interactions: `collectorQueue` (existing) -> `metricsRecorderQueue` -> `storageQueue`.
- Use `DispatchSourceTimer` or `DispatchWorkItem` for retention/vacuum tasks to keep operations off main/collector threads.

### Error Handling
- Define `ProcessMetricsRecorder.Diagnostics` struct capturing last error timestamp and message. Provide log helper using `os_log` (only available on macOS 10.12+; wrap for availability).
- On `append` failure: set cooldown for `60` seconds, log once, drop batch.
- On `prune` failure: log warning, keep cooldown unchanged.
- Ensure `ProcessCollector` continues returning live metrics unaffected by persistence failures.

### Configuration
- `ProcessMetricsRecorder.Configuration` options:
  - `retentionInterval: TimeInterval` (default `72 * 3600`).
  - `maxCommandLineLength: Int` (default `1024`).
  - `cooldownInterval: TimeInterval` (default `60`).
  - `vacuumTriggerBytes: Int` (default `10 * 1024 * 1024`).
- `SystemStats` instantiates recorder with defaults and passes optional custom configuration for future tuning.

### Query API
- Add to `SystemStats`:
  ```swift
  func metricsHistory(pid: Int32, since: Date) throws -> [ProcessMetricSample] {
      try metricsStore.fetchMetrics(pid: pid, since: since)
  }
  ```
- Expose `metricsStore` property only when recorder enabled, to avoid leaking storage details elsewhere.
- Fetch implementation uses prepared statement with `ORDER BY collected_at DESC` limit optional parameter.

## File Layout Changes
```
Sources/SystemMonitor/
  Persistence/
    ProcessMetricSample.swift
    ProcessMetricsStore.swift
    SQLiteProcessMetricsStore.swift
    SQLiteDatabase.swift
  Processes/
    ProcessCollector.swift (inject recorder)
  Support/
    (if needed) OSLog+Extensions.swift
```
- `ProcessCollector` gains new dependency property `metricsRecorder: ProcessMetricsRecording?` and uses it in `snapshotProcesses`.
- `SystemStats` stores `metricsRecorder` and `metricsStore` references, wiring them in initializer.

## Implementation Steps
1. **Scaffold Models & Protocols**: Add `ProcessMetricSample`, `ProcessMetricsStore`, and minimal errors/enums.
2. **SQLite Wrapper**: Implement `SQLiteDatabase` helper (open, close, prepare, bind, step). Write targeted unit-style assertions if/when test target exists; otherwise rely on manual validation.
3. **Concrete Store**: Build `SQLiteProcessMetricsStore` with init performing migrations, `append(samples:)`, `fetchMetrics(pid:since:)`, and `prune(before:)`. Ensure statements reuse via prepared handles cached on queue.
4. **Recorder**: Implement `ProcessMetricsRecorder` with conversion, queue management, cooldown, and retention/trimming logic.
5. **Integrate with Collector**: Update `ProcessCollector` and `SystemStats` to instantiate and invoke recorder. Provide feature flag check (e.g., `ProcessMetricsRecorder.isEnabled` static bool).
6. **Configuration & Defaults**: Determine database path using `FileManager.default.urls(for:in:)`. Create directories lazily.
7. **Diagnostics**: Add lightweight logging wrapper; ensure logs throttle to avoid flooding.
8. **Docs**: Update `USER_GUIDE.md` or `docs/anomaly-profiling-persistence.md` with pointer to new history store and manual inspection instructions.
9. **Validation**: Run `swift build`, launch app, stress CPU/memory, and inspect DB via `sqlite3 process_metrics.sqlite "SELECT COUNT(*)"` to confirm inserts and pruning.

## Testing Strategy
- Manual smoke tests: run `swift run SystemMonitor`, interact for > 3 minutes, confirm DB file growth and retention deletion (`SELECT MIN(collected_at)` vs cutoff).
- Add instrumentation toggled via debug flag to dump last insert count into console for quick validation.
- Future automated tests (once test target exists): stub `InMemoryMetricsStore` to validate recorder batching and cooldown behaviour.

## Risks & Mitigations
- **Disk space growth**: Mitigated via strict retention and optional vacuum. Monitor file size in diagnostics.
- **SQLite contention**: Single-writer queue prevents concurrency issues; WAL mode reduces lock duration.
- **Privacy concerns**: Document stored fields; consider future opt-out toggle. Keep DB under user profile.
- **Performance impact**: Async recorder prevents blocking; measure with Instruments during QA.

## Open Questions
- Should the recorder skip processes with zero activity to reduce noise (e.g., filter by CPU/memory thresholds)? Currently recording all for completeness.
- Do we need encryption-at-rest for command lines/usernames? Possibly optional if storing sensitive data becomes a concern.
- How will future UI consumers request aggregated data (average/min/max per hour) — should the store expose aggregation helpers now or later?

