import Foundation
import Darwin

protocol HostCPUSamplerProtocol {
    func deltaSeconds() -> Double?
}

/// Tracks host CPU tick deltas using `host_processor_info`.
final class HostCPUSampler: HostCPUSamplerProtocol {
    private let clkTck: Double
    private let fallbackCoreCount: Int
    private var previousHostTotalTicks: UInt64?
    private var previousHostCPUCount: Int

    init(clkTck: Double, fallbackCoreCount: Int) {
        self.clkTck = clkTck
        self.fallbackCoreCount = max(fallbackCoreCount, 1)
        self.previousHostCPUCount = max(fallbackCoreCount, 1)
    }

    func deltaSeconds() -> Double? {
        guard let metrics = currentHostTickTotals() else {
            return nil
        }
        let currentTotal = metrics.total
        let coreCount = metrics.cpuCount > 0 ? metrics.cpuCount : fallbackCoreCount
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
}
