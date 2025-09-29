# RFC-005: Per-Process Metric History Persistence

- Status: Draft
- Authors: Codex
- Created: 2025-09-29
- Components: Sources/SystemMonitor/ProcessCollector.swift, Sources/SystemMonitor/Processes, Sources/SystemMonitor/Persistence, Sources/SystemMonitor/SystemStats.swift, docs/designs

## Context
SystemMonitor samples live process metrics (CPU, memory, network, disk) but discards each snapshot after rendering the menu bar UI. Power users want to inspect how specific processes behaved over time, especially while diagnosing intermittent spikes. Without historical storage, investigations must happen in real time and insights are lost when the app closes. A light-weight persistence layer is needed to retain per-process metrics for short windows without introducing heavy dependencies.

## Goals
- Persist per-process metric samples for the most recent three days (72 hours) in a local SQLite database.
- Capture the same metrics currently surfaced in `ProcessInfo` (CPU%, memory%, resident bytes, network, disk, thread count, flags) with timestamps for each process PID.
- Provide read APIs to query historical metrics for a given process, aggregated or raw, to power future UI features.
- Keep storage self-contained (no external services) and resilient across app restarts, with automatic pruning beyond the three-day retention window.

## Non-Goals
- Visualising the history in the UI (charts, timelines). This RFC only covers data capture and storage plumbing.
- Long-term archival beyond three days or export facilities.
- Full-text or fuzzy search across historical command lines/usernames.
- Collecting kernel-level counters not already exposed via `ProcessCollector`.

## Functional Requirements
- Sample cadence matches existing `ProcessCollector.snapshotProcesses(limit:)` invocations (approximately every 2 seconds via `SystemStats`). Each snapshot writes batch entries within the same transaction.
- Schema stores: timestamp (`Date`), PID, parent PID, process identity (name, command line, username), CPU instant %, CPU cumulative %, memory %, resident bytes, thread count, network in/out (bytes per second), disk read/write/logical (bytes per second), and flags.
- Enforce rolling retention: delete samples older than 72 hours on each write batch before inserting new rows.
- Guard against unbounded growth via pragmatic limits (e.g., cap per-batch size, vacuum weekly when file > 10 MB).
- Gracefully handle SQLite failures (disk full, IO errors) without crashing the sampling loop; log once per error type and continue.

## Proposed Solution
### Storage Abstraction
- Introduce `ProcessMetricsStore` protocol under `Sources/SystemMonitor/Persistence` defining async methods:
  - `func append(samples: [ProcessMetricSample], collectedAt: Date)`
  - `func fetchMetrics(pid: Int32, since: Date) throws -> [ProcessMetricSample]`
  - `func prune(before: Date) throws`
- Define `ProcessMetricSample` struct mirroring the persisted columns.
- Supply concrete `SQLiteProcessMetricsStore` backed by the system `sqlite3` C API to avoid extra dependencies.

### Database Location & Lifecycle
- Place database at `~/Library/Application Support/SystemMonitor/process_metrics.sqlite` (create directories as needed).
- On first launch, run migration `001` that creates table `process_metric_samples` with indices on `(pid, collected_at)` and `(collected_at)`.
- Wrap access in a serial dispatch queue to maintain thread safety around SQLite statements.
- Use WAL mode for reliability (`PRAGMA journal_mode=WAL`) and set `synchronous=NORMAL` for balanced durability/perf.

### Collector Integration
- Extend `ProcessCollector` to accept optional `ProcessMetricsRecorder` dependency responsible for transforming `ProcessInfo` snapshots into `ProcessMetricSample`s and dispatching them to the store.
- `ProcessMetricsRecorder` batches writes: when `snapshotProcesses` returns, map each `ProcessInfo` to sample, pass to recorder with shared timestamp, and perform asynchronous write on a background queue to avoid blocking UI sampling.
- After each write, trigger retention: compute `cutoff = Date().addingTimeInterval(-3 * 24 * 60 * 60)` and call `prune(before: cutoff)`.

### Error Handling & Telemetry
- Swallow errors in recorder but emit `os_log` warnings (development builds) with counters to avoid log flooding (`os_log_interval` or manual throttling).
- If the store throws during writes, pause persistence for a cool-off period (e.g., 60 seconds) before retrying to prevent repeated disk hits.

### Extensibility
- Expose query method via `SystemStats` (e.g., `func metricsHistory(for pid: Int32, hours: Int) -> [ProcessMetricSample]`) to prepare for UI consumers.
- Document schema in `docs/designs/design-005-process-metric-history-persistence.md`.

## Open Questions
- Should we normalise process identity (name, command) into a separate table to reduce duplication, or is denormalisation acceptable for a 3-day window?
- How aggressively should the recorder back off on repeated SQLite failures (e.g., exponential vs. fixed cool-off)?
- Do we need to redact process command lines/usernames before storage for privacy preferences?

## Alternatives Considered
- **Core Data**: Higher-level API but introduces additional runtime overhead and codegen; rejected for heavier footprint.
- **In-memory ring buffer**: Low complexity but loses data across restarts, failing the persistence requirement.
- **CSV/JSON logs**: Simple append-only writes but lack indexing for targeted queries and have higher parsing overhead.

## Rollout
- Implement behind feature flag (`ProcessMetricsRecorder.isEnabled`) defaulting to true; allow quick disable if persistence issues arise.
- Ship migrations and recorder in a single PR with documentation updates. Manual QA should stress memory/network heavy processes and verify entries via sqlite CLI.

