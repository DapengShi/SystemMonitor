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

final class SystemStats {
    private var previousCPUTicks: (user: Double, system: Double, idle: Double, nice: Double) = (0, 0, 0, 0)
    private var previousBytesIn: UInt64 = 0
    private var previousBytesOut: UInt64 = 0
    private var lastNetworkCheckTime: Date = Date()
    private let processCollector = ProcessCollector()

    func getCPUUsage() -> Double {
        var cpuInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        if result != KERN_SUCCESS {
            return 0.0
        }

        let userTicks = Double(cpuInfo.cpu_ticks.0)
        let systemTicks = Double(cpuInfo.cpu_ticks.1)
        let idleTicks = Double(cpuInfo.cpu_ticks.2)
        let niceTicks = Double(cpuInfo.cpu_ticks.3)

        let userDiff = userTicks - previousCPUTicks.user
        let systemDiff = systemTicks - previousCPUTicks.system
        let idleDiff = idleTicks - previousCPUTicks.idle
        let niceDiff = niceTicks - previousCPUTicks.nice

        previousCPUTicks = (userTicks, systemTicks, idleTicks, niceTicks)

        let totalTicks = userDiff + systemDiff + idleDiff + niceDiff
        guard totalTicks > 0 else { return 0.0 }

        let usedTicks = userDiff + systemDiff + niceDiff
        return usedTicks / totalTicks
    }

    func getMemoryUsage() -> Double {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if result != KERN_SUCCESS {
            return 0.0
        }

        var totalMemory: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0)

        let pageSize = vm_kernel_page_size
        let activeMemory = UInt64(stats.active_count) * UInt64(pageSize)
        let wiredMemory = UInt64(stats.wire_count) * UInt64(pageSize)
        let inactiveMemory = UInt64(stats.inactive_count) * UInt64(pageSize)

        let usedMemory = activeMemory + wiredMemory + inactiveMemory
        return Double(usedMemory) / Double(totalMemory)
    }

    func getNetworkStats() -> (uploadSpeed: Double, downloadSpeed: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0

        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr

            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }

                guard let interface = ptr?.pointee else { continue }
                let name = String(cString: interface.ifa_name)
                let flags = Int32(interface.ifa_flags)

                if (flags & IFF_UP) == IFF_UP && (flags & IFF_LOOPBACK) != IFF_LOOPBACK && (flags & IFF_RUNNING) == IFF_RUNNING {
                    if let addr = interface.ifa_data {
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

        let now = Date()
        let timeDiff = now.timeIntervalSince(lastNetworkCheckTime)
        let uploadSpeed = timeDiff > 0 ? Double(bytesOut - previousBytesOut) / timeDiff : 0
        let downloadSpeed = timeDiff > 0 ? Double(bytesIn - previousBytesIn) / timeDiff : 0

        previousBytesIn = bytesIn
        previousBytesOut = bytesOut
        lastNetworkCheckTime = now

        return (uploadSpeed, downloadSpeed)
    }

    func getTopProcesses(limit: Int = 0) -> [ProcessInfo] {
        let processes = processCollector.snapshotProcesses(limit: 0)
        guard limit > 0 else {
            return processes
        }
        let sorted = processes.sorted { lhs, rhs in
            if lhs.cpuInstantPercent == rhs.cpuInstantPercent {
                return lhs.memoryPercent > rhs.memoryPercent
            }
            return lhs.cpuInstantPercent > rhs.cpuInstantPercent
        }
        return Array(sorted.prefix(limit))
    }

    func formatByteSpeed(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var speed = bytesPerSecond
        var unitIndex = 0

        while speed >= 1024.0 && unitIndex < units.count - 1 {
            speed /= 1024.0
            unitIndex += 1
        }

        let format = unitIndex == 0 ? "%.0f %@" : "%.1f %@"
        return String(format: format, speed, units[unitIndex])
    }

    func formatByteSpeedShort(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var speed = bytesPerSecond
        var unitIndex = 0

        while speed >= 1024.0 && unitIndex < units.count - 1 {
            speed /= 1024.0
            unitIndex += 1
        }

        let format = unitIndex == 0 ? "%.0f%@" : "%.1f%@"
        return String(format: format, speed, units[unitIndex])
    }
}
