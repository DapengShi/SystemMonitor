import SwiftUI

struct DisplayProcess: Identifiable {
    let process: ProcessInfo
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool

    var id: Int32 { process.pid }
}

struct ProcessListView: View {
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

    var body: some View {
        VStack(spacing: 0) {
            header
            ProcessTableHeader(sortOption: sortOption)
                .padding(.horizontal, 4)

            Divider()
                .background(Palette.border)
                .padding(.bottom, 2)

            scrollableRows
                .background(Palette.cardBackground.opacity(0.4))

            Divider()
                .background(Palette.border)

            footer
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
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text("Active \(totalProcesses)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
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
            .tint(Palette.accentCyan)
            .disabled(currentPage == 0)

            Text("Page \(currentPage + 1)/\(totalPages)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            Button(action: {
                onPageChange(min(currentPage + 1, totalPages - 1))
            }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .tint(Palette.accentCyan)
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
            .tint(selectedProcess == nil ? Color.gray.opacity(0.6) : Palette.accentOrange)

            Spacer()

            if let process = selectedProcess {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PID \(process.pid) • \(process.name)")
                    Text("CPU \(String(format: "%.1f%%", process.cpuUsage)) • MEM \(String(format: "%.1f%%", process.memoryUsage))")
                    Text("NET ↓\(DetailHelpers.formatBytesPerSecond(process.networkInBytesPerSecond)) ↑\(DetailHelpers.formatBytesPerSecond(process.networkOutBytesPerSecond)) · DISK R\(DetailHelpers.formatBytesPerSecond(process.diskReadBytesPerSecond)) W\(DetailHelpers.formatBytesPerSecond(process.diskWriteBytesPerSecond))")
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
    let onSelect: () -> Void

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
                .fill(Palette.border)
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
