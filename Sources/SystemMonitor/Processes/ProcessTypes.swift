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

/// Flags describing partial or restricted process metrics.
struct ProcessFlags: OptionSet {
    let rawValue: Int

    static let cpuRestricted = ProcessFlags(rawValue: 1 << 0)
    static let networkUnavailable = ProcessFlags(rawValue: 1 << 1)
    static let permissionDenied = ProcessFlags(rawValue: 1 << 2)
}

/// Host-level metrics sampled alongside process data.
struct HostMetrics {
    let cpuUsage: Double
    let memoryUsage: Double
}

/// Model representing an individual process snapshot.
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

/// Cached per-PID state used to compute deltas between samples.
struct CachedProcess {
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

/// Convenience tuple-like structs returned by calculators.
struct DiskRates {
    let read: Double
    let write: Double
    let logical: Double
}

struct NetworkRates {
    let download: Double
    let upload: Double
}
