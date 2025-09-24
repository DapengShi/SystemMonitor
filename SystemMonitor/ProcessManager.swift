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
import AppKit

struct ProcessInfo: Identifiable {
    let id = UUID()
    let pid: Int
    let name: String
    let cpu: Double
    let memory: Double
    let memoryMB: Double
    let ppid: Int
    let command: String
    let startTime: String
    let threads: Int
    let state: String
}

class ProcessManager: ObservableObject {
    @Published var processes: [ProcessInfo] = []
    @Published var selectedProcess: ProcessInfo?
    @Published var isLoading = false
    
    private var updateTimer: Timer?
    
    init() {
        updateProcesses()
        startUpdating()
    }
    
    func startUpdating() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.updateProcesses()
        }
    }
    
    func stopUpdating() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    func updateProcesses() {
        DispatchQueue.global(qos: .background).async {
            let newProcesses = self.getProcessList()
            DispatchQueue.main.async {
                self.processes = newProcesses
            }
        }
    }
    
    private func getProcessList() -> [ProcessInfo] {
        var processes: [ProcessInfo] = []
        
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["aux"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                
                for (index, line) in lines.enumerated() {
                    if index == 0 { continue } // Skip header
                    
                    let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if components.count >= 11 {
                        let pid = Int(components[1]) ?? 0
                        let cpu = Double(components[2]) ?? 0.0
                        let memory = Double(components[3]) ?? 0.0
                        let memoryMB = Double(components[5]) ?? 0.0
                        let ppid = Int(components[2]) ?? 0
                        let startTime = components[8]
                        let command = components.dropFirst(10).joined(separator: " ")
                        let name = (command as NSString).lastPathComponent
                        
                        let process = ProcessInfo(
                            pid: pid,
                            name: name.isEmpty ? components[10] : name,
                            cpu: cpu,
                            memory: memory,
                            memoryMB: memoryMB,
                            ppid: ppid,
                            command: command,
                            startTime: startTime,
                            threads: 1,
                            state: "Running"
                        )
                        processes.append(process)
                    }
                }
            }
        } catch {
            print("Error getting process list: \(error)")
        }
        
        return processes.sorted { $0.cpu > $1.cpu }
    }
    
    func getProcessTree(pid: Int) -> (parent: ProcessInfo?, children: [ProcessInfo]) {
        let children = processes.filter { $0.ppid == pid }
        let parent = processes.first { $0.pid == processes.first(where: { $0.pid == pid })?.ppid }
        return (parent, children)
    }
    
    func killProcess(pid: Int, includeFamily: Bool = false) -> Bool {
        var pidsToKill: [Int] = [pid]
        
        if includeFamily {
            // Add parent process
            if let parent = processes.first(where: { $0.pid == processes.first(where: { $0.pid == pid })?.ppid }) {
                pidsToKill.append(parent.pid)
            }
            
            // Add all children processes
            let children = processes.filter { $0.ppid == pid }
            pidsToKill.append(contentsOf: children.map { $0.pid })
        }
        
        var success = true
        for pidToKill in pidsToKill {
            let task = Process()
            task.launchPath = "/bin/kill"
            task.arguments = ["-9", "\(pidToKill)"]
            
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    success = false
                }
            } catch {
                success = false
                print("Error killing process \(pidToKill): \(error)")
            }
        }
        
        if success {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.updateProcesses()
            }
        }
        
        return success
    }
    
    func killProcessFamily(pid: Int) -> Bool {
        return killProcess(pid: pid, includeFamily: true)
    }
}