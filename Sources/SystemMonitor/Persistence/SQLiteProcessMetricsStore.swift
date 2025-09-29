import Foundation
import SQLite3

final class SQLiteProcessMetricsStore: ProcessMetricsStore {
    struct Configuration {
        let retentionInterval: TimeInterval
        let vacuumTriggerBytes: Int
        let minimumVacuumInterval: TimeInterval

        static let `default` = Configuration(
            retentionInterval: 72 * 60 * 60,
            vacuumTriggerBytes: 10 * 1024 * 1024,
            minimumVacuumInterval: 24 * 60 * 60
        )
    }

    private let configuration: Configuration
    private let databaseURLValue: URL
    private let database: SQLiteDatabase
    private let insertStatement: SQLiteStatement
    private let pruneStatement: SQLiteStatement
    private let fetchStatement: SQLiteStatement
    private let queue = DispatchQueue(label: "com.systemmonitor.metrics.sqlite-store")
    private var lastVacuumRun: Date?

    init(url: URL? = nil, configuration: Configuration = .default) throws {
        self.configuration = configuration
        let resolvedURL = try url ?? SQLiteProcessMetricsStore.defaultDatabaseURL()
        self.databaseURLValue = resolvedURL
        let directory = resolvedURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ProcessMetricsStoreError.fileSystemFailure(underlying: error)
        }
        database = try SQLiteDatabase(url: resolvedURL)
        try SQLiteProcessMetricsStore.applyDefaultPragmas(database)
        try SQLiteProcessMetricsStore.migrate(database)
        insertStatement = try database.prepare("""
            INSERT INTO process_metric_samples (
                collected_at,
                pid,
                parent_pid,
                name,
                command_line,
                username,
                cpu_instant,
                cpu_cumulative,
                resident_bytes,
                memory_percent,
                thread_count,
                network_in_bps,
                network_out_bps,
                disk_read_bps,
                disk_write_bps,
                logical_write_bps,
                flags
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
        """)
        pruneStatement = try database.prepare("DELETE FROM process_metric_samples WHERE collected_at < ?1")
        fetchStatement = try database.prepare("""
            SELECT
                collected_at,
                pid,
                parent_pid,
                name,
                command_line,
                username,
                cpu_instant,
                cpu_cumulative,
                resident_bytes,
                memory_percent,
                thread_count,
                network_in_bps,
                network_out_bps,
                disk_read_bps,
                disk_write_bps,
                logical_write_bps,
                flags
            FROM process_metric_samples
            WHERE pid = ?1 AND collected_at >= ?2
            ORDER BY collected_at ASC
            LIMIT ?3
        """)
    }

    func append(samples: [ProcessMetricSample]) throws {
        guard !samples.isEmpty else { return }
        try queue.sync {
            try beginTransaction()
            var transactionError: Error?
            for sample in samples {
                insertStatement.reset()
                bind(sample, to: insertStatement)
                let result = insertStatement.step()
                if result != SQLITE_DONE {
                    transactionError = ProcessMetricsStoreError.executionFailure(
                        code: result,
                        message: "failed to insert sample"
                    )
                    break
                }
            }
            if let transactionError {
                rollbackTransaction()
                throw transactionError
            }
            try commitTransaction()
            try vacuumIfNeededLocked()
        }
    }

    func fetchMetrics(pid: Int32, since: Date, limit: Int?) throws -> [ProcessMetricSample] {
        try queue.sync {
            fetchStatement.reset()
            fetchStatement.bind(Double(since.timeIntervalSince1970), at: 2)
            fetchStatement.bind(pid, at: 1)
            if let limit {
                fetchStatement.bind(Int32(limit), at: 3)
            } else {
                fetchStatement.bind(Int32(-1), at: 3)
            }

            var results: [ProcessMetricSample] = []
            while true {
                let stepResult = fetchStatement.step()
                if stepResult == SQLITE_ROW {
                    results.append(makeSample(from: fetchStatement))
                } else if stepResult == SQLITE_DONE {
                    break
                } else {
                    throw ProcessMetricsStoreError.executionFailure(code: stepResult, message: "fetch failed")
                }
            }
            return results
        }
    }

    func prune(before cutoff: Date) throws {
        try queue.sync {
            pruneStatement.reset()
            pruneStatement.bind(Double(cutoff.timeIntervalSince1970), at: 1)
            let result = pruneStatement.step()
            if result != SQLITE_DONE {
                throw ProcessMetricsStoreError.executionFailure(code: result, message: "prune failed")
            }
        }
    }

    func databaseURL() -> URL {
        databaseURLValue
    }

    private func bind(_ sample: ProcessMetricSample, to statement: SQLiteStatement) {
        statement.bind(sample.collectedAt.timeIntervalSince1970, at: 1)
        statement.bind(sample.pid, at: 2)
        statement.bind(sample.parentPid, at: 3)
        statement.bind(sample.name, at: 4)
        statement.bind(sample.commandLine, at: 5)
        statement.bind(sample.username, at: 6)
        statement.bind(sample.cpuInstantPercent, at: 7)
        statement.bind(sample.cpuCumulativePercent, at: 8)
        statement.bind(sample.residentBytes, at: 9)
        statement.bind(sample.memoryPercent, at: 10)
        statement.bind(Int32(sample.threadCount), at: 11)
        statement.bind(sample.networkInBytesPerSecond, at: 12)
        statement.bind(sample.networkOutBytesPerSecond, at: 13)
        statement.bind(sample.diskReadBytesPerSecond, at: 14)
        statement.bind(sample.diskWriteBytesPerSecond, at: 15)
        statement.bind(sample.logicalWriteBytesPerSecond, at: 16)
        statement.bind(Int32(sample.flags.rawValue), at: 17)
    }

    private func makeSample(from statement: SQLiteStatement) -> ProcessMetricSample {
        let timestamp = Date(timeIntervalSince1970: statement.columnDouble(0))
        let pid = statement.columnInt(1)
        let parentPid = statement.columnInt(2)
        return ProcessMetricSample(
            pid: pid,
            parentPid: parentPid,
            name: statement.columnString(3),
            commandLine: statement.columnString(4),
            username: statement.columnString(5),
            cpuInstantPercent: statement.columnDouble(6),
            cpuCumulativePercent: statement.columnDouble(7),
            residentBytes: UInt64(bitPattern: statement.columnInt64(8)),
            memoryPercent: statement.columnDouble(9),
            threadCount: Int(statement.columnInt(10)),
            networkInBytesPerSecond: statement.columnDouble(11),
            networkOutBytesPerSecond: statement.columnDouble(12),
            diskReadBytesPerSecond: statement.columnDouble(13),
            diskWriteBytesPerSecond: statement.columnDouble(14),
            logicalWriteBytesPerSecond: statement.columnDouble(15),
            flags: ProcessFlags(rawValue: Int(statement.columnInt(16))),
            collectedAt: timestamp
        )
    }

    private func beginTransaction() throws {
        try database.execute("BEGIN IMMEDIATE TRANSACTION")
    }

    private func commitTransaction() throws {
        try database.execute("COMMIT TRANSACTION")
    }

    private func rollbackTransaction() {
        try? database.execute("ROLLBACK TRANSACTION")
    }

    private func vacuumIfNeededLocked() throws {
        guard configuration.vacuumTriggerBytes > 0 else { return }
        let now = Date()
        if let lastVacuumRun, now.timeIntervalSince(lastVacuumRun) < configuration.minimumVacuumInterval {
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: databaseURLValue.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size >= configuration.vacuumTriggerBytes else { return }
        try database.execute("VACUUM")
        lastVacuumRun = now
    }

    private static func applyDefaultPragmas(_ database: SQLiteDatabase) throws {
        try database.execute("PRAGMA journal_mode=WAL")
        try database.execute("PRAGMA synchronous=NORMAL")
    }

    private static func migrate(_ database: SQLiteDatabase) throws {
        try database.execute("""
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
            )
        """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_process_metric_samples_pid_ts ON process_metric_samples(pid, collected_at DESC)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_process_metric_samples_ts ON process_metric_samples(collected_at)")
    }

    private static func defaultDatabaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("SystemMonitor", isDirectory: true)
            .appendingPathComponent("process_metrics.sqlite", isDirectory: false)
    }
}
