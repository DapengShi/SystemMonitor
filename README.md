# SystemMonitor

SystemMonitor is a lightweight macOS menu bar utility that surfaces real-time CPU, memory, and network activity. It highlights processes that cross configurable thresholds so you can spot slowdowns before they impact your workflow.

## Features

- Live CPU, memory, and network usage directly in the menu bar
- Detail window with charts for system utilization and sortable process table
- Visual alerts and menu bar badge when a process crosses high-usage thresholds
- Quick process management, including filter, search, and one-click termination
- Packaged SwiftUI and AppKit implementation suitable for both Swift Package and Xcode workflows

## Getting Started

### Requirements

- macOS 12.0 or later
- Xcode 14 or later with Swift 5.7+ toolchain

### Build From Source

```bash
swift build
```

### Run the Menu Bar App

```bash
swift run SystemMonitor
```

### Create a Release Build & Bundle

```bash
swift build -c release
sh package_app.sh
```

The release build regenerates `SystemMonitor.app` and the distributable `SystemMonitor.zip` archive.

## Documentation

Extended guides are collected under the `docs/` directory:

- `docs/README.md` – documentation index and navigation
- `docs/user-guide.md` – everyday usage walkthrough
- `docs/interface-guide.md` – UI layout reference
- `docs/detail-page-guide.md` – tips for the detailed resource view

## Development Notes

- Core package sources live in `Sources/SystemMonitor/`
- The legacy SwiftUI app target under `SystemMonitor/` mirrors packaged code for rapid UI experiments
- Manual performance validation can be performed via `swift run SystemMonitor` alongside the provided `cpu_stress_test.py`

## Contributing

Contributions are welcome. Follow Conventional Commits when preparing patches, document manual validation steps, and include updated UI screenshots for visual changes.

## License

This project is licensed under the [Apache License 2.0](LICENSE).
