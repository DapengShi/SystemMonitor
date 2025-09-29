import Foundation

enum ProcessMetricsStoreError: Error {
    case databaseOpenFailure(code: Int32, message: String)
    case statementPreparationFailure(message: String)
    case executionFailure(code: Int32, message: String)
    case fileSystemFailure(underlying: Error)
}

protocol ProcessMetricsStore: AnyObject {
    func append(samples: [ProcessMetricSample]) throws
    func fetchMetrics(pid: Int32, since: Date, limit: Int?) throws -> [ProcessMetricSample]
    func prune(before cutoff: Date) throws
    func databaseURL() -> URL
}

protocol ProcessMetricsRecording: AnyObject {
    func record(processes: [ProcessInfo], timestamp: Date)
}
