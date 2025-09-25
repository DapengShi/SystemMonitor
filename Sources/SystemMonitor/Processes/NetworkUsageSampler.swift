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

protocol NetworkUsageSamplerProtocol {
    func sampleIfNeeded(reference: Date) -> [Int32: (UInt64, UInt64)]
}

/// Wraps `nettop` execution and parsing to provide per-PID network totals.
final class NetworkUsageSampler: NetworkUsageSamplerProtocol {
    private let interval: TimeInterval
    private var lastSample: Date
    private var totals: [Int32: (UInt64, UInt64)] = [:]

    init(interval: TimeInterval = 5.0) {
        self.interval = interval
        self.lastSample = .distantPast
    }

    func sampleIfNeeded(reference: Date = Date()) -> [Int32: (UInt64, UInt64)] {
        guard reference.timeIntervalSince(lastSample) >= interval else {
            return totals
        }
        lastSample = reference
        totals = captureTotals() ?? totals
        return totals
    }

    private func captureTotals() -> [Int32: (UInt64, UInt64)]? {
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
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            return parse(output: output)
        } catch {
            return nil
        }
    }

    private func parse(output: String) -> [Int32: (UInt64, UInt64)] {
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
            guard
                let pid = Int32(values[pidIndex]),
                let bytesIn = UInt64(values[inIndex]),
                let bytesOut = UInt64(values[outIndex])
            else { continue }
            totals[pid] = (bytesIn, bytesOut)
        }
        return totals
    }
}
