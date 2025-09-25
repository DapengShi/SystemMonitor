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
    @Environment(\.detailTheme) private var detailTheme

    let metrics: OverviewMetrics

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    private var palette: DetailThemePalette { detailTheme.palette }
    private var highlightedProcess: ProcessInfo? { metrics.highlightedProcess }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            StatBlock(
                title: "CPU",
                subtitle: "\(DetailHelpers.formatPercent(fromRatio: metrics.cpuUsage)) USED",
                icon: "cpu",
                gradient: palette.gradients.cpu,
                palette: palette
            ) {
                UsageBar(
                    value: metrics.cpuUsage,
                    gradient: palette.gradients.cpu,
                    trackColor: palette.controlBorder.opacity(0.35),
                    shadowColor: palette.shadow.opacity(0.6)
                )
                .frame(height: 18)

                HStack(spacing: 12) {
                    MetricPill(
                        title: "Processes",
                        value: "\(metrics.processCount)",
                        color: palette.accentPrimary,
                        palette: palette
                    )
                    if let top = highlightedProcess {
                        MetricPill(
                            title: "Top",
                            value: DetailHelpers.truncatedProcessName(top.name),
                            color: palette.accentSecondary,
                            palette: palette
                        )
                    }
                }

                if let loads = metrics.loadAverages {
                    HStack(spacing: 8) {
                        MetricPill(title: "1m", value: String(format: "%.2f", loads.0), color: palette.accentPrimary, palette: palette)
                        MetricPill(title: "5m", value: String(format: "%.2f", loads.1), color: palette.accentSecondary, palette: palette)
                        MetricPill(title: "15m", value: String(format: "%.2f", loads.2), color: palette.accentQuaternary, palette: palette)
                    }
                }
            }

            StatBlock(
                title: "MEMORY",
                subtitle: "\(DetailHelpers.formatPercent(fromRatio: metrics.memoryUsage)) USED",
                icon: "memorychip",
                gradient: palette.gradients.memory,
                palette: palette
            ) {
                UsageBar(
                    value: metrics.memoryUsage,
                    gradient: palette.gradients.memory,
                    trackColor: palette.controlBorder.opacity(0.35),
                    shadowColor: palette.shadow.opacity(0.6)
                )
                .frame(height: 18)

                HStack(spacing: 12) {
                    MetricPill(
                        title: "Used",
                        value: DetailHelpers.formatPercent(fromRatio: metrics.memoryUsage, decimals: 1),
                        color: palette.accentTertiary,
                        palette: palette
                    )
                    MetricPill(
                        title: "Free",
                        value: DetailHelpers.formatPercent(fromRatio: max(0, 1 - metrics.memoryUsage), decimals: 1),
                        color: palette.accentPrimary,
                        palette: palette
                    )
                }
            }

            StatBlock(
                title: "NETWORK",
                subtitle: "↓ \(DetailHelpers.formatByteSpeed(metrics.downloadSpeed)) • ↑ \(DetailHelpers.formatByteSpeed(metrics.uploadSpeed))",
                icon: "dot.radiowaves.up.forward",
                gradient: palette.gradients.networkDown,
                palette: palette
            ) {
                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Download")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(palette.secondaryText)
                        UsageBar(
                            value: DetailHelpers.networkBarValue(for: metrics.downloadSpeed),
                            gradient: palette.gradients.networkDown,
                            trackColor: palette.controlBorder.opacity(0.35),
                            shadowColor: palette.shadow.opacity(0.6)
                        )
                        .frame(height: 14)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Upload")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(palette.secondaryText)
                        UsageBar(
                            value: DetailHelpers.networkBarValue(for: metrics.uploadSpeed),
                            gradient: palette.gradients.networkUp,
                            trackColor: palette.controlBorder.opacity(0.35),
                            shadowColor: palette.shadow.opacity(0.6)
                        )
                        .frame(height: 14)
                    }
                }
            }

            StatBlock(
                title: "FOCUS PROCESS",
                subtitle: highlightedProcess != nil ? DetailHelpers.truncatedProcessName(highlightedProcess!.name) : "No data",
                icon: "waveform.path.ecg",
                gradient: palette.gradients.process,
                palette: palette
            ) {
                if let process = highlightedProcess {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("PID")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(palette.secondaryText)
                            Text("\(process.pid)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(palette.primaryText)
                            Spacer()
                            MetricPill(
                                title: "Alerts",
                                value: process.isAbnormal ? "⚠︎" : "OK",
                                color: process.isAbnormal ? palette.accentWarning : palette.accentSuccess,
                                palette: palette
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("CPU")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(palette.secondaryText)
                            UsageBar(
                                value: min(process.cpuUsage / 100.0, 1.0),
                                gradient: palette.gradients.process,
                                trackColor: palette.controlBorder.opacity(0.35),
                                shadowColor: palette.shadow.opacity(0.6)
                            )
                            .frame(height: 14)
                            .overlay(
                                Text(String(format: "%.1f%%", process.cpuUsage))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(palette.primaryText)
                                    .padding(.trailing, 6),
                                alignment: .trailing
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Memory")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(palette.secondaryText)
                            UsageBar(
                                value: min(process.memoryUsage / 100.0, 1.0),
                                gradient: palette.gradients.memory,
                                trackColor: palette.controlBorder.opacity(0.35),
                                shadowColor: palette.shadow.opacity(0.6)
                            )
                            .frame(height: 14)
                            .overlay(
                                Text(String(format: "%.1f%%", process.memoryUsage))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(palette.primaryText)
                                    .padding(.trailing, 6),
                                alignment: .trailing
                            )
                        }

                        HStack(spacing: 10) {
                            MetricPill(
                                title: "Net ↓",
                                value: DetailHelpers.formatBytesPerSecond(process.networkInBytesPerSecond),
                                color: palette.accentPrimary,
                                palette: palette
                            )
                            MetricPill(
                                title: "Net ↑",
                                value: DetailHelpers.formatBytesPerSecond(process.networkOutBytesPerSecond),
                                color: palette.accentWarning,
                                palette: palette
                            )
                        }
                        HStack(spacing: 10) {
                            MetricPill(
                                title: "Disk R",
                                value: DetailHelpers.formatBytesPerSecond(process.diskReadBytesPerSecond),
                                color: palette.accentSuccess,
                                palette: palette
                            )
                            MetricPill(
                                title: "Disk W",
                                value: DetailHelpers.formatBytesPerSecond(process.diskWriteBytesPerSecond),
                                color: palette.accentSecondary,
                                palette: palette
                            )
                        }
                    }
                } else {
                    Text("Select a process to inspect real-time metrics.")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(palette.secondaryText)
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
    let palette: DetailThemePalette
    private let contentBuilder: () -> Content

    init(title: String,
         subtitle: String,
         icon: String,
         gradient: LinearGradient,
         palette: DetailThemePalette,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.gradient = gradient
        self.palette = palette
        self.contentBuilder = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(gradient)
                        .frame(width: 34, height: 34)
                        .opacity(0.85)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(palette.primaryText)
                    Text(subtitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(palette.secondaryText)
                }
            }

            contentBuilder()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(palette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(palette.border, lineWidth: 1.1)
        )
        .shadow(color: palette.shadow, radius: 24, x: 0, y: 18)
    }
}

private struct UsageBar: View {
    let value: Double
    let gradient: LinearGradient
    let trackColor: Color
    let shadowColor: Color

    var body: some View {
        GeometryReader { proxy in
            let clamped = max(0, min(value, 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                Capsule()
                    .fill(gradient)
                    .frame(width: max(clamped * proxy.size.width, clamped > 0 ? 6 : 0))
                    .shadow(color: shadowColor, radius: 10, x: 0, y: 6)
            }
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let color: Color
    let palette: DetailThemePalette

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(color)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(palette.primaryText)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(color.opacity(0.18))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.35), lineWidth: 1)
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
        return Group {
            DetailOverviewSection(metrics: metrics)
                .detailTheme(DetailThemeController.preview(mode: .night, colorScheme: .dark))
                .padding()
                .background(Color.black)
                .previewDisplayName("Night")

            DetailOverviewSection(metrics: metrics)
                .detailTheme(DetailThemeController.preview(mode: .day, colorScheme: .light))
                .padding()
                .background(Color.white)
                .previewDisplayName("Day")
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
