import Foundation
import Darwin

struct ProcessFlags: OptionSet {
    let rawValue: Int
    static let cpuRestricted = ProcessFlags(rawValue: 1 << 0)
    static let networkUnavailable = ProcessFlags(rawValue: 1 << 1)
    static let permissionDenied = ProcessFlags(rawValue: 1 << 2)
}

private struct CachedProcess {
    var lastTotalCPUTime: UInt64
    var lastSampleAbsTime: UInt64
    var lastRusage: rusage_info_v6
    var commandLine: String
    var username: String
    var networkSnapshot: (bytesIn: UInt64, bytesOut: UInt64)?
    var cpuCumulativeFallback: Double
    var lastResidentBytes: UInt64
    var lastThreadCount: Int
    var cpuInstantFallback: Double
}

struct HostMetrics {
    let cpuUsage: Double
    let memoryUsage: Double
}

struct ProcessInfo: Identifiable {
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

    var id: Int32 { pid }

    var cpuUsage: Double { cpuInstantPercent }
    var memoryUsage: Double { memoryPercent }
    var isHighCPU: Bool { cpuInstantPercent > 80.0 }
    var isHighMemory: Bool { memoryPercent > 80.0 }
    var isAbnormal: Bool { isHighCPU || isHighMemory }
}

final class ProcessCollector {
    private let collectorQueue = DispatchQueue(label: "com.systemmonitor.process.collector", qos: .userInitiated)
    private var processListBuffer: UnsafeMutableRawPointer?
    private var processListCapacity: Int = 0
    private var processListLength: Int = 0
    private var cachedProcesses: [Int32: CachedProcess] = [:]
    private var networkTotals: [Int32: (UInt64, UInt64)] = [:]
    private var lastNetworkSample: Date = .distantPast
    private let networkSampleInterval: TimeInterval = 5.0
    private let commandBufferSize = 8192
    private let usernameBufferSize = 256
    private var timebaseInfo = mach_timebase_info_data_t()
    private let cpuCoreCount: Int
    private let totalMemoryBytes: UInt64
    private let clkTck: Double
    private let kernFScale: Double
    private var previousHostTotalTicks: UInt64?
    private var previousHostCPUCount: Int = 1

    init() {
        mach_timebase_info(&timebaseInfo)
        var cores = sysconf(_SC_NPROCESSORS_ONLN)
        if cores < 1 { cores = 1 }
        cpuCoreCount = Int(cores)
        let ticksPerSecond = sysconf(_SC_CLK_TCK)
        clkTck = ticksPerSecond > 0 ? Double(ticksPerSecond) : 100.0
        var mem: UInt64 = 0
        var memSize = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &mem, &memSize, nil, 0)
        totalMemoryBytes = mem

        var fscale: Int32 = 2048
        var fscaleSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.fscale", &fscale, &fscaleSize, nil, 0) != 0 {
            fscale = 2048
        }
        kernFScale = Double(fscale)
    }

    deinit {
        if let buffer = processListBuffer {
            buffer.deallocate()
        }
    }

    func snapshotProcesses(limit: Int = 0) -> [ProcessInfo] {
        return collectorQueue.sync {
            let nowAbs = mach_absolute_time()
            let hostDeltaSeconds = captureHostDeltaSeconds()
            guard let processes = readProcessList(nowAbs: nowAbs, hostDeltaSeconds: hostDeltaSeconds) else { return [] }
            let slice: ArraySlice<ProcessInfo>
            if limit > 0 && processes.count > limit {
                slice = processes[..<limit]
            } else {
                slice = processes[processes.indices]
            }
            return Array(slice)
        }
    }

    private func readProcessList(nowAbs: UInt64, hostDeltaSeconds: Double?) -> [ProcessInfo]? {
        guard let procPointer = fetchKinfoProcBuffer() else { return nil }
        let length = processListLength
        let count = length / MemoryLayout<kinfo_proc>.stride
        var processes: [ProcessInfo] = []
        processes.reserveCapacity(count)
        let typedPointer = procPointer.bindMemory(to: kinfo_proc.self, capacity: count)
        updateNetworkTotalsIfNeeded()

        var currentPIDs: Set<Int32> = []

        for index in 0..<count {
            var kproc = typedPointer[index]
            let pid = kproc.kp_proc.p_pid
            if pid <= 0 { continue }
            currentPIDs.insert(pid)

            var flags: ProcessFlags = []

            var taskInfo = proc_taskinfo()
            let taskInfoSize = MemoryLayout<proc_taskinfo>.stride
            let tiBytes = withUnsafeMutablePointer(to: &taskInfo) { pointer -> Int32 in
                pointer.withMemoryRebound(to: UInt8.self, capacity: taskInfoSize) { rebound in
                    return proc_pidinfo(Int32(pid), PROC_PIDTASKINFO, 0, rebound, Int32(taskInfoSize))
                }
            }
            let hasTaskInfo = (tiBytes == Int32(taskInfoSize))
            if !hasTaskInfo {
                flags.insert(.permissionDenied)
            }

            var rusage = rusage_info_v6()
            var rawPointer: Optional<UnsafeMutableRawPointer> = nil
            withUnsafeMutablePointer(to: &rusage) { pointer in
                rawPointer = Optional(UnsafeMutableRawPointer(pointer))
            }
            let rusageResult = withUnsafeMutablePointer(to: &rawPointer) { rawPtr -> Int32 in
                return proc_pid_rusage(Int32(pid), RUSAGE_INFO_V6, rawPtr)
            }
            if rusageResult != 0 {
                memset(&rusage, 0, MemoryLayout<rusage_info_v6>.size)
            }

            var bsdInfo = proc_bsdinfo()
            let bsdInfoSize = MemoryLayout<proc_bsdinfo>.stride
            let bsdBytes = withUnsafeMutablePointer(to: &bsdInfo) { pointer -> Int32 in
                pointer.withMemoryRebound(to: UInt8.self, capacity: bsdInfoSize) { rebound in
                    return proc_pidinfo(Int32(pid), PROC_PIDTBSDINFO, 0, rebound, Int32(bsdInfoSize))
                }
            }
            let name: String
            if bsdBytes == Int32(bsdInfoSize) {
                name = withUnsafePointer(to: bsdInfo.pbi_name) { pointer -> String in
                    return String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self))
                }
            } else {
                name = withUnsafePointer(to: &kproc.kp_proc.p_comm.0) { ptr -> String in
                    return String(cString: ptr)
                }
            }

            let parentPid = kproc.kp_eproc.e_ppid
            let username = resolveUsername(uid: kproc.kp_eproc.e_ucred.cr_uid, pid: pid)
            let command = resolveCommandLine(pid: pid)

            let cache = cachedProcesses[pid]
            let totalCPUTime = hasTaskInfo ? taskInfo.pti_total_user + taskInfo.pti_total_system : (cache?.lastTotalCPUTime ?? 0)
            let lastCPUTime = cache?.lastTotalCPUTime ?? totalCPUTime
            let lastSampleAbsTime = cache?.lastSampleAbsTime ?? nowAbs
            let cpuPercent: Double
            if hasTaskInfo, let hostSeconds = hostDeltaSeconds, hostSeconds > 0 {
                let deltaCPU = totalCPUTime >= lastCPUTime ? totalCPUTime - lastCPUTime : 0
                let deltaCPUSeconds = convertMachToSeconds(deltaCPU)
                let percent = (deltaCPUSeconds / hostSeconds) * 100.0
                cpuPercent = percent.isFinite ? min(max(percent, 0.0), Double(cpuCoreCount) * 100.0) : 0.0
            } else {
                let scaled = Double(kproc.kp_proc.p_pctcpu) / kernFScale * 100.0
                let fallback = scaled > 0 ? scaled : (cache?.cpuInstantFallback ?? 0.0)
                cpuPercent = min(max(fallback, 0.0), Double(cpuCoreCount) * 100.0)
            }
            let cumulativePercent: Double
            if hasTaskInfo {
                cumulativePercent = computeCumulativeCPUPercent(totalCPUTime: totalCPUTime, startTime: rusage.ri_proc_start_abstime, currentAbs: nowAbs)
            } else {
                cumulativePercent = cache?.cpuCumulativeFallback ?? 0.0
            }

            let residentBytes: UInt64
            if hasTaskInfo {
                residentBytes = taskInfo.pti_resident_size
            } else {
                residentBytes = cache?.lastResidentBytes ?? 0
            }
            let memoryPercent = totalMemoryBytes > 0 ? (Double(residentBytes) / Double(totalMemoryBytes)) * 100.0 : 0
            let threadCount = hasTaskInfo ? Int(taskInfo.pti_threadnum) : (cache?.lastThreadCount ?? 0)

            let previousNetwork = cache?.networkSnapshot
            let currentNetwork = networkTotals[pid]
            let elapsedSeconds = max(convertMachToSeconds(nowAbs > lastSampleAbsTime ? nowAbs - lastSampleAbsTime : 0), 0.001)
            let networkRates = computeNetworkRates(previous: previousNetwork, current: currentNetwork, elapsed: elapsedSeconds)
            if currentNetwork == nil {
                flags.insert(.networkUnavailable)
            }

            let diskRates = computeDiskRates(previous: cache?.lastRusage, current: rusage, elapsed: elapsedSeconds)

            let processInfo = ProcessInfo(
                pid: pid,
                parentPid: parentPid,
                name: name,
                commandLine: command,
                username: username,
                cpuInstantPercent: cpuPercent,
                cpuCumulativePercent: cumulativePercent,
                residentBytes: residentBytes,
                memoryPercent: memoryPercent,
                threadCount: threadCount,
                networkInBytesPerSecond: networkRates.download,
                networkOutBytesPerSecond: networkRates.upload,
                diskReadBytesPerSecond: diskRates.read,
                diskWriteBytesPerSecond: diskRates.write,
                logicalWriteBytesPerSecond: diskRates.logical,
                flags: flags
            )
            processes.append(processInfo)

            cachedProcesses[pid] = CachedProcess(
                lastTotalCPUTime: totalCPUTime,
                lastSampleAbsTime: nowAbs,
                lastRusage: rusage,
                commandLine: command,
                username: username,
                networkSnapshot: currentNetwork,
                cpuCumulativeFallback: cumulativePercent,
                lastResidentBytes: residentBytes,
                lastThreadCount: threadCount,
                cpuInstantFallback: cpuPercent
            )
        }

        cachedProcesses = cachedProcesses.filter { currentPIDs.contains($0.key) }
        return processes
    }

    private func computeCumulativeCPUPercent(totalCPUTime: UInt64, startTime: UInt64, currentAbs: UInt64) -> Double {
        let elapsedAbs = currentAbs > startTime ? currentAbs - startTime : 0
        let elapsedSeconds = convertMachToSeconds(elapsedAbs)
        guard elapsedSeconds > 0 else { return 0 }
        let cpuSeconds = Double(totalCPUTime) / 1_000_000_000.0
        return (cpuSeconds / elapsedSeconds) * 100.0
    }

    private func computeDiskRates(previous: rusage_info_v6?, current: rusage_info_v6, elapsed: Double) -> (read: Double, write: Double, logical: Double) {
        guard elapsed > 0 else { return (0, 0, 0) }
        if let previous = previous {
            let readDelta = current.ri_diskio_bytesread >= previous.ri_diskio_bytesread ? current.ri_diskio_bytesread - previous.ri_diskio_bytesread : 0
            let writeDelta = current.ri_diskio_byteswritten >= previous.ri_diskio_byteswritten ? current.ri_diskio_byteswritten - previous.ri_diskio_byteswritten : 0
            let logicalDelta = current.ri_logical_writes >= previous.ri_logical_writes ? current.ri_logical_writes - previous.ri_logical_writes : 0
            return (Double(readDelta) / elapsed, Double(writeDelta) / elapsed, Double(logicalDelta) / elapsed)
        }
        return (0, 0, 0)
    }

    private func computeNetworkRates(previous: (UInt64, UInt64)?, current: (UInt64, UInt64)?, elapsed: Double) -> (download: Double, upload: Double) {
        guard elapsed > 0 else { return (0, 0) }
        guard let current = current else { return (0, 0) }
        guard let previous = previous else { return (0, 0) }
        let inDelta = current.0 >= previous.0 ? current.0 - previous.0 : 0
        let outDelta = current.1 >= previous.1 ? current.1 - previous.1 : 0
        return (Double(inDelta) / elapsed, Double(outDelta) / elapsed)
    }

    private func fetchKinfoProcBuffer() -> UnsafeMutableRawPointer? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length: Int = 0
        let nameCount = UInt32(mib.count)
        let queryStatus = mib.withUnsafeMutableBufferPointer { ptr -> Int32 in
            return sysctl(ptr.baseAddress, nameCount, nil, &length, nil, 0)
        }
        if queryStatus != 0 {
            return nil
        }

        if processListBuffer == nil || processListCapacity < length {
            allocateProcessBuffer(bytes: length)
        }

        var mutableLength = length
        let status = mib.withUnsafeMutableBufferPointer { ptr -> Int32 in
            return sysctl(ptr.baseAddress, nameCount, processListBuffer, &mutableLength, nil, 0)
        }

        if status != 0 {
            return nil
        }

        processListLength = mutableLength
        return processListBuffer
    }

    private func captureHostDeltaSeconds() -> Double? {
        guard let metrics = currentHostTickTotals() else {
            return nil
        }
        let currentTotal = metrics.total
        let coreCount = metrics.cpuCount > 0 ? metrics.cpuCount : cpuCoreCount
        defer {
            previousHostTotalTicks = currentTotal
            previousHostCPUCount = coreCount
        }
        guard let previous = previousHostTotalTicks, currentTotal >= previous else {
            return nil
        }
        let deltaTicks = currentTotal - previous
        if deltaTicks == 0 {
            return nil
        }
        return Double(deltaTicks) / (clkTck * Double(coreCount))
    }

    private func currentHostTickTotals() -> (total: UInt64, cpuCount: Int)? {
        var cpuCount: natural_t = 0
        var infoPtr: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoPtr, &infoCount)
        guard result == KERN_SUCCESS, let infoPtr = infoPtr else {
            return nil
        }
        defer {
            let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoPtr), size)
        }

        var totalTicks: UInt64 = 0
        infoPtr.withMemoryRebound(to: processor_cpu_load_info_data_t.self, capacity: Int(cpuCount)) { pointer in
            for index in 0..<Int(cpuCount) {
                let info = pointer[index]
                totalTicks += UInt64(info.cpu_ticks.0)
                totalTicks += UInt64(info.cpu_ticks.1)
                totalTicks += UInt64(info.cpu_ticks.2)
                totalTicks += UInt64(info.cpu_ticks.3)
            }
        }

        return (totalTicks, Int(cpuCount))
    }

    private func allocateProcessBuffer(bytes: Int) {
        if let buffer = processListBuffer {
            buffer.deallocate()
        }
        let alignment = max(MemoryLayout<kinfo_proc>.alignment, MemoryLayout<Int>.alignment)
        processListBuffer = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: alignment)
        processListCapacity = bytes
        processListLength = bytes
    }

    private func resolveCommandLine(pid: Int32) -> String {
        if let cached = cachedProcesses[pid]?.commandLine, !cached.isEmpty {
            return cached
        }
        guard let buffer = fetchCommandBuffer(pid: pid) else {
            return resolveExecutablePath(pid: pid)
        }
        return parseCommandLineBuffer(buffer) ?? resolveExecutablePath(pid: pid)
    }

    private func fetchCommandBuffer(pid: Int32) -> [CChar]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var length: Int = 0
        let nameCount = UInt32(mib.count)
        let queryStatus = mib.withUnsafeMutableBufferPointer { ptr -> Int32 in
            return sysctl(ptr.baseAddress, nameCount, nil, &length, nil, 0)
        }
        if queryStatus != 0 {
            length = commandBufferSize
        }
        var buffer = [CChar](repeating: 0, count: max(length, commandBufferSize))
        var mutableLength = buffer.count
        let status = mib.withUnsafeMutableBufferPointer { ptr -> Int32 in
            return buffer.withUnsafeMutableBufferPointer { bufPtr -> Int32 in
                var size = mutableLength
                let result = sysctl(ptr.baseAddress, nameCount, bufPtr.baseAddress, &size, nil, 0)
                mutableLength = size
                return result
            }
        }
        guard status == 0 else { return nil }
        let limit = min(mutableLength, buffer.count - 1)
        if limit >= 0 && limit < buffer.count {
            buffer[limit] = 0
        } else if buffer.count > 0 {
            buffer[buffer.count - 1] = 0
        }
        return buffer
    }

    private func parseCommandLineBuffer(_ buffer: [CChar]) -> String? {
        return buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return nil }
            let length = ptr.count
            if length <= MemoryLayout<Int32>.size { return nil }
            let argc = base.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
            if argc <= 0 { return nil }
            var strings: [String] = []
            var cursor = base.advanced(by: MemoryLayout<Int32>.size)
            let end = base.advanced(by: length)
            while cursor < end && strings.count < Int(argc) {
                let currentString = String(cString: cursor)
                if currentString.isEmpty {
                    cursor = cursor.advanced(by: 1)
                    continue
                }
                strings.append(currentString)
                cursor = cursor.advanced(by: currentString.utf8.count + 1)
            }
            if strings.isEmpty {
                return nil
            }
            return strings.joined(separator: " ")
        }
    }

    private func resolveExecutablePath(pid: Int32) -> String {
        let pathSize = max(Int(MAXPATHLEN) * 4, 1024)
        var pathBuffer = [CChar](repeating: 0, count: pathSize)
        let result = pathBuffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            return proc_pidpath(pid, pointer.baseAddress, UInt32(pointer.count))
        }
        if result > 0 {
            return String(cString: pathBuffer)
        }
        return "<unknown>"
    }

    private func resolveUsername(uid: uid_t, pid: Int32) -> String {
        if let cached = cachedProcesses[pid]?.username, !cached.isEmpty {
            return cached
        }
        var pwd = passwd()
        var resultPtr: UnsafeMutablePointer<passwd>? = nil
        var buffer = [CChar](repeating: 0, count: usernameBufferSize)
        let status = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            return getpwuid_r(uid, &pwd, ptr.baseAddress, ptr.count, &resultPtr)
        }
        if status == 0, let namePtr = resultPtr?.pointee.pw_name {
            return String(cString: namePtr)
        }
        return String(uid)
    }

    private func updateNetworkTotalsIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastNetworkSample) >= networkSampleInterval else { return }
        lastNetworkSample = now
        let process = Process()
        process.launchPath = "/usr/bin/nettop"
        process.arguments = ["-P", "-n", "-x", "-J", "pid,bytes_in,bytes_out", "-L", "1"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return }
            networkTotals = parseNettop(output: output)
        } catch {
            return
        }
    }

    private func parseNettop(output: String) -> [Int32: (UInt64, UInt64)] {
        var totals: [Int32: (UInt64, UInt64)] = [:]
        let lines = output.split(whereSeparator: { $0.isNewline })
        guard let header = lines.first else { return totals }
        let columns = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard
            let pidIndex = columns.firstIndex(of: "pid"),
            let inIndex = columns.firstIndex(of: "bytes_in"),
            let outIndex = columns.firstIndex(of: "bytes_out")
        else {
            return totals
        }
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            let values = line.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            if values.count <= max(pidIndex, max(inIndex, outIndex)) { continue }
            guard let pid = Int32(values[pidIndex]),
                  let bytesIn = UInt64(values[inIndex]),
                  let bytesOut = UInt64(values[outIndex]) else { continue }
            totals[pid] = (bytesIn, bytesOut)
        }
        return totals
    }

    private func convertMachToSeconds(_ value: UInt64) -> Double {
        let numer = Double(timebaseInfo.numer)
        let denom = Double(timebaseInfo.denom)
        let nanoseconds = Double(value) * (numer / denom)
        return nanoseconds / 1_000_000_000.0
    }
}
