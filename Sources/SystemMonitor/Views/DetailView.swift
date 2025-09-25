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

struct DetailView: View {
    @Environment(\.detailTheme) private var detailTheme
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var systemStats = SystemStatsObservable()
    @State private var selectedProcess: ProcessInfo? = nil
    @State private var showKillConfirmation = false
    @State private var expandedProcesses: Set<Int32> = []
    @State private var searchText = ""
    @State private var sortOption = SortOption.cpu
    @State private var currentPage = 0

    private let pageSize = 50
    private let availableSortOptions = SortOption.allCases
    private let sortChipMinWidth: CGFloat = 68

    private var palette: DetailThemePalette { detailTheme.palette }

    private var appearanceBinding: Binding<DetailAppearanceMode> {
        Binding(
            get: { detailTheme.mode },
            set: { detailTheme.update(mode: $0, using: colorScheme) }
        )
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"
        case network = "Network"
        case disk = "Disk"
        case name = "Name"
        case pid = "PID"

        var description: String {
            rawValue
        }

        var id: String { rawValue }
    }

    private var highlightedProcess: ProcessInfo? {
        selectedProcess ?? systemStats.processes.max { lhs, rhs in
            lhs.cpuUsage < rhs.cpuUsage
        }
    }

    private var headerSubtitle: String {
        let hostName = Host.current().localizedName ?? "Unknown Host"
        let timestamp = DetailHelpers.timestampFormatter.string(from: Date())
        return "\(hostName.uppercased()) • \(timestamp)"
    }

    private var loadAverageValues: (Double, Double, Double)? {
        DetailHelpers.loadAverages()
    }

    private var overviewMetrics: OverviewMetrics {
        OverviewMetrics(
            cpuUsage: systemStats.cpuUsage,
            memoryUsage: systemStats.memoryUsage,
            downloadSpeed: systemStats.downloadSpeed,
            uploadSpeed: systemStats.uploadSpeed,
            processCount: systemStats.processes.count,
            highlightedProcess: highlightedProcess,
            loadAverages: loadAverageValues
        )
    }

    var body: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()
            LinearGradient(
                colors: [palette.background, palette.backgroundSecondary.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 80)
            .ignoresSafeArea()

            VStack(spacing: 24) {
                headerSection
                DetailOverviewSection(metrics: overviewMetrics)
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
            clampCurrentPage()
        }
        .onChange(of: searchText) { newValue in
            if !newValue.isEmpty {
                expandedProcesses.removeAll()
            }
            currentPage = 0
        }
        .onChange(of: sortOption) { _ in
            currentPage = 0
        }
        .onChange(of: colorScheme) { scheme in
            detailTheme.updateSystemColorScheme(scheme)
        }
        .onAppear {
            detailTheme.updateSystemColorScheme(colorScheme)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SYSTEM MONITOR")
                    .font(.system(.title2, design: .monospaced).weight(.heavy))
                    .foregroundColor(palette.accentPrimary)
                    .shadow(color: palette.accentPrimary.opacity(0.3), radius: 10, x: 0, y: 6)
                Text(headerSubtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(palette.secondaryText)
            }

            Spacer(minLength: 12)

            sortPicker
                .frame(width: 420)

            appearancePicker

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(palette.iconMuted)
                TextField("Search processes", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(palette.primaryText)
                    .disableAutocorrection(true)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(palette.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(palette.controlBorder, lineWidth: 1)
            )
        }
    }

    private var appearancePicker: some View {
        Picker(selection: appearanceBinding) {
            ForEach(DetailAppearanceMode.allCases) { mode in
                DetailThemeOptionLabel(mode: mode)
                    .tag(mode)
            }
        } label: {
            DetailThemeOptionLabel(mode: detailTheme.mode)
        }
        .tint(palette.primaryText)
        .pickerStyle(.menu)
        .help("Select appearance for the detail view")
    }

    private var sortPicker: some View {
        let options = Array(availableSortOptions)
        return HStack(spacing: 8) {
            ForEach(options, id: \.id) { option in
                sortButton(for: option)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.controlBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.controlBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sortButton(for option: SortOption) -> some View {
        let isSelected = sortOption == option
        Button {
            sortOption = option
        } label: {
            Text(option.description.uppercased())
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundColor(isSelected ? palette.textOnAccent : palette.secondaryText)
                .lineLimit(1)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? palette.accentSecondary : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isSelected ? Color.clear : palette.controlBorder.opacity(0.7), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private var processPanel: some View {
        ProcessListView(
            title: "PROCESSES",
            rows: paginatedDisplayProcesses,
            totalProcesses: systemStats.processes.count,
            currentPage: currentPage,
            totalPages: totalPageCount,
            sortOption: sortOption,
            selectedProcess: $selectedProcess,
            onToggle: { toggleSubtree(for: $0) },
            onPageChange: { newValue in currentPage = newValue },
            onKillRequested: { showKillConfirmation = true }
        )
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

    private var totalPageCount: Int {
        guard pageSize > 0 else { return 1 }
        return max(1, Int(ceil(Double(allDisplayProcesses.count) / Double(pageSize))))
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

private struct DetailThemeOptionLabel: View {
    @Environment(\.detailTheme) private var detailTheme

    let mode: DetailAppearanceMode

    private var palette: DetailThemePalette { detailTheme.palette }

    var body: some View {
        let color = palette.primaryText
        return Label {
            Text(mode.title)
                .foregroundColor(color)
        } icon: {
            Image(systemName: mode.symbolName)
                .renderingMode(.template)
        }
        .tint(color)
        .padding(.vertical, 4)
    }
}
