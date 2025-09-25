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

struct DisplayProcess: Identifiable {
    let process: ProcessInfo
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool

    var id: Int32 { process.pid }
}

struct ProcessListView: View {
    @Environment(\.detailTheme) private var detailTheme

    let title: String
    let rows: [DisplayProcess]
    let totalProcesses: Int
    let currentPage: Int
    let totalPages: Int
    let sortOption: DetailView.SortOption
    @Binding var selectedProcess: ProcessInfo?
    let onToggle: (ProcessInfo) -> Void
    let onPageChange: (Int) -> Void
    let onKillRequested: () -> Void

    private var palette: DetailThemePalette { detailTheme.palette }

    var body: some View {
        VStack(spacing: 0) {
            header
            ProcessTableHeader(sortOption: sortOption, palette: palette)
                .padding(.horizontal, 4)

            Divider()
                .background(palette.border)
                .padding(.bottom, 2)

            scrollableRows
                .background(palette.cardBackground.opacity(0.45))

            Divider()
                .background(palette.border)

            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(palette.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(palette.border, lineWidth: 1.2)
        )
        .shadow(color: palette.shadow, radius: 30, x: 0, y: 24)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(palette.primaryText)
            Spacer()
            Text("Active \(totalProcesses)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(palette.tertiaryText)
            if totalPages > 1 {
                paginationControls
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var paginationControls: some View {
        HStack(spacing: 8) {
            Button(action: {
                onPageChange(max(currentPage - 1, 0))
            }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .tint(palette.paginationTint)
            .disabled(currentPage == 0)

            Text("Page \(currentPage + 1)/\(totalPages)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(palette.tertiaryText)

            Button(action: {
                onPageChange(min(currentPage + 1, totalPages - 1))
            }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .tint(palette.paginationTint)
            .disabled(currentPage >= totalPages - 1)
        }
    }

    private var scrollableRows: some View {
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
                            palette: palette,
                            onToggle: { onToggle(display.process) },
                            onSelect: { selectedProcess = display.process }
                        )
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
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: {
                if selectedProcess != nil {
                    onKillRequested()
                }
            }) {
                Label("Kill Process", systemImage: "bolt.slash")
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
            }
            .disabled(selectedProcess == nil)
            .buttonStyle(.borderedProminent)
            .tint(selectedProcess == nil ? palette.tertiaryText.opacity(0.4) : palette.accentWarning)

            Spacer()

            if let process = selectedProcess {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PID \(process.pid) • \(process.name)")
                    Text("CPU \(String(format: "%.1f%%", process.cpuUsage)) • MEM \(String(format: "%.1f%%", process.memoryUsage))")
                    Text("NET ↓\(DetailHelpers.formatBytesPerSecond(process.networkInBytesPerSecond)) ↑\(DetailHelpers.formatBytesPerSecond(process.networkOutBytesPerSecond)) · DISK R\(DetailHelpers.formatBytesPerSecond(process.diskReadBytesPerSecond)) W\(DetailHelpers.formatBytesPerSecond(process.diskWriteBytesPerSecond))")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(palette.secondaryText)
            } else {
                Text("Select a process to inspect or terminate")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(palette.tertiaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
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
    let palette: DetailThemePalette

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
        .foregroundColor(palette.secondaryText)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func headerCell(_ title: String, width: CGFloat?, alignment: Alignment, isActive: Bool = false, flexible: Bool = false) -> some View {
        let label = Text(title)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(isActive ? palette.accentPrimary : palette.secondaryText)

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
    let palette: DetailThemePalette
    let onToggle: () -> Void
    let onSelect: () -> Void

    var body: some View {
        ZStack {
            (isSelected ? palette.rowSelected : palette.rowBackground(isEven: isEven))
                .animation(.easeInOut(duration: 0.12), value: isSelected)

            HStack(spacing: 0) {
                Text("\(process.pid)")
                    .frame(width: ProcessColumn.pid, alignment: .leading)
                    .foregroundColor(palette.secondaryText)

                nameColumn

                Text(String(format: "%.1f%%", process.cpuUsage))
                    .frame(width: ProcessColumn.cpu, alignment: .trailing)
                    .foregroundColor(cpuColor)

                Text(String(format: "%.1f%%", process.memoryUsage))
                    .frame(width: ProcessColumn.memory, alignment: .trailing)
                    .foregroundColor(memoryColor)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("↓ \(DetailHelpers.formatBytesPerSecond(process.networkInBytesPerSecond))")
                    Text("↑ \(DetailHelpers.formatBytesPerSecond(process.networkOutBytesPerSecond))")
                }
                .frame(width: ProcessColumn.network, alignment: .trailing)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(networkColor)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("R \(DetailHelpers.formatBytesPerSecond(process.diskReadBytesPerSecond))")
                    Text("W \(DetailHelpers.formatBytesPerSecond(process.diskWriteBytesPerSecond))")
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
                .fill(palette.border)
                .frame(height: 1),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            if hasChildren {
                onToggle()
            }
        }
        .contextMenu {
            if hasChildren {
                Button(isExpanded ? "Collapse Subtree" : "Expand Subtree") {
                    onToggle()
                }
            }
        }
    }

    private var nameColumn: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<depth, id: \.self) { _ in
                SpacerView(width: 14)
            }

            if hasChildren {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(palette.accentPrimary)
                    .onTapGesture {
                        onToggle()
                    }
            } else if depth > 0 {
                SpacerView(width: 12)
            }

            Text(process.name)
                .lineLimit(1)
                .foregroundColor(palette.primaryText)
        }
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
    }

    private var cpuColor: Color {
        if process.isHighCPU {
            return palette.accentWarning
        }
        return sortOption == .cpu ? palette.accentSecondary : palette.secondaryText
    }

    private var memoryColor: Color {
        if process.isHighMemory {
            return palette.accentWarning
        }
        return sortOption == .memory ? palette.accentTertiary : palette.secondaryText
    }

    private var networkColor: Color {
        sortOption == .network ? palette.accentPrimary : palette.tertiaryText
    }

    private var diskColor: Color {
        sortOption == .disk ? palette.accentSecondary : palette.tertiaryText
    }
}

private struct SpacerView: View {
    let width: CGFloat

    var body: some View {
        Color.clear
            .frame(width: width, height: 1)
    }
}
