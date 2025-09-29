import Foundation

/// Immutable representation of a persisted per-process metric snapshot.
struct ProcessMetricSample: Equatable {
    let pid: Int32
    let parentPid: Int32
    let name: String
    let commandLine: String
    let username: String
    let cpuInstantPercent: Double
    let cpuCumulativePercent: Double
    let residentBytes: UInt64
    let memoryPercent: Double
    let threadCount: Int
    let networkInBytesPerSecond: Double
    let networkOutBytesPerSecond: Double
    let diskReadBytesPerSecond: Double
    let diskWriteBytesPerSecond: Double
    let logicalWriteBytesPerSecond: Double
    let flags: ProcessFlags
    let collectedAt: Date
}

extension ProcessMetricSample {
    init(processInfo: ProcessInfo, collectedAt: Date, maxCommandLineLength: Int) {
        self.pid = processInfo.pid
        self.parentPid = processInfo.parentPid
        self.name = ProcessMetricSample.truncate(processInfo.name, limit: 255)
        self.commandLine = ProcessMetricSample.truncate(processInfo.commandLine, limit: maxCommandLineLength)
        self.username = ProcessMetricSample.truncate(processInfo.username, limit: 255)
        self.cpuInstantPercent = processInfo.cpuInstantPercent
        self.cpuCumulativePercent = processInfo.cpuCumulativePercent
        self.residentBytes = processInfo.residentBytes
        self.memoryPercent = processInfo.memoryPercent
        self.threadCount = processInfo.threadCount
        self.networkInBytesPerSecond = processInfo.networkInBytesPerSecond
        self.networkOutBytesPerSecond = processInfo.networkOutBytesPerSecond
        self.diskReadBytesPerSecond = processInfo.diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = processInfo.diskWriteBytesPerSecond
        self.logicalWriteBytesPerSecond = processInfo.logicalWriteBytesPerSecond
        self.flags = processInfo.flags
        self.collectedAt = collectedAt
    }

    private static func truncate(_ string: String, limit: Int) -> String {
        guard limit > 0 else { return string }
        if string.count <= limit { return string }
        return String(string.prefix(limit))
    }
}
