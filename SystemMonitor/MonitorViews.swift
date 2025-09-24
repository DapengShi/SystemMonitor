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

import SwiftUI
import Charts

struct SystemStats {
    let cpuUsage: Double
    let memoryUsage: Double
    let networkIn: Double
    let networkOut: Double
    let totalMemory: Double
    let usedMemory: Double
    let freeMemory: Double
}

struct ProcessDetailView: View {
    let process: ProcessInfo
    @ObservedObject var processManager: ProcessManager
    @State private var showingKillAlert = false
    @State private var killFamily = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "app.badge")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text(process.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("PID: \(process.pid)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            
            Divider()
            
            // Process Info Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                InfoCard(title: "CPU Usage", value: "\(String(format: "%.1f", process.cpu))%", color: .orange)
                InfoCard(title: "Memory Usage", value: "\(String(format: "%.1f", process.memory))%", color: .blue)
                InfoCard(title: "Memory (MB)", value: "\(String(format: "%.0f", process.memoryMB))", color: .purple)
            }
            
            // Process Details
            VStack(alignment: .leading, spacing: 8) {
                Text("Process Details")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                DetailRow(label: "Parent PID", value: "\(process.ppid)")
                DetailRow(label: "Command", value: process.command)
                DetailRow(label: "Start Time", value: process.startTime)
                DetailRow(label: "Threads", value: "\(process.threads)")
                DetailRow(label: "State", value: process.state)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Process Tree
            if let parent = processManager.getProcessTree(pid: process.pid).parent,
               !processManager.getProcessTree(pid: process.pid).children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Process Tree")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    // Parent
                    if let parent = processManager.getProcessTree(pid: process.pid).parent {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.green)
                            Text("Parent: \(parent.name) (PID: \(parent.pid))")
                                .font(.subheadline)
                        }
                    }
                    
                    // Current process
                    HStack {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.blue)
                        Text("Current: \(process.name) (PID: \(process.pid))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    // Children
                    ForEach(processManager.getProcessTree(pid: process.pid).children, id: \.pid) { child in
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.orange)
                            Text("Child: \(child.name) (PID: \(child.pid))")
                                .font(.subheadline)
                        }
                        .padding(.leading, 20)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Action Buttons
            HStack {
                Button("Kill Process") {
                    killFamily = false
                    showingKillAlert = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
                Button("Kill Process Family") {
                    killFamily = true
                    showingKillAlert = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
        .alert("Confirm Kill", isPresented: $showingKillAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Kill", role: .destructive) {
                if killFamily {
                    processManager.killProcessFamily(pid: process.pid)
                } else {
                    processManager.killProcess(pid: process.pid)
                }
                dismiss()
            }
        } message: {
            if killFamily {
                Text("This will kill the process, its parent, and all its children. Are you sure?")
            } else {
                Text("This will kill the process. Are you sure?")
            }
        }
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
            
            Spacer()
        }
    }
}

struct ProcessListView: View {
    @ObservedObject var processManager: ProcessManager
    @State private var searchText = ""
    @State private var sortBy = "cpu"
    @State private var showingDetail = false
    
    var filteredProcesses: [ProcessInfo] {
        let filtered = searchText.isEmpty ? processManager.processes : processManager.processes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText)
        }
        
        switch sortBy {
        case "cpu":
            return filtered.sorted { $0.cpu > $1.cpu }
        case "memory":
            return filtered.sorted { $0.memory > $1.memory }
        case "name":
            return filtered.sorted { $0.name < $1.name }
        case "pid":
            return filtered.sorted { $0.pid < $1.pid }
        default:
            return filtered
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search and controls
            HStack {
                TextField("Search processes...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                
                Picker("Sort by", selection: $sortBy) {
                    Text("CPU").tag("cpu")
                    Text("Memory").tag("memory")
                    Text("Name").tag("name")
                    Text("PID").tag("pid")
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                
                Spacer()
                
                Button("Refresh") {
                    processManager.updateProcesses()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            // Process list header
            HStack {
                Text("PID").frame(width: 60, alignment: .leading)
                Text("Name").frame(width: 150, alignment: .leading)
                Text("CPU%").frame(width: 60, alignment: .trailing)
                Text("Mem%").frame(width: 60, alignment: .trailing)
                Text("Memory").frame(width: 80, alignment: .trailing)
                Text("Command").frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 100)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Process list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filteredProcesses, id: \.pid) { process in
                        ProcessRow(process: process, processManager: processManager)
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

struct ProcessRow: View {
    let process: ProcessInfo
    @ObservedObject var processManager: ProcessManager
    @State private var showingDetail = false
    
    var body: some View {
        HStack {
            Text("\(process.pid)").frame(width: 60, alignment: .leading)
            
            Text(process.name)
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)
            
            Text("\(String(format: "%.1f", process.cpu))%")
                .frame(width: 60, alignment: .trailing)
                .foregroundColor(process.cpu > 80 ? .red : .primary)
                .fontWeight(process.cpu > 80 ? .bold : .regular)
            
            Text("\(String(format: "%.1f", process.memory))%")
                .frame(width: 60, alignment: .trailing)
                .foregroundColor(process.memory > 10 ? .red : .primary)
                .fontWeight(process.memory > 10 ? .bold : .regular)
            
            Text("\(String(format: "%.0f", process.memoryMB)) MB")
                .frame(width: 80, alignment: .trailing)
            
            Text(process.command)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .font(.system(size: 11))
            
            HStack(spacing: 4) {
                Button("Detail") {
                    showingDetail = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Kill") {
                    processManager.killProcess(pid: process.pid)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }
            .frame(width: 100)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
        .padding(.horizontal)
        .sheet(isPresented: $showingDetail) {
            ProcessDetailView(process: process, processManager: processManager)
        }
    }
}

struct SystemMonitorView: View {
    @ObservedObject var systemStats: SystemStatsManager
    @ObservedObject var processManager: ProcessManager
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // System stats header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(.orange)
                        Text("CPU: \(String(format: "%.1f", systemStats.cpuUsage))%")
                            .font(.headline)
                    }
                    
                    HStack {
                        Image(systemName: "memorychip")
                            .foregroundColor(.blue)
                        Text("Memory: \(String(format: "%.1f", systemStats.memoryUsage))%")
                            .font(.headline)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.green)
                        Text("↓ \(String(format: "%.1f", systemStats.networkIn)) KB/s")
                            .font(.subheadline)
                        
                        Image(systemName: "arrow.up.circle")
                            .foregroundColor(.red)
                        Text("↑ \(String(format: "%.1f", systemStats.networkOut)) KB/s")
                            .font(.subheadline)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total: \(String(format: "%.0f", systemStats.totalMemory)) GB")
                        .font(.subheadline)
                    Text("Used: \(String(format: "%.1f", systemStats.usedMemory)) GB")
                        .font(.subheadline)
                    Text("Free: \(String(format: "%.1f", systemStats.freeMemory)) GB")
                        .font(.subheadline)
                }
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Tabs
            Picker("View", selection: $selectedTab) {
                Text("Processes").tag(0)
                Text("CPU History").tag(1)
                Text("Memory History").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            Group {
                if selectedTab == 0 {
                    ProcessListView(processManager: processManager)
                } else if selectedTab == 1 {
                    CPUHistoryView(systemStats: systemStats)
                } else {
                    MemoryHistoryView(systemStats: systemStats)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}

struct CPUHistoryView: View {
    @ObservedObject var systemStats: SystemStatsManager
    
    var body: some View {
        VStack {
            Text("CPU Usage History")
                .font(.headline)
                .padding()
            
            Chart(systemStats.cpuHistory, id: \.time) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("CPU %", point.value)
                )
                .foregroundStyle(.orange)
                
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("CPU %", point.value)
                )
                .foregroundStyle(.orange.opacity(0.2))
            }
            .frame(height: 300)
            .padding()
            
            Spacer()
        }
    }
}

struct MemoryHistoryView: View {
    @ObservedObject var systemStats: SystemStatsManager
    
    var body: some View {
        VStack {
            Text("Memory Usage History")
                .font(.headline)
                .padding()
            
            Chart(systemStats.memoryHistory, id: \.time) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Memory %", point.value)
                )
                .foregroundStyle(.blue)
                
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Memory %", point.value)
                )
                .foregroundStyle(.blue.opacity(0.2))
            }
            .frame(height: 300)
            .padding()
            
            Spacer()
        }
    }
}

struct HistoryPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}