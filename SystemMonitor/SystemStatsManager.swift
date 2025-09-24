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
import SwiftUI

class SystemStatsManager: ObservableObject {
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsage: Double = 0.0
    @Published var networkIn: Double = 0.0
    @Published var networkOut: Double = 0.0
    @Published var totalMemory: Double = 0.0
    @Published var usedMemory: Double = 0.0
    @Published var freeMemory: Double = 0.0
    @Published var cpuHistory: [HistoryPoint] = []
    @Published var memoryHistory: [HistoryPoint] = []
    
    private var updateTimer: Timer?
    private var previousNetworkStats: (inBytes: UInt64, outBytes: UInt64)?
    private var lastUpdateTime: Date?
    
    init() {
        updateSystemStats()
        startUpdating()
    }
    
    func startUpdating() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateSystemStats()
        }
    }
    
    func stopUpdating() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func updateSystemStats() {
        DispatchQueue.global(qos: .background).async {
            let cpu = self.getCPUUsage()
            let memory = self.getMemoryUsage()
            let network = self.getNetworkUsage()
            
            DispatchQueue.main.async {
                self.cpuUsage = cpu
                self.memoryUsage = memory.usage
                self.totalMemory = memory.total
                self.usedMemory = memory.used
                self.freeMemory = memory.free
                self.networkIn = network.inSpeed
                self.networkOut = network.outSpeed
                
                // Update history
                let now = Date()
                self.cpuHistory.append(HistoryPoint(time: now, value: cpu))
                self.memoryHistory.append(HistoryPoint(time: now, value: memory.usage))
                
                // Keep only last 60 points (1 minute of data)
                if self.cpuHistory.count > 60 {
                    self.cpuHistory.removeFirst()
                }
                if self.memoryHistory.count > 60 {
                    self.memoryHistory.removeFirst()
                }
            }
        }
    }
    
    private func getCPUUsage() -> Double {
        var kr: kern_return_t
        var cpuCount: mach_msg_type_number_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUs: natural_t = 0
        
        let port = mach_host_self()
        
        // Get number of CPUs
        kr = host_processor_info(port, PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &cpuCount)
        
        if kr != KERN_SUCCESS {
            return 0.0
        }
        
        var totalUsage: Double = 0.0
        
        if let cpuInfo = cpuInfo {
            for i in 0..<Int(numCPUs) {
                let user = Double(cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_USER)])
                let system = Double(cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_SYSTEM)])
                let idle = Double(cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_IDLE)])
                let nice = Double(cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_NICE)])
                
                let totalTicks = user + system + idle + nice
                if totalTicks > 0 {
                    let usage = ((user + system + nice) / totalTicks) * 100.0
                    totalUsage += usage
                }
            }
            
            let infoSize = vm_size_t(numCPUs * UInt32(CPU_STATE_MAX) * UInt32(MemoryLayout<integer_t>.size))
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), infoSize)
        }
        
        return totalUsage / Double(numCPUs)
    }
    
    private func getMemoryUsage() -> (usage: Double, total: Double, used: Double, free: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size) / (1024.0 * 1024.0 * 1024.0) // Convert to GB
            let totalMemory = Double(getTotalMemory()) / (1024.0 * 1024.0 * 1024.0) // Convert to GB
            let freeMemory = totalMemory - usedMemory
            let usagePercentage = (usedMemory / totalMemory) * 100.0
            
            return (usage: usagePercentage, total: totalMemory, used: usedMemory, free: freeMemory)
        }
        
        return (usage: 0.0, total: 0.0, used: 0.0, free: 0.0)
    }
    
    private func getTotalMemory() -> UInt64 {
        return ProcessInfo.processInfo.physicalMemory
    }
    
    private func getNetworkUsage() -> (inSpeed: Double, outSpeed: Double) {
        var inSpeed: Double = 0.0
        var outSpeed: Double = 0.0
        
        let currentTime = Date()
        
        // Get network statistics
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        var totalInBytes: UInt64 = 0
        var totalOutBytes: UInt64 = 0
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                if let interface = ptr?.pointee {
                    let name = String(cString: interface.ifa_name)
                    if name.hasPrefix("en") || name.hasPrefix("eth") { // Ethernet interfaces
                        if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                            totalInBytes += UInt64(data.pointee.ifi_ibytes)
                            totalOutBytes += UInt64(data.pointee.ifi_obytes)
                        }
                    }
                }
                ptr = ptr?.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        
        if let previousStats = previousNetworkStats, let lastTime = lastUpdateTime {
            let timeInterval = currentTime.timeIntervalSince(lastTime)
            if timeInterval > 0 {
                let inBytesDiff = Double(totalInBytes - previousStats.inBytes)
                let outBytesDiff = Double(totalOutBytes - previousStats.outBytes)
                
                inSpeed = (inBytesDiff / timeInterval) / 1024.0 // KB/s
                outSpeed = (outBytesDiff / timeInterval) / 1024.0 // KB/s
            }
        }
        
        previousNetworkStats = (totalInBytes, totalOutBytes)
        lastUpdateTime = currentTime
        
        return (inSpeed: max(0, inSpeed), outSpeed: max(0, outSpeed))
    }
}