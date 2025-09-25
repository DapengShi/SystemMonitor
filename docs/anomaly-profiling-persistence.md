# Anomalous Process Profiling Persistence (Draft)

## Goals
- Capture profiling artefacts for processes that trigger SystemMonitor alerts.
- Persist anomaly metadata for ~72 hours so users can review recent spikes.
- Provide a foundation for richer analytics without demanding additional tooling.

## Constraints and Assumptions
- Runs inside the existing menu bar app with minimal additional dependencies.
- Storage footprint should stay under ~50 MB assuming frequent purging.
- Profiles may be large; keep raw dumps on disk, store metadata pointers in the database.
- No blocking on the main thread; all writes run on a background queue.

## Storage Engine Considerations
### SQLite (recommended baseline)
- Native to Apple platforms, small footprint, easy to ship with SwiftPM.
- Works well for time-ordered writes, simple filtering, and retention pruning.
- Compatible with light wrappers such as GRDB/SQLite.swift or raw `sqlite3` APIs.

### DuckDB (optional analytical companion)
- Excels at window functions and ad-hoc analytics on larger datasets.
- Heavier binary (~5–7 MB) and less battle-tested for apps with frequent incremental writes.
- Suggested as an add-on for exporting snapshots rather than the primary event log.

## Data Model
| Table | Columns | Notes |
| --- | --- | --- |
| `profile_capture` | `id` INTEGER PRIMARY KEY AUTOINCREMENT | Internal identifier |
|  | `processName` TEXT | Display name when the alert fired |
|  | `pid` INTEGER | PID when captured |
|  | `triggerMetric` TEXT | e.g. `cpu`, `memory`, `diskIO` |
|  | `triggerValue` REAL | Percentage or MB value at alert time |
|  | `capturedAt` DATETIME | `CURRENT_TIMESTAMP` on insert |
|  | `profilePath` TEXT | Absolute/relative path to sample artefact |
|  | `durationSeconds` INTEGER | Length of profiling capture |
|  | `notes` TEXT | Optional JSON blob for extra metadata |

Indices:
- `CREATE INDEX idx_profile_capture_time ON profile_capture(capturedAt);`
- `CREATE INDEX idx_profile_capture_pid_time ON profile_capture(pid, capturedAt DESC);`

Retention policy:
- `DELETE FROM profile_capture WHERE capturedAt < datetime('now', '-3 days');`
- Schedule VACUUM weekly when the app is idle to reclaim disk space.

## Component Overview
- `ProfileCaptureService`: orchestrates capture commands (e.g. `sample`, `spindump`).
- `ProfileStore`: abstracts SQLite reads/writes, exposes async APIs.
- `RetentionManager`: periodic cleanup using the retention policy.
- `RecentProfilesViewModel`: feeds SwiftUI views with last-N anomalies.
- `ProfileBrowserView`: optional UI surface in the detail window to review captures.

## Flow Summary
1. Alert fires in `SystemStats` aggregator.
2. `ProfileCaptureService` spawns profiling command(s) on a background queue.
3. Results saved to `~/Library/Application Support/SystemMonitor/Profiles/<timestamp>-<pid>.sample`.
4. `ProfileStore.save(record: ProfileRecord)` inserts metadata linking to the file.
5. `RetentionManager` runs hourly to purge rows/files older than 72 hours.
6. UI layer queries `ProfileStore.fetchRecent(limit:)` to display records.

## Swift API Sketch
```swift
struct ProfileRecord: Identifiable {
    var id: Int64?
    let processName: String
    let pid: Int
    let triggerMetric: TriggerMetric
    let triggerValue: Double
    let capturedAt: Date
    let profilePath: URL
    let durationSeconds: Int
    var notes: [String: String]? // JSON encoded before persistence
}

enum TriggerMetric: String {
    case cpu
    case memory
    case diskIO
    case network
}

protocol ProfileStore {
    func migrateIfNeeded() throws
    func save(record: ProfileRecord) async throws -> ProfileRecord
    func fetchRecent(limit: Int) async throws -> [ProfileRecord]
    func deleteOlderThan(date: Date) async throws
}

final class SQLiteProfileStore: ProfileStore {
    private let queue = DispatchQueue(label: "profile-store", qos: .utility)
    private let db: OpaquePointer?

    init(databasePath: String) throws {
        // open/prepare pragmas, call `migrateIfNeeded()`
        db = try SQLiteOpener.open(path: databasePath)
    }

    func migrateIfNeeded() throws {
        try queue.sync {
            let sql = """
                CREATE TABLE IF NOT EXISTS profile_capture (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    processName TEXT NOT NULL,
                    pid INTEGER NOT NULL,
                    triggerMetric TEXT NOT NULL,
                    triggerValue REAL NOT NULL,
                    capturedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
                    profilePath TEXT NOT NULL,
                    durationSeconds INTEGER,
                    notes TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_profile_capture_time
                    ON profile_capture(capturedAt);
                CREATE INDEX IF NOT EXISTS idx_profile_capture_pid_time
                    ON profile_capture(pid, capturedAt DESC);
            """
            try SQLiteOpener.exec(db, sql: sql)
        }
    }

    func save(record: ProfileRecord) async throws -> ProfileRecord {
        try await queue.async {
            let sql = """
                INSERT INTO profile_capture
                (processName, pid, triggerMetric, triggerValue, capturedAt, profilePath, durationSeconds, notes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            let params: [SQLiteValue] = [
                .text(record.processName),
                .int(record.pid),
                .text(record.triggerMetric.rawValue),
                .double(record.triggerValue),
                .date(record.capturedAt),
                .text(record.profilePath.path),
                .int(record.durationSeconds),
                .text(encodeJSON(record.notes))
            ]
            let newId = try SQLiteOpener.insert(db, sql: sql, bindings: params)
            var saved = record
            saved.id = newId
            return saved
        }
    }

    func fetchRecent(limit: Int) async throws -> [ProfileRecord] {
        try await queue.async {
            let sql = """
                SELECT id, processName, pid, triggerMetric, triggerValue,
                       capturedAt, profilePath, durationSeconds, notes
                  FROM profile_capture
                 ORDER BY capturedAt DESC
                 LIMIT ?;
            """
            return try SQLiteOpener.query(db, sql: sql, bindings: [.int(limit)])
        }
    }

    func deleteOlderThan(date: Date) async throws {
        try await queue.async {
            let sql = "DELETE FROM profile_capture WHERE capturedAt < ?;"
            try SQLiteOpener.exec(db, sql: sql, bindings: [.date(date)])
        }
    }
}
```

Helper utilities such as `SQLiteOpener` encapsulate `sqlite3_open_v2`, statement preparation, and type bridging. Replace with GRDB or SQLite.swift if preferred.

## Retention and Cleanup Workflow
```swift
final class RetentionManager {
    private let store: ProfileStore
    private let fileManager: FileManager

    init(store: ProfileStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + .minutes(10), repeating: .hours(1))
        timer.setEventHandler { [weak self] in
            Task { await self?.purgeExpired() }
        }
        timer.resume()
    }

    @MainActor
    private func purgeExpired() async {
        let cutoff = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        try? await store.deleteOlderThan(date: cutoff)
        removeOrphanedFiles(olderThan: cutoff)
    }

    private func removeOrphanedFiles(olderThan cutoff: Date) {
        // Walk the profile directory and remove artefacts older than 3 days
    }
}
```

## UI Surface Ideas
- Add a “Recent Anomalies” section in `DetailView` with filtering by metric or process.
- Provide quick actions: reveal artefact in Finder, re-run profiling, copy summary.
- Offer export to CSV/JSON for sharing with support teams.

## DuckDB Extension (Future Work)
- Periodically export recent SQLite rows into a `.duckdb` database for advanced queries.
- Expose a developer-only command palette action to run templated analytics (e.g. peak CPU by process).

## Open Questions
- Where to store heavy artefacts (bundle vs. `Application Support` vs. iCloud Drive toggle).
- Whether profiling should be automatic or gated behind user opt-in due to CPU overhead.
- How to redact sensitive paths or arguments before sharing artefacts externally.
