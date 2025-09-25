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
import Foundation
import Darwin

private enum Palette {
    static let background = Color(red: 0.05, green: 0.07, blue: 0.12)
    static let backgroundSecondary = Color(red: 0.08, green: 0.10, blue: 0.18)
    static let panelBackground = Color(red: 0.11, green: 0.14, blue: 0.24)
    static let cardBackground = Color(red: 0.13, green: 0.16, blue: 0.27)
    static let border = Color.white.opacity(0.08)
    static let accentCyan = Color(red: 0.35, green: 0.78, blue: 0.98)
    static let accentMagenta = Color(red: 0.78, green: 0.42, blue: 0.98)
    static let accentGreen = Color(red: 0.40, green: 0.89, blue: 0.60)
    static let accentOrange = Color(red: 1.00, green: 0.56, blue: 0.32)
    static let accentPurple = Color(red: 0.62, green: 0.39, blue: 0.89)
    static let rowEven = Color.white.opacity(0.02)
    static let rowOdd = Color.white.opacity(0.04)
    static let rowSelected = Color.white.opacity(0.16)
    static let gradientCPU = LinearGradient(colors: [Palette.accentCyan, Palette.accentMagenta], startPoint: .leading, endPoint: .trailing)
    static let gradientMemory = LinearGradient(colors: [Palette.accentGreen, Color(red: 0.24, green: 0.73, blue: 0.87)], startPoint: .leading, endPoint: .trailing)
    static let gradientNetworkDown = LinearGradient(colors: [Color(red: 0.50, green: 0.67, blue: 0.99), Palette.accentCyan], startPoint: .leading, endPoint: .trailing)
    static let gradientNetworkUp = LinearGradient(colors: [Palette.accentOrange, Color(red: 0.99, green: 0.30, blue: 0.36)], startPoint: .leading, endPoint: .trailing)
    static let gradientProcess = LinearGradient(colors: [Palette.accentMagenta, Palette.accentPurple], startPoint: .leading, endPoint: .trailing)
}

struct DetailView: View {
    @ObservedObject var systemStats = SystemStatsObservable()
    @State private var selectedProcess: ProcessInfo? = nil
    @State private var showKillConfirmation = false
    @State private var expandedProcesses: Set<Int32> = []
    @State private var searchText = ""
    @State private var sortOption = SortOption.cpu
    @State private var currentPage = 0

    private let pageSize = 50

    enum SortOption: String, CaseIterable {
        case cpu = "CPU"
        case memory = "Memory"
        case network = "Network"
        case disk = "Disk"
        case name = "Name"
        case pid = "PID"

        var description: String {
            rawValue
        }
    }

    private let overviewColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    private var highlightedProcess: ProcessInfo? {
        selectedProcess ?? systemStats.processes.max { lhs, rhs in
            lhs.cpuUsage < rhs.cpuUsage
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM • HH:mm:ss"
        return formatter
    }()

    private var headerSubtitle: String {
        let hostName = Host.current().localizedName ?? "Unknown Host"
        let timestamp = DetailView.timestampFormatter.string(from: Date())
        return "\(hostName.uppercased()) • \(timestamp)"
    }

    private var loadAverageValues: (Double, Double, Double)? {
        var loads = [Double](repeating: 0, count: 3)
        let result = loads.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return getloadavg(baseAddress, 3)
        }
        guard result == 3 else { return nil }
        return (loads[0], loads[1], loads[2])
    }

    var body: some View {
        ZStack {
            Palette.background
                .ignoresSafeArea()
            LinearGradient(
                colors: [Palette.background, Palette.backgroundSecondary.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 80)
            .ignoresSafeArea()

            VStack(spacing: 24) {
                headerSection
                overviewGrid
                processPanel
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
        }
        .frame(minWidth: 1100, minHeight: 720)
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
        .onChange(of: systemStats.processes.map { $0.pid }) { pids in
            let available = Set(pids)
            expandedProcesses = expandedProcesses.intersection(available)
        }
        .onChange(of: searchText) { newValue in
            if !newValue.isEmpty {
                expandedProcesses.removeAll()
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SYSTEM MONITOR")
                    .font(.system(.title2, design: .monospaced).weight(.heavy))
                    .foregroundColor(Palette.accentCyan)
                    .shadow(color: Palette.accentCyan.opacity(0.3), radius: 10, x: 0, y: 6)
                Text(headerSubtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer(minLength: 12)

            Picker("Sort by", selection: $sortOption) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 420)
            .tint(Palette.accentMagenta)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.45))
                TextField("Search processes", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .disableAutocorrection(true)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Palette.cardBackground.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Palette.border, lineWidth: 1)
            )
        }
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: overviewColumns, spacing: 18) {
            StatBlock(
                title: "CPU",
                subtitle: "\(formatPercent(fromRatio: systemStats.cpuUsage)) USED",
                icon: "cpu",
                gradient: Palette.gradientCPU
            ) {
                UsageBar(value: systemStats.cpuUsage, gradient: Palette.gradientCPU)
                    .frame(height: 18)

                HStack(spacing: 12) {
                    MetricPill(
                        title: "Processes",
                        value: "\(systemStats.processes.count)",
                        color: Palette.accentCyan
                    )
                    if let top = highlightedProcess {
                        MetricPill(
                            title: "Top",
                            value: truncatedProcessName(top.name),
                            color: Palette.accentMagenta
                        )
                    }
                }

                if let loads = loadAverageValues {
                    HStack(spacing: 8) {
                        MetricPill(title: "1m", value: String(format: "%.2f", loads.0), color: Palette.accentCyan)
                        MetricPill(title: "5m", value: String(format: "%.2f", loads.1), color: Palette.accentMagenta)
                        MetricPill(title: "15m", value: String(format: "%.2f", loads.2), color: Palette.accentPurple)
                    }
                }
            }

            StatBlock(
                title: "MEMORY",
                subtitle: "\(formatPercent(fromRatio: systemStats.memoryUsage)) USED",
                icon: "memorychip",
                gradient: Palette.gradientMemory
            ) {
                UsageBar(value: systemStats.memoryUsage, gradient: Palette.gradientMemory)
                    .frame(height: 18)

                HStack(spacing: 12) {
                    MetricPill(
                        title: "Used",
                        value: formatPercent(fromRatio: systemStats.memoryUsage, decimals: 1),
                        color: Palette.accentGreen
                    )
                    MetricPill(
                        title: "Free",
                        value: formatPercent(fromRatio: max(0, 1 - systemStats.memoryUsage), decimals: 1),
                        color: Palette.accentCyan
                    )
                }
            }

            StatBlock(
                title: "NETWORK",
                subtitle: "↓ \(formatByteSpeed(systemStats.downloadSpeed)) • ↑ \(formatByteSpeed(systemStats.uploadSpeed))",
                icon: "dot.radiowaves.up.forward",
                gradient: Palette.gradientNetworkDown
            ) {
                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Download")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        UsageBar(value: networkBarValue(for: systemStats.downloadSpeed), gradient: Palette.gradientNetworkDown)
                            .frame(height: 14)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Upload")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        UsageBar(value: networkBarValue(for: systemStats.uploadSpeed), gradient: Palette.gradientNetworkUp)
                            .frame(height: 14)
                    }
                }
            }

            StatBlock(
                title: "FOCUS PROCESS",
                subtitle: highlightedProcess != nil ? truncatedProcessName(highlightedProcess!.name) : "No data",
                icon: "waveform.path.ecg",
                gradient: Palette.gradientProcess
            ) {
                if let process = highlightedProcess {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("PID")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                            Text("\(process.pid)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            MetricPill(
                                title: "Alerts",
                                value: process.isAbnormal ? "⚠︎" : "OK",
                                color: process.isAbnormal ? Palette.accentOrange : Palette.accentGreen
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("CPU")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                            UsageBar(value: min(process.cpuUsage / 100.0, 1.0), gradient: Palette.gradientProcess)
                                .frame(height: 14)
                                .overlay(
                                    Text(String(format: "%.1f%%", process.cpuUsage))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.trailing, 6),
                                    alignment: .trailing
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Memory")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                            UsageBar(value: min(process.memoryUsage / 100.0, 1.0), gradient: Palette.gradientMemory)
                                .frame(height: 14)
                                .overlay(
                                    Text(String(format: "%.1f%%", process.memoryUsage))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.trailing, 6),
                                    alignment: .trailing
                                )
                        }

                        HStack(spacing: 10) {
                            MetricPill(
                                title: "Net ↓",
                                value: formatBytesPerSecond(process.networkInBytesPerSecond),
                                color: Palette.accentCyan
                            )
                            MetricPill(
                                title: "Net ↑",
                                value: formatBytesPerSecond(process.networkOutBytesPerSecond),
                                color: Palette.accentOrange
                            )
                        }
                        HStack(spacing: 10) {
                            MetricPill(
                                title: "Disk R",
                                value: formatBytesPerSecond(process.diskReadBytesPerSecond),
                                color: Palette.accentGreen
                            )
                            MetricPill(
                                title: "Disk W",
                                value: formatBytesPerSecond(process.diskWriteBytesPerSecond),
                                color: Palette.accentMagenta
                            )
                        }
                    }
                } else {
                    Text("Select a process to inspect real-time metrics.")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }

    private var processPanel: some View {
        let rows = paginatedDisplayProcesses
        let totalPages = max(1, Int(ceil(Double(allDisplayProcesses.count) / Double(pageSize))))

        return VStack(spacing: 0) {
            HStack {
                Text("PROCESSES")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("Active \(systemStats.processes.count)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                if totalPages > 1 {
                    HStack(spacing: 8) {
                        Button(action: {
                            currentPage = max(currentPage - 1, 0)
                        }) {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.bordered)
                        .tint(Palette.accentCyan)
                        .disabled(currentPage == 0)

                        Text("Page \(currentPage + 1)/\(totalPages)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))

                        Button(action: {
                            currentPage = min(currentPage + 1, totalPages - 1)
                        }) {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.bordered)
                        .tint(Palette.accentCyan)
                        .disabled(currentPage >= totalPages - 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ProcessTableHeader(sortOption: sortOption)
                .padding(.horizontal, 4)

            Divider()
                .background(Palette.border)
                .padding(.bottom, 2)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, display in
                            ProcessRowView(
                                process: display.process,
                                depth: display.depth,
                                hasChildren: display.hasChildren,
                                isExpanded: display.isExpanded,
                                isSelected: selectedProcess?.pid == display.process.pid,
                                isEven: index % 2 == 0,
                                sortOption: sortOption,
                                onToggle: {
                                    toggleSubtree(for: display.process)
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedProcess = display.process
                            }
                            .onTapGesture(count: 2) {
                                if display.hasChildren {
                                    toggleSubtree(for: display.process)
                                }
                            }
                            .contextMenu {
                                if display.hasChildren {
                                    Button(display.isExpanded ? "Collapse Subtree" : "Expand Subtree") {
                                        toggleSubtree(for: display.process)
                                    }
                                }
                            }
                            .id(display.process.pid)
                        }
                    }
                }
                .onChange(of: rows.map { $0.process.pid }) { _ in
                    guard let pid = selectedProcess?.pid,
                          rows.contains(where: { $0.process.pid == pid }) else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(pid, anchor: .center)
                    }
                }
                .onChange(of: selectedProcess?.pid) { pid in
                    guard let pid = pid,
                          rows.contains(where: { $0.process.pid == pid }) else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(pid, anchor: .center)
                    }
                }
            }
            .background(Palette.cardBackground.opacity(0.4))

            Divider()
                .background(Palette.border)

            HStack(spacing: 12) {
                Button(action: {
                    if selectedProcess != nil {
                        showKillConfirmation = true
                    }
                }) {
                    Label("Kill Process", systemImage: "bolt.slash")
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                }
                .disabled(selectedProcess == nil)
                .buttonStyle(.borderedProminent)
                .tint(selectedProcess == nil ? Color.gray.opacity(0.6) : Palette.accentOrange)

                Spacer()

                if let process = selectedProcess {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("PID \(process.pid) • \(process.name)")
                        Text("CPU \(String(format: "%.1f%%", process.cpuUsage)) • MEM \(String(format: "%.1f%%", process.memoryUsage))")
                        Text("NET ↓\(formatBytesPerSecond(process.networkInBytesPerSecond)) ↑\(formatBytesPerSecond(process.networkOutBytesPerSecond)) · DISK R\(formatBytesPerSecond(process.diskReadBytesPerSecond)) W\(formatBytesPerSecond(process.diskWriteBytesPerSecond))")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                } else {
                    Text("Select a process to inspect or terminate")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Palette.panelBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Palette.border, lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 30, x: 0, y: 24)
        .onChange(of: searchText) { _ in
            currentPage = 0
        }
        .onChange(of: sortOption) { _ in
            currentPage = 0
        }
        .onChange(of: systemStats.processes.map { $0.pid }) { _ in
            clampCurrentPage()
        }
    }

    private var searchFilteredProcesses: [ProcessInfo] {
        let processes = systemStats.processes
        guard !searchText.isEmpty else {
            return processes
        }
        return processes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var allDisplayProcesses: [DisplayProcess] {
        let filtered = searchFilteredProcesses
        let childrenMap = Dictionary(grouping: filtered, by: { $0.parentPid })
        let sorted = sortProcesses(filtered, by: sortOption)

        if !searchText.isEmpty {
            return sorted.map { process in
                DisplayProcess(process: process, depth: 0, hasChildren: false, isExpanded: false)
            }
        }

        var added: Set<Int32> = []
        var flattened: [DisplayProcess] = []

        func emit(_ process: ProcessInfo, depth: Int) {
            guard !added.contains(process.pid) else { return }
            added.insert(process.pid)
            let children = childrenMap[process.pid] ?? []
            let hasChildren = !children.isEmpty
            let isExpanded = hasChildren && expandedProcesses.contains(process.pid)
            flattened.append(
                DisplayProcess(
                    process: process,
                    depth: depth,
                    hasChildren: hasChildren,
                    isExpanded: isExpanded
                )
            )

            if isExpanded {
                let orderedChildren = sortProcesses(children, by: .cpu)
                for child in orderedChildren {
                    emit(child, depth: depth + 1)
                }
            }
        }

        for process in sorted {
            if expandedProcesses.contains(process.parentPid) {
                continue
            }
            emit(process, depth: 0)
        }

        return flattened
    }

    private var paginatedDisplayProcesses: [DisplayProcess] {
        let rows = allDisplayProcesses
        guard pageSize > 0 else { return rows }
        let totalPages = max(1, Int(ceil(Double(rows.count) / Double(pageSize))))
        let page = min(max(currentPage, 0), totalPages - 1)
        let start = page * pageSize
        let end = min(start + pageSize, rows.count)
        guard start < end else { return [] }
        return Array(rows[start..<end])
    }

    private func sortProcesses(_ processes: [ProcessInfo], by option: SortOption) -> [ProcessInfo] {
        switch option {
        case .cpu:
            return processes.sorted { $0.cpuUsage > $1.cpuUsage }
        case .memory:
            return processes.sorted { $0.memoryUsage > $1.memoryUsage }
        case .network:
            return processes.sorted { ($0.networkInBytesPerSecond + $0.networkOutBytesPerSecond) > ($1.networkInBytesPerSecond + $1.networkOutBytesPerSecond) }
        case .disk:
            return processes.sorted { ($0.diskReadBytesPerSecond + $0.diskWriteBytesPerSecond) > ($1.diskReadBytesPerSecond + $1.diskWriteBytesPerSecond) }
        case .name:
            return processes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .pid:
            return processes.sorted { $0.pid < $1.pid }
        }
    }

    private func toggleSubtree(for process: ProcessInfo) {
        guard searchText.isEmpty else { return }
        let childrenMap = Dictionary(grouping: systemStats.processes, by: { $0.parentPid })
        guard let children = childrenMap[process.pid], !children.isEmpty else { return }

        if expandedProcesses.contains(process.pid) {
            expandedProcesses.remove(process.pid)
        } else {
            expandedProcesses.insert(process.pid)
        }
    }

    private func clampCurrentPage() {
        let totalCount = allDisplayProcesses.count
        guard pageSize > 0 else { return }
        let totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
        if currentPage >= totalPages {
            currentPage = max(totalPages - 1, 0)
        }
    }

    private func killSelectedProcess() {
        guard let process = selectedProcess else { return }

        let task = Process()
        task.launchPath = "/bin/kill"
        task.arguments = ["-9", String(process.pid)]

        do {
            try task.run()
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

    private func networkBarValue(for value: Double) -> Double {
        guard value > 0 else { return 0 }
        let minLog = log10(1.0)
        let maxLog = log10(50_000_000.0) // scale up to ~50 MB/s
        let current = log10(max(value, 1.0))
        let normalized = (current - minLog) / (maxLog - minLog)
        return min(max(normalized, 0), 1)
    }

    private func truncatedProcessName(_ name: String, limit: Int = 18) -> String {
        guard name.count > limit else { return name }
        let endIndex = name.index(name.startIndex, offsetBy: limit - 1)
        return "\(name[..<endIndex])…"
    }

    private func formatPercent(fromRatio value: Double, decimals: Int = 0) -> String {
        let clamped = max(0, min(value, 1)) * 100
        let format = "%.\(decimals)f"
        let formatted = String(format: format, clamped)
        return "\(formatted)%"
    }
}

private struct StatBlock<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient
    private let contentBuilder: () -> Content

    init(title: String, subtitle: String, icon: String, gradient: LinearGradient, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.gradient = gradient
        self.contentBuilder = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(gradient)
                        .frame(width: 34, height: 34)
                        .opacity(0.8)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                    Text(subtitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
            }

            contentBuilder()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Palette.cardBackground.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Palette.border, lineWidth: 1.1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 18)
    }
}

private struct UsageBar: View {
    let value: Double
    let gradient: LinearGradient

    var body: some View {
        GeometryReader { proxy in
            let clamped = max(0, min(value, 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(gradient)
                    .frame(width: max(clamped * proxy.size.width, clamped > 0 ? 6 : 0))
                    .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 6)
            }
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let color: Color

    init(title: String, value: String, color: Color = .white) {
        self.title = title
        self.value = value
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(color.opacity(0.9))
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(color.opacity(0.18))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct DisplayProcess: Identifiable {
    let process: ProcessInfo
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool

    var id: Int32 { process.pid }
}

private enum ProcessColumn {
    static let pid: CGFloat = 70
    static let cpu: CGFloat = 70
    static let memory: CGFloat = 70
    static let network: CGFloat = 140
    static let disk: CGFloat = 140
}

private struct ProcessTableHeader: View {
    let sortOption: DetailView.SortOption

    var body: some View {
        HStack(spacing: 0) {
            headerCell("PID", width: ProcessColumn.pid, alignment: .leading, isActive: sortOption == .pid)
            headerCell("PROCESS", width: nil, alignment: .leading, isActive: sortOption == .name, flexible: true)
            headerCell("CPU%", width: ProcessColumn.cpu, alignment: .trailing, isActive: sortOption == .cpu)
            headerCell("MEM%", width: ProcessColumn.memory, alignment: .trailing, isActive: sortOption == .memory)
            headerCell("NET", width: ProcessColumn.network, alignment: .trailing, isActive: sortOption == .network)
            headerCell("DISK", width: ProcessColumn.disk, alignment: .trailing, isActive: sortOption == .disk)
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.white.opacity(0.6))
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func headerCell(_ title: String, width: CGFloat?, alignment: Alignment, isActive: Bool = false, flexible: Bool = false) -> some View {
        let label = Text(title)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(isActive ? Palette.accentCyan : .white.opacity(0.55))

        return Group {
            if flexible {
                label
                    .frame(minWidth: 200, maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            } else if let width = width {
                label
                    .frame(width: width, alignment: alignment == .leading ? .leading : .trailing)
            } else {
                label
            }
        }
    }
}

private struct ProcessRowView: View {
    let process: ProcessInfo
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let isEven: Bool
    let sortOption: DetailView.SortOption
    let onToggle: () -> Void

    var body: some View {
        ZStack {
            (isSelected ? Palette.rowSelected : (isEven ? Palette.rowEven : Palette.rowOdd))
                .animation(.easeInOut(duration: 0.12), value: isSelected)

            HStack(spacing: 0) {
                Text("\(process.pid)")
                    .frame(width: ProcessColumn.pid, alignment: .leading)
                    .foregroundColor(.white.opacity(0.7))

                nameColumn

                Text(String(format: "%.1f%%", process.cpuUsage))
                    .frame(width: ProcessColumn.cpu, alignment: .trailing)
                    .foregroundColor(cpuColor)

                Text(String(format: "%.1f%%", process.memoryUsage))
                    .frame(width: ProcessColumn.memory, alignment: .trailing)
                    .foregroundColor(memoryColor)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("↓ \(formatBytesPerSecond(process.networkInBytesPerSecond))")
                    Text("↑ \(formatBytesPerSecond(process.networkOutBytesPerSecond))")
                }
                .frame(width: ProcessColumn.network, alignment: .trailing)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(networkColor)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("R \(formatBytesPerSecond(process.diskReadBytesPerSecond))")
                    Text("W \(formatBytesPerSecond(process.diskWriteBytesPerSecond))")
                }
                .frame(width: ProcessColumn.disk, alignment: .trailing)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(diskColor)
            }
            .font(.system(.body, design: .monospaced))
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
        }
        .overlay(
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var nameColumn: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<depth, id: \.self) { _ in
                SpacerView(width: 14)
            }

            if hasChildren {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Palette.accentCyan.opacity(0.85))
                    .onTapGesture {
                        onToggle()
                    }
            } else if depth > 0 {
                SpacerView(width: 12)
            }

            Text(process.name)
                .lineLimit(1)
                .foregroundColor(.white.opacity(0.92))
        }
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
    }

    private var cpuColor: Color {
        if process.isHighCPU {
            return Palette.accentOrange
        }
        return sortOption == .cpu ? Palette.accentMagenta : .white.opacity(0.75)
    }

    private var memoryColor: Color {
        if process.isHighMemory {
            return Palette.accentOrange
        }
        return sortOption == .memory ? Palette.accentGreen : .white.opacity(0.75)
    }

    private var networkColor: Color {
        sortOption == .network ? Palette.accentCyan.opacity(0.85) : .white.opacity(0.55)
    }

    private var diskColor: Color {
        sortOption == .disk ? Palette.accentMagenta.opacity(0.85) : .white.opacity(0.55)
    }
}

private struct SpacerView: View {
    let width: CGFloat

    var body: some View {
        Color.clear
            .frame(width: width, height: 1)
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
        updateStats()
        refreshProcesses()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }

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
        cpuUsage = systemStats.getCPUUsage()
        memoryUsage = systemStats.getMemoryUsage()
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
            let fetched = self.systemStats.getTopProcesses(limit: 0)
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
