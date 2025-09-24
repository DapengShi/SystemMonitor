# Interface Guide

The SystemMonitor UI mirrors the efficiency of TUI monitors such as btop while remaining native to macOS. Use this guide as a reference when iterating on interface changes.

## Menu Bar

- Displays compact CPU, memory, and network metrics.
- Includes the `Open Detailed View` command for quick access to the windowed experience.

## Detail Window Layout

### Left Panel

1. **CPU Usage** — Horizontal bar with dynamic color; turns red once usage exceeds 80%.
2. **Memory Usage** — Memory pressure bar using the same threshold logic as CPU.
3. **Network Throughput** — Paired bars (orange for upload, purple for download) that auto-scale to the active network speeds.

### Right Panel

1. **Processes Table** — Up to 50 rows with PID, name, CPU %, and memory %. High-usage rows appear in red.
2. **Controls** —
   - Sorting options: CPU, memory, name, or PID.
   - Search field for narrowing the list by process name.
   - `Kill Process` button located at the bottom edge.

## Interaction Model

- Click any row to select a process.
- Toggle the sort controls to reorder the table.
- Use the search field to filter results in real time.
- `Kill Process` prompts for confirmation before sending the termination signal.

## Cautionary Notes

- Killing essential system processes may trigger instability or data loss.
- Data refreshes automatically; there is no need to manually reload.
