# RFC-001: Native macOS Process Metric Collector

- Status: Draft
- Authors: Codex
- Created: 2024-05-25
- Components: SystemStats, Views/DetailView, Bridging Interfaces

## Context
SystemMonitor currently shells out to `ps` and `nettop` on each refresh to populate process tables and per-process throughput. This approach inflates latency, drops data for short-lived processes, and yields CPU and memory numbers that do not match tools like btop which derive values from kernel counters. The goal is to migrate to macOS SDK primitives so we can sample frequently without process spawning overhead, while meeting feature parity requirements (per-PID metrics, full command line, process tree).

## Goals
- Replace external command execution with native APIs (`libproc`, `sysctl`, `mach` kernels).
- Track instantaneous CPU usage per process with multi-core aware percentages.
- Provide per-process resident size (bytes) and retain existing percent formatting in the UI.
- Report per-PID disk and network throughput as deltas per refresh window.
- Cache full command line strings for display and search.
- Minimize `sysctl` overhead via buffer reuse and change-detection heuristics.

## Non-Goals
- Introducing new UI surfaces beyond what DetailView already renders.
- Providing kernel-private data that demands elevated entitlements (e.g. Endpoint Security).
- Collecting network statistics for non-socket I/O like AF_SYSTEM (exposed as zeroed metrics instead).

## Current Pain Points
- `%CPU` from `ps` is lifetime-averaged and capped at 100%; spikes are missed.
- `%MEM` is provided without underlying byte values, limiting sorting precision.
- `nettop` startup dominates refresh latency and inherits locale parsing issues.
- The process list is truncated at `limit`, breaking tree and search features.
- Command names are truncated (`comm`) and omit arguments.

## Proposed Architecture
### Collector Pipeline
1. **Process Snapshot**: Invoke `sysctl` with `{CTL_KERN, KERN_PROC, KERN_PROC_ALL}` on a dedicated queue every refresh (default 2 s for host metrics, 5 s for process metrics). Allocate a reusable buffer sized from the previous call; grow only when `sysctl` returns `ENOMEM`.
2. **Process Cache**: Maintain a `ProcessCache` keyed by PID storing previous host tick totals, `proc_pidinfo` counters, command line strings, and timestamp of last scan.
3. **Per-PID Detail**:
   - Call `proc_pidinfo(pid, PROC_PIDTASKINFO, ...)` once per active PID to obtain user/system runtime, resident size, thread counts, and IO bytes.
   - Fetch full command lines via `sysctl` with `{CTL_KERN, KERN_PROCARGS2}` on first observation; store in cache until PID exits.
   - Resolve executable path with `proc_pidpath` for fallback display.
   - Lookup user names through `getpwuid` and cache UID→string mappings.
4. **CPU Computation**:
   - Use `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` to capture system tick deltas.
   - For each PID, compute `(delta_user + delta_system) / host_delta_ticks * core_count * 100` with clamping to `[0, core_count * 100]`.
5. **Memory Metrics**:
   - Record `pti_resident_size` (bytes) and compute `%MEM = resident / totalMem` where `totalMem` is retrieved once on init via `sysctlbyname("hw.memsize")`.
6. **Disk Throughput**:
   - Leverage `proc_pid_rusage(pid, RUSAGE_INFO_V6, ...)` to read cumulative `ri_diskio_bytes{read,written}` and derive per-second deltas using timestamps.
7. **Per-PID Network Throughput**:
   - Enumerate sockets using `proc_pidinfo(pid, PROC_PIDLISTFDS, ...)`.
   - For each file descriptor with `PROC_PIDFDSOCKETINFO`, accumulate bytes from protocol-specific payloads:
     - TCP: `socket_fdinfo.psi.soi_kind == SOCKINFO_TCP` exposes `tcpsi_state.tcpi_bytes_in/out`.
     - UDP: fall back to `socket_fdinfo.psi.soi_flow_control.rcv_obytes/ibytes` when available.
   - Maintain `NetworkSnapshot` per PID storing totals per interface.
   - Compute upload/download rates as `(current - previous) / elapsed` with graceful handling for closed sockets (drop cache entries when FDs disappear).
   - For sockets lacking counters (e.g. UNIX domain), return zero without raising errors.

### Sysctl Optimization Strategy
- **Buffer Reuse**: Persist an `UnsafeMutableRawPointer` sized from the last successful call; only allocate when the process table grows.
- **Refresh Throttling**: Separate host-level metrics (2 s cadence) from process-heavy refresh (5 s default) and allow future configuration.
- **Change Detection**: Track `kinfo_proc` generation numbers; skip full recomputation when PID set remains unchanged between intervals (update CPU/RAM via cached `proc_pidinfo` without rerunning `sysctl`).

### Public API Adjustments
- Extend `ProcessInfo` with:
  - `residentBytes: UInt64`
  - `commandLine: String`
  - `username: String`
  - `cpuInstantPercent: Double`
  - `diskReadBytesPerSecond`, `diskWriteBytesPerSecond`
  - `networkInBytesPerSecond`, `networkOutBytesPerSecond`
- Preserve existing computed properties (`isHighCPU`, etc.) while migrating UI to new fields.
- Expose `ProcessCollector` from `SystemStats` with methods:
  - `snapshotProcesses() -> [ProcessInfo]`
  - `snapshotHost() -> HostMetrics`
  - `invalidateCache(for pid: Int32)` (used when killing a process).

### Bridging Considerations
- Implement a small C helper in the bridging header to wrap `sysctl` + `proc_pidinfo` interactions for Swift-friendly consumption.
- Ensure thread safety by confining collector mutation to a serial DispatchQueue.
- Guard expensive calls (`proc_pidinfo`) behind `task_for_pid` entitlements checks; fall back to zeroed metrics if permission is denied.

## Testing Strategy
- **Unit Tests** (`Tests/SystemMonitorTests/ProcessCollectorTests.swift`):
  - Mock host tick data to verify CPU delta math.
  - Simulate `NetworkSnapshot` cache updates ensuring closed sockets are handled.
  - Confirm command line caching survives repeated snapshots.
- **Manual Runs**:
  - `swift run SystemMonitor` under idle and stress conditions (`python3 cpu_stress_test.py`).
  - Compare metrics with `btop` and Activity Monitor for representative processes (browser, IDE, background agents).
  - Validate per-PID network counters against `nettop` for TCP-heavy workloads.

## Rollout Plan
1. Land collector scaffolding and host metric migration behind a feature flag (`SystemStats.useNativeCollector`).
2. Switch DetailView to consume the new collector while keeping legacy fields populated for validation.
3. Remove `ps`/`nettop` dependencies once parity is confirmed.
4. Document manual verification steps in `UPDATE_NOTES.md` and ready the tree for packaging.

## Risks & Mitigations
- **Permission Failures**: Some daemons may block `proc_pidinfo`; handle with default values and log once per PID.
- **Socket Enumeration Cost**: Iterating descriptors can be expensive for servers with many connections. Mitigate by caching the fd list across refreshes and capping per-sample iteration time with cooperative yielding.
- **API Stability**: `proc_pidinfo` and socket counters are private-ish but ship in the public SDK; monitor for signature changes across macOS releases and gate features with availability checks.

## Open Questions
- Should network sampling fallback to `nettop` for protocols where `proc_pidfdinfo` yields zero counters?
- Do we expose configuration to relax refresh cadences for low-power modes?
- How should we store long command lines to avoid excessive memory usage (e.g. impose 4 KB cap)?
