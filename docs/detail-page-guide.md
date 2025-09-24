# Detail Page Guide

The detail window unlocks richer visualizations and process controls. Follow the steps below to open it and troubleshoot common issues.

## Opening the Detail View

1. Launch the latest build of SystemMonitor.
2. Locate the SystemMonitor icon in the macOS menu bar (showing CPU, MEM, and network values).
3. Click the icon and choose **Open Detailed View**.
4. Alternatively, use the keyboard shortcut `⌘D`.
5. The detail window appears with system charts on the left and the process table on the right.

## If the Menu Entry Is Missing

1. Verify that you are running the current release. Older versions may not expose the detail view.
2. Quit the app via the menu (`Quit` or `⌘Q`) and relaunch `SystemMonitor.app`.
3. Rebuild and repackage if necessary:
   ```bash
   cd /Users/shidapeng/Documents/SystemMonitor
   sh package_app.sh
   open SystemMonitor.app
   ```

## What You Will See

- **Charts** — CPU, memory, and network usage with auto-scaling thresholds.
- **Processes** — Sortable list with CPU and memory impact, plus controls to terminate runaway tasks.
- **Alerts** — High-usage processes appear in red, matching the menu bar warning state.

Use the detail page whenever you need a deeper snapshot than the compact menu view can provide.
