import Foundation
import Darwin

protocol ProcessMetricsCalculating {
    func instantaneousCPUPercent(totalCPUTime: UInt64,
                                 lastCPUTime: UInt64,
                                 hostDeltaSeconds: Double?,
                                 cpuCoreCount: Int,
                                 kernFScale: Double,
                                 pctCPU: UInt32,
                                 fallbackInstant: Double,
                                 hasTaskInfo: Bool) -> Double

    func cumulativeCPUPercent(totalCPUTime: UInt64,
                              startTime: UInt64,
                              currentAbs: UInt64) -> Double

    func diskRates(previous: rusage_info_v6?, current: rusage_info_v6, elapsed: Double) -> DiskRates

    func networkRates(previous: (UInt64, UInt64)?, current: (UInt64, UInt64)?, elapsed: Double) -> NetworkRates

    func convertMachToSeconds(_ value: UInt64) -> Double
}

/// Performs per-process metric calculations using raw kernel counters.
struct ProcessMetricsCalculator: ProcessMetricsCalculating {
    private let timebaseInfo: mach_timebase_info_data_t

    init(timebaseInfo: mach_timebase_info_data_t) {
        self.timebaseInfo = timebaseInfo
    }

    func instantaneousCPUPercent(totalCPUTime: UInt64,
                                 lastCPUTime: UInt64,
                                 hostDeltaSeconds: Double?,
                                 cpuCoreCount: Int,
                                 kernFScale: Double,
                                 pctCPU: UInt32,
                                 fallbackInstant: Double,
                                 hasTaskInfo: Bool) -> Double {
        let sanitisedCoreCount = max(cpuCoreCount, 1)
        let maxPercent = Double(sanitisedCoreCount) * 100.0
        let clamped: (Double) -> Double = { value in
            let limited = value.isFinite ? value : 0
            return min(max(limited, 0.0), maxPercent)
        }

        if hasTaskInfo, let hostSeconds = hostDeltaSeconds, hostSeconds > 0 {
            let deltaCPU = totalCPUTime >= lastCPUTime ? totalCPUTime - lastCPUTime : 0
            let deltaCPUSeconds = convertMachToSeconds(deltaCPU)
            let percent = (deltaCPUSeconds / hostSeconds) * 100.0
            return clamped(percent)
        }

        let scaled = Double(pctCPU) / kernFScale * 100.0
        let fallback = scaled > 0 ? scaled : fallbackInstant
        return clamped(fallback)
    }

    func cumulativeCPUPercent(totalCPUTime: UInt64,
                              startTime: UInt64,
                              currentAbs: UInt64) -> Double {
        let elapsedAbs = currentAbs > startTime ? currentAbs - startTime : 0
        let elapsedSeconds = convertMachToSeconds(elapsedAbs)
        guard elapsedSeconds > 0 else { return 0 }
        let cpuSeconds = Double(totalCPUTime) / 1_000_000_000.0
        return (cpuSeconds / elapsedSeconds) * 100.0
    }

    func diskRates(previous: rusage_info_v6?, current: rusage_info_v6, elapsed: Double) -> DiskRates {
        guard elapsed > 0 else { return DiskRates(read: 0, write: 0, logical: 0) }
        guard let previous = previous else {
            return DiskRates(read: 0, write: 0, logical: 0)
        }
        let readDelta = current.ri_diskio_bytesread >= previous.ri_diskio_bytesread ? current.ri_diskio_bytesread - previous.ri_diskio_bytesread : 0
        let writeDelta = current.ri_diskio_byteswritten >= previous.ri_diskio_byteswritten ? current.ri_diskio_byteswritten - previous.ri_diskio_byteswritten : 0
        let logicalDelta = current.ri_logical_writes >= previous.ri_logical_writes ? current.ri_logical_writes - previous.ri_logical_writes : 0
        return DiskRates(
            read: Double(readDelta) / elapsed,
            write: Double(writeDelta) / elapsed,
            logical: Double(logicalDelta) / elapsed
        )
    }

    func networkRates(previous: (UInt64, UInt64)?, current: (UInt64, UInt64)?, elapsed: Double) -> NetworkRates {
        guard elapsed > 0 else { return NetworkRates(download: 0, upload: 0) }
        guard let current = current else { return NetworkRates(download: 0, upload: 0) }
        guard let previous = previous else { return NetworkRates(download: 0, upload: 0) }
        let inDelta = current.0 >= previous.0 ? current.0 - previous.0 : 0
        let outDelta = current.1 >= previous.1 ? current.1 - previous.1 : 0
        return NetworkRates(
            download: Double(inDelta) / elapsed,
            upload: Double(outDelta) / elapsed
        )
    }

    func convertMachToSeconds(_ value: UInt64) -> Double {
        let numer = Double(timebaseInfo.numer)
        let denom = Double(timebaseInfo.denom)
        let nanoseconds = Double(value) * (numer / denom)
        return nanoseconds / 1_000_000_000.0
    }
}
