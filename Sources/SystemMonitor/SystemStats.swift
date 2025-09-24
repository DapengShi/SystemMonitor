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

// MARK: - Process Information

struct ProcessInfo: Identifiable {
    let pid: Int32
    let parentPid: Int32
    let name: String
    let cpuUsage: Double
    let memoryUsage: Double
    let networkInBytesPerSecond: Double
    let networkOutBytesPerSecond: Double
    let diskReadBytesPerSecond: Double
    let diskWriteBytesPerSecond: Double
    
    // Conform to Identifiable protocol
    var id: Int32 { pid }
    
    var isHighCPU: Bool {
        return cpuUsage > 80.0 // CPU usage threshold: 80%
    }
    
    var isHighMemory: Bool {
        return memoryUsage > 10.0 // Memory usage threshold: 10%
    }
    
    var isAbnormal: Bool {
        return isHighCPU || isHighMemory
    }
}

// MARK: - System Statistics

class SystemStats {
    // Previous CPU ticks for calculating usage over time
    private var previousCPUTicks: (user: Double, system: Double, idle: Double, nice: Double) = (0, 0, 0, 0)
    
    // Previous network counters for calculating speed
    private var previousBytesIn: UInt64 = 0
    private var previousBytesOut: UInt64 = 0
    private var lastNetworkCheckTime: Date = Date()
    
    // Per-process IO state for delta calculations
    private var previousProcessDiskIO: [Int32: (read: UInt64, write: UInt64, timestamp: Date)] = [:]
    private var previousProcessNetworkIO: [Int32: (bytesIn: UInt64, bytesOut: UInt64, timestamp: Date)] = [:]
    private let processMetricsQueue = DispatchQueue(label: "com.systemmonitor.processMetrics")
    
    // MARK: - CPU Usage
    
    func getCPUUsage() -> Double {
        var cpuInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        if result != KERN_SUCCESS {
            print("Error getting CPU usage")
            return 0.0
        }
        
        // Get current ticks
        let userTicks = Double(cpuInfo.cpu_ticks.0)
        let systemTicks = Double(cpuInfo.cpu_ticks.1)
        let idleTicks = Double(cpuInfo.cpu_ticks.2)
        let niceTicks = Double(cpuInfo.cpu_ticks.3)
        
        // Calculate difference from previous measurement
        let userDiff = userTicks - previousCPUTicks.user
        let systemDiff = systemTicks - previousCPUTicks.system
        let idleDiff = idleTicks - previousCPUTicks.idle
        let niceDiff = niceTicks - previousCPUTicks.nice
        
        // Store current values for next calculation
        previousCPUTicks = (userTicks, systemTicks, idleTicks, niceTicks)
        
        // Calculate CPU usage percentage based on tick differences
        let totalTicks = userDiff + systemDiff + idleDiff + niceDiff
        if totalTicks <= 0 {
            return 0.0
        }
        
        let usedTicks = userDiff + systemDiff + niceDiff
        return usedTicks / totalTicks
    }
    
    // MARK: - Memory Usage
    
    func getMemoryUsage() -> Double {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        if result != KERN_SUCCESS {
            print("Error getting memory usage")
            return 0.0
        }
        
        // Get total physical memory
        var totalMemory: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0)
        
        // Calculate used memory more accurately
        let pageSize = vm_kernel_page_size
        let activeMemory = UInt64(stats.active_count) * UInt64(pageSize)
        let wiredMemory = UInt64(stats.wire_count) * UInt64(pageSize)
        let inactiveMemory = UInt64(stats.inactive_count) * UInt64(pageSize)
        
        // Total used memory
        let usedMemory = activeMemory + wiredMemory + inactiveMemory
        
        // Return as a ratio (0.0 to 1.0)
        return Double(usedMemory) / Double(totalMemory)
    }
    
    // MARK: - Network Usage
    
    func getNetworkStats() -> (uploadSpeed: Double, downloadSpeed: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0

        // Get network interfaces
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                let interface = ptr?.pointee
                let name = String(cString: (interface?.ifa_name)!)
                let flags = Int32((interface?.ifa_flags)!)
                
                // Filter out loopback and inactive interfaces
                if (flags & IFF_UP) == IFF_UP && (flags & IFF_LOOPBACK) != IFF_LOOPBACK && (flags & IFF_RUNNING) == IFF_RUNNING {
                    if let addr = interface?.ifa_data {
                        if name.hasPrefix("en") || name.hasPrefix("wl") || name.hasPrefix("pdp_ip") || name.hasPrefix("utun") {
                            let networkData = addr.assumingMemoryBound(to: if_data.self)
                            bytesIn += UInt64(networkData.pointee.ifi_ibytes)
                            bytesOut += UInt64(networkData.pointee.ifi_obytes)
                        }
                    }
                }
            }
            
            freeifaddrs(ifaddr)
        }
        
        // Calculate speeds
        let now = Date()
        let timeDiff = now.timeIntervalSince(lastNetworkCheckTime)
        
        let uploadSpeed = timeDiff > 0 ? Double(bytesOut - previousBytesOut) / timeDiff : 0
        let downloadSpeed = timeDiff > 0 ? Double(bytesIn - previousBytesIn) / timeDiff : 0
        
        // Store current values for next calculation
        previousBytesIn = bytesIn
        previousBytesOut = bytesOut
        lastNetworkCheckTime = now
        
        return (uploadSpeed, downloadSpeed)
    }
    
    // MARK: - Process IO Helpers
    
    private func diskIORates(for pid: Int32, now: Date) -> (read: Double, write: Double) {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                proc_pid_rusage(Int32(pid), RUSAGE_INFO_V2, reboundPtr)
            }
        }
        guard result == 0 else {
            return (0.0, 0.0)
        }
        let currentRead = info.ri_diskio_bytesread
        let currentWrite = info.ri_diskio_byteswritten
        let previous = previousProcessDiskIO[pid]
        previousProcessDiskIO[pid] = (currentRead, currentWrite, now)
        guard let previous = previous else {
            return (0.0, 0.0)
        }
        let elapsed = now.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else {
            return (0.0, 0.0)
        }
        let readDelta = currentRead >= previous.read ? currentRead - previous.read : 0
        let writeDelta = currentWrite >= previous.write ? currentWrite - previous.write : 0
        return (Double(readDelta) / elapsed, Double(writeDelta) / elapsed)
    }
    
    private func fetchNetworkUsageByPid() -> [Int32: (UInt64, UInt64)] {
        var usage: [Int32: (UInt64, UInt64)] = [:]
        let task = Process()
        task.launchPath = "/usr/bin/nettop"
        task.arguments = ["-P", "-n", "-x", "-J", "pid,bytes_in,bytes_out", "-L", "1"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return usage
        }
        guard task.terminationStatus == 0 else {
            return usage
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return usage
        }
        let lines = output.split(whereSeparator: { $0.isNewline })
        guard let headerLine = lines.first else {
            return usage
        }
        let headers = headerLine.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard
            let pidIndex = headers.firstIndex(of: "pid"),
            let inIndex = headers.firstIndex(of: "bytes_in"),
            let outIndex = headers.firstIndex(of: "bytes_out")
        else {
            return usage
        }
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            let values = line.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            if values.count <= max(pidIndex, max(inIndex, outIndex)) {
                continue
            }
            guard let pidValue = Int32(values[pidIndex]),
                  let bytesInValue = UInt64(values[inIndex]),
                  let bytesOutValue = UInt64(values[outIndex]) else {
                continue
            }
            let existing = usage[pidValue] ?? (0, 0)
            usage[pidValue] = (existing.0 + bytesInValue, existing.1 + bytesOutValue)
        }
        return usage
    }
    
    private func networkRates(for pid: Int32, totals: (UInt64, UInt64)?, now: Date) -> (download: Double, upload: Double) {
        guard let totals = totals else {
            previousProcessNetworkIO.removeValue(forKey: pid)
            return (0.0, 0.0)
        }
        let previous = previousProcessNetworkIO[pid]
        previousProcessNetworkIO[pid] = (totals.0, totals.1, now)
        guard let previous = previous else {
            return (0.0, 0.0)
        }
        let elapsed = now.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else {
            return (0.0, 0.0)
        }
        let inDelta = totals.0 >= previous.bytesIn ? totals.0 - previous.bytesIn : 0
        let outDelta = totals.1 >= previous.bytesOut ? totals.1 - previous.bytesOut : 0
        return (Double(inDelta) / elapsed, Double(outDelta) / elapsed)
    }
    
    // MARK: - Process Monitoring
    
    func getTopProcesses(limit: Int = 10) -> [ProcessInfo] {
        return processMetricsQueue.sync {
            var processes = [ProcessInfo]()
            let now = Date()
            let networkTotals = fetchNetworkUsageByPid()
            
            let task = Process()
            task.launchPath = "/bin/ps"
            task.arguments = ["-axro", "%cpu,%mem,pid,ppid,comm", "-c"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.components(separatedBy: "\n")
                    var collected = 0
                    
                    for line in lines {
                        if line.isEmpty || line.hasPrefix("%CPU") {
                            continue
                        }
                        
                        if limit > 0 && collected >= limit {
                            break
                        }
                        
                        let components = line.split(separator: " ").filter { !$0.isEmpty }
                        if components.count >= 5,
                           let cpuUsage = Double(components[0]),
                           let memUsage = Double(components[1]),
                           let pid = Int32(components[2]),
                           let parentPid = Int32(components[3]) {
                            let name = components[4...].joined(separator: " ")
                            let diskRates = diskIORates(for: pid, now: now)
                            let networkRates = networkRates(for: pid, totals: networkTotals[pid], now: now)

                            let process = ProcessInfo(
                                pid: pid,
                                parentPid: parentPid,
                                name: name,
                                cpuUsage: cpuUsage,
                                memoryUsage: memUsage,
                                networkInBytesPerSecond: networkRates.download,
                                networkOutBytesPerSecond: networkRates.upload,
                                diskReadBytesPerSecond: diskRates.read,
                                diskWriteBytesPerSecond: diskRates.write
                            )
                            
                            processes.append(process)
                            collected += 1
                        }
                    }
                }
            } catch {
                print("Error getting process information: \(error)")
            }
            
            let activePids = Set(processes.map { $0.pid })
            previousProcessDiskIO = previousProcessDiskIO.filter { activePids.contains($0.key) }
            previousProcessNetworkIO = previousProcessNetworkIO.filter { activePids.contains($0.key) }
            
            return processes
        }
    }
    
    // MARK: - Formatting Utilities
    
    func formatByteSpeed(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var speed = bytesPerSecond
        var unitIndex = 0
        
        while speed > 1024 && unitIndex < units.count - 1 {
            speed /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", speed, units[unitIndex])
    }
    
    func formatByteSpeedShort(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G"]
        var speed = bytesPerSecond
        var unitIndex = 0
        
        while speed > 1024 && unitIndex < units.count - 1 {
            speed /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f%@", speed, units[unitIndex])
    }
}
