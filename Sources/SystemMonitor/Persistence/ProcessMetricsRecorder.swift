import Foundation
import os.log

final class ProcessMetricsRecorder: ProcessMetricsRecording {
    struct Configuration {
        let retentionInterval: TimeInterval
        let maxCommandLineLength: Int
        let cooldownInterval: TimeInterval

        static let `default` = Configuration(
            retentionInterval: 72 * 60 * 60,
            maxCommandLineLength: 1024,
            cooldownInterval: 60
        )
    }

    private struct Diagnostics {
        var lastErrorMessage: String?
        var lastErrorTimestamp: Date?
    }

    let store: ProcessMetricsStore
    private let configuration: Configuration
    private let queue = DispatchQueue(label: "com.systemmonitor.metrics.recorder", qos: .utility)
    private let dateProvider: () -> Date
    private var cooldownUntil: Date?
    private var diagnostics = Diagnostics()
    private let logger = Logger(subsystem: "com.systemmonitor", category: "ProcessMetricsRecorder")

    init(store: ProcessMetricsStore,
         configuration: Configuration = .default,
         dateProvider: @escaping () -> Date = Date.init) {
        self.store = store
        self.configuration = configuration
        self.dateProvider = dateProvider
    }

    func record(processes: [ProcessInfo], timestamp: Date) {
        guard !processes.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            if self.isCoolingDown(now: self.dateProvider()) {
                return
            }

            let samples = processes.map { process in
                ProcessMetricSample(
                    processInfo: process,
                    collectedAt: timestamp,
                    maxCommandLineLength: self.configuration.maxCommandLineLength
                )
            }

            do {
                try self.store.append(samples: samples)
                let cutoff = timestamp.addingTimeInterval(-self.configuration.retentionInterval)
                try self.store.prune(before: cutoff)
                self.cooldownUntil = nil
            } catch {
                self.cooldownUntil = self.dateProvider().addingTimeInterval(self.configuration.cooldownInterval)
                self.logErrorIfNeeded(error)
            }
        }
    }

    private func isCoolingDown(now: Date) -> Bool {
        guard let cooldownUntil else { return false }
        return now < cooldownUntil
    }

    private func logErrorIfNeeded(_ error: Error) {
        let message = String(describing: error)
        let now = dateProvider()
        let shouldLog: Bool
        if diagnostics.lastErrorMessage != message {
            shouldLog = true
        } else if let lastTimestamp = diagnostics.lastErrorTimestamp {
            shouldLog = now.timeIntervalSince(lastTimestamp) > 300
        } else {
            shouldLog = true
        }

        if shouldLog {
            logger.error("Process metrics recorder error: \(message, privacy: .public)")
            diagnostics.lastErrorMessage = message
            diagnostics.lastErrorTimestamp = now
        }
    }
}
