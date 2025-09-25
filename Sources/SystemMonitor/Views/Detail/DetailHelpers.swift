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

enum DetailHelpers {
    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM • HH:mm:ss"
        return formatter
    }()

    static func formatPercent(fromRatio value: Double, decimals: Int = 0) -> String {
        let clamped = max(0, min(value, 1)) * 100
        let format = "%.\(decimals)f"
        let formatted = String(format: format, clamped)
        return "\(formatted)%"
    }

    static func formatByteSpeed(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var speed = bytesPerSecond
        var unitIndex = 0

        while speed > 1024 && unitIndex < units.count - 1 {
            speed /= 1024
            unitIndex += 1
        }

        return String(format: "%.1f %@", speed, units[unitIndex])
    }

    static func formatBytesPerSecond(_ bytes: Double) -> String {
        guard bytes > 0 else { return "0 B/s" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var value = bytes
        var unitIndex = 0
        while value >= 1024.0 && unitIndex < units.count - 1 {
            value /= 1024.0
            unitIndex += 1
        }
        if unitIndex == 0 {
            return String(format: "%.0f %@", value, units[unitIndex])
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    static func networkBarValue(for value: Double) -> Double {
        guard value > 0 else { return 0 }
        let minLog = log10(1.0)
        let maxLog = log10(50_000_000.0)
        let current = log10(max(value, 1.0))
        let normalized = (current - minLog) / (maxLog - minLog)
        return min(max(normalized, 0), 1)
    }

    static func truncatedProcessName(_ name: String, limit: Int = 18) -> String {
        guard name.count > limit else { return name }
        let endIndex = name.index(name.startIndex, offsetBy: limit - 1)
        return "\(name[..<endIndex])…"
    }

    static func loadAverages() -> (Double, Double, Double)? {
        var loads = [Double](repeating: 0, count: 3)
        let result = loads.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return getloadavg(baseAddress, 3)
        }
        guard result == 3 else { return nil }
        return (loads[0], loads[1], loads[2])
    }
}
