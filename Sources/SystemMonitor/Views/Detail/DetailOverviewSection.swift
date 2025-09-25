import SwiftUI

struct OverviewMetrics {
    let cpuUsage: Double
    let memoryUsage: Double
    let downloadSpeed: Double
    let uploadSpeed: Double
    let processCount: Int
    let highlightedProcess: ProcessInfo?
    let loadAverages: (Double, Double, Double)?
}

struct DetailOverviewSection: View {
    let metrics: OverviewMetrics

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    private var highlightedProcess: ProcessInfo? { metrics.highlightedProcess }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            StatBlock(
                title: "CPU",
                subtitle: "\(DetailHelpers.formatPercent(fromRatio: metrics.cpuUsage)) USED",
                icon: "cpu",
                gradient: Palette.gradientCPU
            ) {
                UsageBar(value: metrics.cpuUsage, gradient: Palette.gradientCPU)
                    .frame(height: 18)

                HStack(spacing: 12) {
                    MetricPill(
                        title: "Processes",
                        value: "\(metrics.processCount)",
                        color: Palette.accentCyan
                    )
                    if let top = highlightedProcess {
                        MetricPill(
                            title: "Top",
                            value: DetailHelpers.truncatedProcessName(top.name),
                            color: Palette.accentMagenta
                        )
                    }
                }

                if let loads = metrics.loadAverages {
                    HStack(spacing: 8) {
                        MetricPill(title: "1m", value: String(format: "%.2f", loads.0), color: Palette.accentCyan)
                        MetricPill(title: "5m", value: String(format: "%.2f", loads.1), color: Palette.accentMagenta)
                        MetricPill(title: "15m", value: String(format: "%.2f", loads.2), color: Palette.accentPurple)
                    }
                }
            }

            StatBlock(
                title: "MEMORY",
                subtitle: "\(DetailHelpers.formatPercent(fromRatio: metrics.memoryUsage)) USED",
                icon: "memorychip",
                gradient: Palette.gradientMemory
            ) {
                UsageBar(value: metrics.memoryUsage, gradient: Palette.gradientMemory)
                    .frame(height: 18)

                HStack(spacing: 12) {
                    MetricPill(
                        title: "Used",
                        value: DetailHelpers.formatPercent(fromRatio: metrics.memoryUsage, decimals: 1),
                        color: Palette.accentGreen
                    )
                    MetricPill(
                        title: "Free",
                        value: DetailHelpers.formatPercent(fromRatio: max(0, 1 - metrics.memoryUsage), decimals: 1),
                        color: Palette.accentCyan
                    )
                }
            }

            StatBlock(
                title: "NETWORK",
                subtitle: "↓ \(DetailHelpers.formatByteSpeed(metrics.downloadSpeed)) • ↑ \(DetailHelpers.formatByteSpeed(metrics.uploadSpeed))",
                icon: "dot.radiowaves.up.forward",
                gradient: Palette.gradientNetworkDown
            ) {
                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Download")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        UsageBar(value: DetailHelpers.networkBarValue(for: metrics.downloadSpeed), gradient: Palette.gradientNetworkDown)
                            .frame(height: 14)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Upload")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        UsageBar(value: DetailHelpers.networkBarValue(for: metrics.uploadSpeed), gradient: Palette.gradientNetworkUp)
                            .frame(height: 14)
                    }
                }
            }

            StatBlock(
                title: "FOCUS PROCESS",
                subtitle: highlightedProcess != nil ? DetailHelpers.truncatedProcessName(highlightedProcess!.name) : "No data",
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
                                value: DetailHelpers.formatBytesPerSecond(process.networkInBytesPerSecond),
                                color: Palette.accentCyan
                            )
                            MetricPill(
                                title: "Net ↑",
                                value: DetailHelpers.formatBytesPerSecond(process.networkOutBytesPerSecond),
                                color: Palette.accentOrange
                            )
                        }
                        HStack(spacing: 10) {
                            MetricPill(
                                title: "Disk R",
                                value: DetailHelpers.formatBytesPerSecond(process.diskReadBytesPerSecond),
                                color: Palette.accentGreen
                            )
                            MetricPill(
                                title: "Disk W",
                                value: DetailHelpers.formatBytesPerSecond(process.diskWriteBytesPerSecond),
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

#if DEBUG
struct DetailOverviewSection_Previews: PreviewProvider {
    static var previews: some View {
        let sampleProcess = ProcessInfo(
            pid: 1234,
            parentPid: 1,
            name: "SampleProcess",
            commandLine: "SampleProcess --arg",
            username: "user",
            cpuInstantPercent: 42.5,
            cpuCumulativePercent: 37.2,
            residentBytes: 512_000_000,
            memoryPercent: 12.4,
            threadCount: 8,
            networkInBytesPerSecond: 1_024_000,
            networkOutBytesPerSecond: 512_000,
            diskReadBytesPerSecond: 256_000,
            diskWriteBytesPerSecond: 128_000,
            logicalWriteBytesPerSecond: 128_000,
            flags: []
        )
        let metrics = OverviewMetrics(
            cpuUsage: 0.38,
            memoryUsage: 0.62,
            downloadSpeed: 2_400_000,
            uploadSpeed: 1_200_000,
            processCount: 142,
            highlightedProcess: sampleProcess,
            loadAverages: (1.23, 1.12, 0.98)
        )
        return DetailOverviewSection(metrics: metrics)
            .padding()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
#endif
