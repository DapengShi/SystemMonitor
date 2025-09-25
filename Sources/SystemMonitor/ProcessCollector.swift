// Copyright 2024 SystemMonitor Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Darwin

final class ProcessCollector {
    private let collectorQueue = DispatchQueue(label: "com.systemmonitor.process.collector", qos: .userInitiated)
    private var processEnumerator: any ProcessEnumeratorProtocol
    private var hostSampler: any HostCPUSamplerProtocol
    private var networkSampler: any NetworkUsageSamplerProtocol
    private var metricsCalculator: any ProcessMetricsCalculating
    private var cachedProcesses: [Int32: CachedProcess] = [:]
    private var networkTotals: [Int32: (UInt64, UInt64)] = [:]
    private let commandBufferSize = 8192
    private let usernameBufferSize = 256
    private let cpuCoreCount: Int
    private let totalMemoryBytes: UInt64
    private let clkTck: Double
    private let kernFScale: Double

    init(processEnumerator: ProcessEnumeratorProtocol = ProcessEnumerator(),
         hostSampler: HostCPUSamplerProtocol? = nil,
         networkSampler: NetworkUsageSamplerProtocol = NetworkUsageSampler(),
         metricsCalculator: ProcessMetricsCalculating? = nil) {
        self.processEnumerator = processEnumerator
        self.networkSampler = networkSampler

        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        self.metricsCalculator = metricsCalculator ?? ProcessMetricsCalculator(timebaseInfo: timebaseInfo)
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

        self.hostSampler = hostSampler ?? HostCPUSampler(clkTck: clkTck, fallbackCoreCount: cpuCoreCount)
    }

    func snapshotProcesses(limit: Int = 0) -> [ProcessInfo] {
        return collectorQueue.sync {
            let nowAbs = mach_absolute_time()
            let hostDeltaSeconds = hostSampler.deltaSeconds()
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
        return processEnumerator.withProcessList { pointer in
            networkTotals = networkSampler.sampleIfNeeded(reference: Date())

            var processes: [ProcessInfo] = []
            processes.reserveCapacity(pointer.count)
            var currentPIDs: Set<Int32> = []

            for index in 0..<pointer.count {
                var kproc = pointer[index]
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
                let cpuPercent = metricsCalculator.instantaneousCPUPercent(
                    totalCPUTime: totalCPUTime,
                    lastCPUTime: lastCPUTime,
                    hostDeltaSeconds: hostDeltaSeconds,
                    cpuCoreCount: cpuCoreCount,
                    kernFScale: kernFScale,
                    pctCPU: kproc.kp_proc.p_pctcpu,
                    fallbackInstant: cache?.cpuInstantFallback ?? 0.0,
                    hasTaskInfo: hasTaskInfo
                )
                let cumulativePercent = hasTaskInfo
                    ? metricsCalculator.cumulativeCPUPercent(totalCPUTime: totalCPUTime, startTime: rusage.ri_proc_start_abstime, currentAbs: nowAbs)
                    : (cache?.cpuCumulativeFallback ?? 0.0)

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
                let networkElapsed = nowAbs > lastSampleAbsTime ? nowAbs - lastSampleAbsTime : 0
                let elapsedSeconds = max(metricsCalculator.convertMachToSeconds(networkElapsed), 0.001)
                let networkRates = metricsCalculator.networkRates(previous: previousNetwork, current: currentNetwork, elapsed: elapsedSeconds)
                if currentNetwork == nil {
                    flags.insert(.networkUnavailable)
                }

                let diskRates = metricsCalculator.diskRates(previous: cache?.lastRusage, current: rusage, elapsed: elapsedSeconds)

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

}
