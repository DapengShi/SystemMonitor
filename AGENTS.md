# Repository Guidelines

## Requirement speicfications and implmentation designs
1. Give the RFC for the uer's goal. The RFC files are all in doc/RFCs. And all files contians sequence number in file name.
2. Then analyize the RFCs and generate implmentation desgin docs in doc/designs. The desgin doc contains the sequence number of corresponding RFCs.

## Project Structure & Module Organization
SystemMonitor ships both as a Swift Package (`Package.swift`) and an Xcode project (`SystemMonitor.xcodeproj`). Core sources live in `Sources/SystemMonitor`, with `Views/` holding SwiftUI views, `SystemStats.swift` wrapping Darwin APIs, and `SystemMonitor-Bridging-Header.h` exposing C helpers. The legacy SwiftUI app target under `SystemMonitor/` mirrors the packaged code and is useful for quick UI experiments. Documentation for users and UI details sits at the repository root (`USER_GUIDE.md`, `INTERFACE_GUIDE.md`, `DETAIL_PAGE_GUIDE.md`). Keep any new assets or tooling scripts beside related features so packaging (`package_app.sh`) stays predictable.

## Build, Test, and Development Commands
- `swift build` – incremental debug build for CLI iteration.
- `swift run SystemMonitor` – launch the menubar app from the package target.
- `swift build -c release` – produce an optimized binary used by `package_app.sh`.
- `sh package_app.sh` – regenerate `SystemMonitor.app` and the distributable zip.
- `xcodebuild -project SystemMonitor.xcodeproj -scheme SystemMonitor` – integrate with CI or Xcode-driven workflows.

## Coding Style & Naming Conventions
Use four-space indentation and keep trailing whitespace out. Follow Swift defaults: `UpperCamelCase` for types, `lowerCamelCase` for functions, properties, and enum cases (`SortOption.cpu`). Prefer `struct` where value semantics are intended and annotate shared utilities with `// MARK:` blocks. Keep SwiftUI layouts declarative and split view-specific logic into dedicated files under `Views/`.

## Testing Guidelines
No XCTest target ships with this snapshot; create one under `Tests/SystemMonitorTests` when adding automated coverage. Name test files after the type under test (`SystemStatsTests.swift`) and group scenarios with `test_<Behavior>()`. Until unit tests exist, validate performance thresholds manually by running the app via `swift run` and stressing the system with `python3 cpu_stress_test.py`. Document manual checks in PR descriptions.

## Commit & Pull Request Guidelines
Version control metadata is not bundled here, so follow Conventional Commits (`feat: add process filter`, `fix: guard network stats`) when pushing to the canonical repo. Each PR should describe the change, link the tracking issue, list build/test commands run, and include updated screenshots for UI adjustments (menu bar, detail window). Request review from a maintainer familiar with the affected module and wait for at least one approval before merge.

## Packaging & Distribution
When cutting a release, run `swift build -c release`, execute `package_app.sh`, and archive the refreshed `SystemMonitor.zip`. Confirm the bundled `Info.plist` matches the version in `UPDATE_NOTES.md` and that the menubar icon behavior still signals high-usage alerts.
