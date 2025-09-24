# User Guide

SystemMonitor surfaces key system metrics in the macOS menu bar while offering a focused detail window for deeper inspection. Use this guide to learn the primary workflows.

## Menu Bar Indicators

- **CPU** — Current CPU utilization percentage aggregated across all cores.
- **MEM** — Memory pressure represented as a percentage of active memory.
- **Network** — Upward arrow (↑) for upload speed, downward arrow (↓) for download speed.
- **Alerts** — When a process crosses the high-usage thresholds, the menu bar icon turns red to attract attention.

## Menu Actions

Click the menu bar icon to reveal:

1. **CPU Usage** — Snapshot of current CPU load.
2. **Memory Usage** — Breakdown of memory consumption.
3. **Network Activity** — Upload and download throughput details.
4. **Top Processes** — Table of the most resource-intensive processes.
5. **Open Detailed View** (`⌘D`) — Launches the feature-rich detail window.
6. **Quit** (`⌘Q`) — Exits the app.

## Detail Window Overview

- **Left Panel** — Charts for CPU, memory, and network usage with color-coded thresholds (red when crossing 80%).
- **Right Panel** — Sortable table showing up to 50 processes with CPU %, memory %, PID, and name. High-usage rows display in red.
- **Footer Controls** — Sorting toggles, search field, and `Kill Process` button.

### Process Management

1. Select a process in the table.
2. Click **Kill Process**.
3. Confirm the action in the dialog.

> **Warning:** Terminating system or critical app processes can destabilize your Mac. Double-check before you confirm.

## Refresh Cadence

SystemMonitor is designed to stay lightweight. System metrics refresh every two seconds, and the process list refreshes every five seconds to balance responsiveness with resource usage.
