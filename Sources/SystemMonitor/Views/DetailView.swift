import SwiftUI
import Foundation

struct DetailView: View {
    @ObservedObject var systemStats = SystemStatsObservable()
    @State private var selectedProcess: ProcessInfo? = nil
    @State private var showKillConfirmation = false
    @State private var searchText = ""
    @State private var sortOption = SortOption.cpu
    
    enum SortOption: String, CaseIterable {
        case cpu = "CPU"
        case memory = "Memory"
        case name = "Name"
        case pid = "PID"
        
        var description: String {
            return self.rawValue
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and controls
            HStack {
                Text("System Monitor")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                
                Picker("Sort by", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.description).tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 300)
                
                TextField("Search processes", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            // Main content area with split view
            HSplitView {
                // Left side: System stats
                VStack(spacing: 16) {
                    // CPU Usage Panel
                    GroupBox(label: Text("CPU Usage").font(.headline)) {
                        VStack(alignment: .leading, spacing: 8) {
                            CPUUsageView(cpuUsage: systemStats.cpuUsage)
                            Text("Total: \(Int(systemStats.cpuUsage * 100))%")
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(8)
                    }
                    
                    // Memory Usage Panel
                    GroupBox(label: Text("Memory Usage").font(.headline)) {
                        VStack(alignment: .leading, spacing: 8) {
                            MemoryUsageView(memoryUsage: systemStats.memoryUsage)
                            Text("Used: \(Int(systemStats.memoryUsage * 100))%")
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(8)
                    }
                    
                    // Network Usage Panel
                    GroupBox(label: Text("Network").font(.headline)) {
                        VStack(alignment: .leading, spacing: 8) {
                            NetworkUsageView(
                                uploadSpeed: systemStats.uploadSpeed,
                                downloadSpeed: systemStats.downloadSpeed
                            )
                            HStack {
                                Text("↑ \(formatByteSpeed(systemStats.uploadSpeed))")
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Text("↓ \(formatByteSpeed(systemStats.downloadSpeed))")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding(8)
                    }
                }
                .frame(minWidth: 300, idealWidth: 350)
                .padding()
                
                // Right side: Process list
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredProcesses, id: \.pid) { process in
                                ProcessRowView(process: process, isSelected: selectedProcess?.pid == process.pid)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedProcess = process
                                    }
                                Divider()
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Bottom controls for process management
                    HStack {
                        Button(action: {
                            if selectedProcess != nil {
                                showKillConfirmation = true
                            }
                        }) {
                            Label("Kill Process", systemImage: "xmark.circle")
                        }
                        .disabled(selectedProcess == nil)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        
                        Spacer()
                        
                        if let process = selectedProcess {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Selected: \(process.name) (PID: \(process.pid))")
                                Text("CPU \(String(format: "%.1f%%", process.cpuUsage)), MEM \(String(format: "%.1f%%", process.memoryUsage))")
                                Text("NET ↓\(formatBytesPerSecond(process.networkInBytesPerSecond)) ↑\(formatBytesPerSecond(process.networkOutBytesPerSecond)) · DISK R\(formatBytesPerSecond(process.diskReadBytesPerSecond)) W\(formatBytesPerSecond(process.diskWriteBytesPerSecond))")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        } else {
                            Text("No process selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .alert(isPresented: $showKillConfirmation) {
            Alert(
                title: Text("Confirm Process Termination"),
                message: Text("Are you sure you want to terminate \(selectedProcess?.name ?? "") (PID: \(selectedProcess?.pid ?? 0))?\nThis action cannot be undone."),
                primaryButton: .destructive(Text("Kill")) {
                    killSelectedProcess()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private var filteredProcesses: [ProcessInfo] {
        let processes = systemStats.processes
        
        // Apply search filter if needed
        let filtered = searchText.isEmpty ? processes : processes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        
        // Apply sorting
        return filtered.sorted { p1, p2 in
            switch sortOption {
            case .cpu:
                return p1.cpuUsage > p2.cpuUsage
            case .memory:
                return p1.memoryUsage > p2.memoryUsage
            case .name:
                return p1.name.localizedCaseInsensitiveCompare(p2.name) == .orderedAscending
            case .pid:
                return p1.pid < p2.pid
            }
        }
    }
    
    private func killSelectedProcess() {
        guard let process = selectedProcess else { return }
        
        let task = Process()
        task.launchPath = "/bin/kill"
        task.arguments = ["-9", String(process.pid)]
        
        do {
            try task.run()
            // Wait a moment to refresh the process list
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                systemStats.refreshProcesses()
                selectedProcess = nil
            }
        } catch {
            print("Failed to kill process: \(error)")
        }
    }
    
    private func formatByteSpeed(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var speed = bytesPerSecond
        var unitIndex = 0
        
        while speed > 1024 && unitIndex < units.count - 1 {
            speed /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", speed, units[unitIndex])
    }
}

// MARK: - Subviews

struct CPUUsageView: View {
    let cpuUsage: Double
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(NSColor.controlBackgroundColor))
                .frame(height: 20)
            
            Rectangle()
                .fill(cpuUsage > 0.8 ? Color.red : Color.blue)
                .frame(width: max(CGFloat(cpuUsage) * 300, 4), height: 20)
        }
        .cornerRadius(4)
    }
}

struct MemoryUsageView: View {
    let memoryUsage: Double
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(NSColor.controlBackgroundColor))
                .frame(height: 20)
            
            Rectangle()
                .fill(memoryUsage > 0.8 ? Color.red : Color.green)
                .frame(width: max(CGFloat(memoryUsage) * 300, 4), height: 20)
        }
        .cornerRadius(4)
    }
}

struct NetworkUsageView: View {
    let uploadSpeed: Double
    let downloadSpeed: Double
    
    var body: some View {
        VStack(spacing: 4) {
            // Upload speed bar
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(height: 10)
                
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: getScaledWidth(for: uploadSpeed), height: 10)
            }
            .cornerRadius(2)
            
            // Download speed bar
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(height: 10)
                
                Rectangle()
                    .fill(Color.purple)
                    .frame(width: getScaledWidth(for: downloadSpeed), height: 10)
            }
            .cornerRadius(2)
        }
    }
    
    private func getScaledWidth(for bytesPerSecond: Double) -> CGFloat {
        // Auto-scaling algorithm for network speeds
        let maxWidth: CGFloat = 300
        let scaleFactor = min(CGFloat(bytesPerSecond) / 1_000_000, 1.0) // Scale based on 1MB/s max
        return max(scaleFactor * maxWidth, 2)
    }
}

struct ProcessRowView: View {
    let process: ProcessInfo
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Text("\(process.pid)")
                .frame(width: 60, alignment: .leading)
                .font(.system(.body, design: .monospaced))
            
            Text(process.name)
                .frame(minWidth: 200, alignment: .leading)
                .lineLimit(1)
            
            Spacer()
            
            Text("\(String(format: "%.1f%%", process.cpuUsage))")
                .frame(width: 60, alignment: .trailing)
                .foregroundColor(process.isHighCPU ? .red : .primary)
                .font(.system(.body, design: .monospaced))
            
            Text("\(String(format: "%.1f%%", process.memoryUsage))")
                .frame(width: 60, alignment: .trailing)
                .foregroundColor(process.isHighMemory ? .red : .primary)
                .font(.system(.body, design: .monospaced))

            VStack(alignment: .trailing, spacing: 2) {
                Text("↓ \(formatBytesPerSecond(process.networkInBytesPerSecond))")
                Text("↑ \(formatBytesPerSecond(process.networkOutBytesPerSecond))")
            }
            .frame(width: 120, alignment: .trailing)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)

            VStack(alignment: .trailing, spacing: 2) {
                Text("R \(formatBytesPerSecond(process.diskReadBytesPerSecond))")
                Text("W \(formatBytesPerSecond(process.diskWriteBytesPerSecond))")
            }
            .frame(width: 120, alignment: .trailing)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }
}

private func formatBytesPerSecond(_ bytes: Double) -> String {
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

// MARK: - Observable class for system stats

class SystemStatsObservable: ObservableObject {
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsage: Double = 0.0
    @Published var uploadSpeed: Double = 0.0
    @Published var downloadSpeed: Double = 0.0
    @Published var processes: [ProcessInfo] = []
    
    private let systemStats = SystemStats()
    private var timer: Timer?
    private var processTimer: Timer?
    private let samplingQueue = DispatchQueue(label: "com.systemmonitor.detail.processRefresh", qos: .userInitiated)
    private var refreshWorkItem: DispatchWorkItem?
    
    init() {
        // Initial update
        updateStats()
        refreshProcesses()
        
        // Set up timer for periodic updates
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        
        // Set up timer for process monitoring
        processTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshProcesses(immediate: false)
        }
    }
    
    deinit {
        timer?.invalidate()
        processTimer?.invalidate()
        refreshWorkItem?.cancel()
    }
    
    func updateStats() {
        // Update CPU usage
        cpuUsage = systemStats.getCPUUsage()
        
        // Update memory usage
        memoryUsage = systemStats.getMemoryUsage()
        
        // Update network stats
        let networkStats = systemStats.getNetworkStats()
        uploadSpeed = networkStats.uploadSpeed
        downloadSpeed = networkStats.downloadSpeed
    }
    
    func refreshProcesses(immediate: Bool = true) {
        scheduleProcessRefresh(immediate: immediate)
    }
    
    private func scheduleProcessRefresh(immediate: Bool) {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let fetched = self.systemStats.getTopProcesses(limit: 50)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                withAnimation(.easeInOut(duration: 0.15)) {
                    self?.processes = fetched
                }
            }
        }
        refreshWorkItem = workItem
        let delay: DispatchTime = immediate ? .now() : .now() + 0.1
        samplingQueue.asyncAfter(deadline: delay, execute: workItem)
    }
}
