# Design-001: Native Process Metrics Collector

- Related RFC: [RFC-001: Native macOS Process Metric Collector](../RFCs/RFC-001-native-process-metrics.md)
- Status: Draft
- Authors: Codex
- Updated: 2024-05-25

## Overview
This design describes the implementation plan that realizes RFC-001. The deliverable is a native macOS metrics pipeline that replaces external tools (`ps`, `nettop`) with SDK calls while preserving current UI behaviour and adding higher-fidelity CPU, memory, disk, and network data per process.

Key principles:
- Perform work on a dedicated collector queue, never from the main thread.
- Cache kernel snapshots to avoid repeated allocations and reduce `sysctl` pressure.
- Provide deterministic data models so SwiftUI rendering can stay unchanged except for reading new fields.

## Components
- `ProcessCollector` (Swift class) orchestrating snapshots and caches.
- `ProcessSnapshot` / `HostSnapshot` value types capturing individual refresh results.
- `ProcessCache` (struct) storing per-PID historical counters and metadata.
- `NativeProcessCollector.c` helpers exposed through `SystemMonitor-Bridging-Header.h` for raw syscalls.
- Updated `SystemStats` facade returning data to both menu bar and DetailView.

## Data Flow
1. `SystemStats` schedules `ProcessCollector.snapshot()` on the serial `collectorQueue`.
2. The collector imports the latest `kinfo_proc` array via `sysctl`. Buffer reuse and generation checks determine whether follow-up `proc_pidinfo` calls are needed.
3. For each active PID the collector gathers runtime counters, IO totals, socket metrics, command lines, users, and builds `ProcessInfo` models.
4. Snapshots are published back to the main queue. UI sorts, filters, and renders as before.

```
Timer -> SystemStats -> ProcessCollector (queue)
        |                                   |
        |                        Native C helpers (sysctl/libproc)
        |                                   |
        +--> HostSnapshot -------------------+
                |                            
                +--> ProcessInfo array -> UI
```

## Detailed Design
### 1. Collector Queue & Scheduling
- Add `collectorQueue = DispatchQueue(label: "com.systemmonitor.collector", qos: .userInitiated)`.
- Host metrics refresh: 2 s cadence.
- Process metrics refresh: 5 s cadence (configurable). If a manual refresh is requested (search, kill), allow opportunistic 2 s updates but throttle via `DispatchWorkItem` cancellation.

### 2. Sysctl Interaction
- New helper `size_t sm_kern_proc_list(void *buffer, size_t *length);` returns required bytes when buffer too small (`ENOMEM`).
- Persist `UnsafeMutableRawPointer processListBuffer` and `size_t processListCapacity` inside `ProcessCollector`.
- On each refresh:
  1. Call helper with the existing buffer.
  2. If return indicates `needs_resize`, double capacity and retry (bounded by 64 MB to guard runaway allocation).
  3. Extract `generation_id` (use `kinfo_proc.kp_proc.p_flag` + `kp_proc.p_comm` snapshot) to detect unchanged lists.
- When `generation_id` matches previous sample, skip `sysctl` and rely on cached PIDs, but still update per-PID counters via `proc_pidinfo` to keep CPU/memory fresh.

### 3. Process Cache
Structure per PID:
```
struct CachedProcess {
    rusage_info_v6 lastRusage;
    proc_taskinfo lastTaskInfo;
    timeval lastSampleTime;
    uint64_t lastHostTicks;
    uint64_t lastUserTicks;
    uint64_t lastSystemTicks;
    std::string commandLine;
    std::string userName;
    std::vector<int32_t> cachedFds;
    std::unordered_map<int32_t, SocketSnapshot> socketBytes;
}
```
- Implemented in Swift as class/struct bridging to C arrays. `commandLine` fetched only once and stored.
- When a PID disappears, remove from cache and release memory.
- Provide cap on cached command length (4 KB) to avoid pathological memory retention.

### 4. Host CPU Statistics
- Use `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` and accumulate totals per core.
- Store previous totals inside `ProcessCollector`. On each refresh compute delta ticks and `hostDeltaSeconds` using `mach_timebase_info` conversions.
- Deliver overall CPU ratio plus per-core data for future use (optional).

### 5. Per-PID CPU Calculation
```
let taskInfo = proc_pidinfo(pid, PROC_PIDTASKINFO, ...)
let userDelta = (taskInfo.pti_total_user - cached.lastTaskInfo.pti_total_user)
let systemDelta = (taskInfo.pti_total_system - cached.lastTaskInfo.pti_total_system)
let total = Double(userDelta + systemDelta) / hostDeltaTicks
let percent = min(max(total * 100.0 * coreCount, 0), coreCount * 100)
```
- Cache last task info per PID. If `proc_pidinfo` fails (permissions), reuse cached values and set percent to 0 with `ProcessInfo.flags` indicating partial data.

### 6. Memory Metrics
- Convert `pti_resident_size` to bytes and compute `%` via `resident / totalPhysicalMemory`.
- Keep `pti_virtual_size` for potential future use but do not surface yet.

### 7. Disk Throughput
- Use `proc_pid_rusage(pid, RUSAGE_INFO_V6, ...)` to read cumulative `ri_diskio_bytes{read, written}`.
- Compare with cached values to produce per-second rates: `(delta / elapsed)`.
- Also capture `ri_logical_writes` to augment disk write metrics (exposed as `logicalWriteBytesPerSecond`).

### 8. Per-PID Network Measurement
- Step 1: gather file descriptors with `proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer, ...)`. Cache `fd` list per PID to avoid full re-enumeration when unchanged (compare counts + `proc_fdinfo` metadata).
- Step 2: for each `proc_fdinfo` where `proc.fdinfo.fi_type == PROX_FDTYPE_SOCKET`, call `proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &socketInfo, ...)`.
  - For TCP sockets: use `socketInfo.psi.soi_proto.pri_tcp.tcpsi_state.tcpi_bytes_in/out`.
  - For UDP sockets: use `socketInfo.psi.soi_proto.pri_in.insi_flow.hash`, if counters absent fall back to `socketInfo.psi.soi_stat.sb_cc` deltas.
- Maintain `SocketSnapshot { UInt64 bytesIn; UInt64 bytesOut; }` per `(pid, fd)` pair.
- Aggregate totals per PID; compute rates via `elapsedSeconds`.
- When `proc_pidfdinfo` fails (e.g., due to permission or closed socket), purge that fd from cache.
- Expose totals in `ProcessInfo.networkInBytesPerSecond` / `networkOutBytesPerSecond`.

### 9. Command Line & Username Caching
- Use helper `sm_copy_proc_args(pid, buffer, length)` wrapping `sysctl KERN_PROCARGS2` to populate a Swift `String` (UTF-8). Keep the first argument (binary path) to use when arguments missing.
- Cache UID→username lookups using `getpwuid_r` inside helper to avoid repeated `getpwuid` (non-thread-safe).

### 10. Swift Data Model Changes
`ProcessInfo` becomes (simplified):
```swift
struct ProcessInfo: Identifiable {
    let pid: Int32
    let parentPid: Int32
    let name: String
    let commandLine: String
    let username: String
    let cpuInstantPercent: Double
    let cpuCumulativePercent: Double
    let residentBytes: UInt64
    let memoryPercent: Double
    let threadCount: Int
    let networkInBytesPerSecond: Double
    let networkOutBytesPerSecond: Double
    let diskReadBytesPerSecond: Double
    let diskWriteBytesPerSecond: Double
    let logicalWriteBytesPerSecond: Double
    let flags: ProcessFlags
}
```
`ProcessFlags` is an `OptionSet` to mark partial data (`.cpuRestricted`, `.networkUnavailable`). The UI can continue to compute `isHighCPU` etc. from these fields.

### 11. Bridging Layer
- New C file `Sources/SystemMonitor/NativeProcessCollector.c` exposing:
  - `int sm_list_pids(struct sm_pid_buffer *buffer);`
  - `int sm_fetch_taskinfo(pid_t pid, struct proc_taskinfo *out);`
  - `int sm_fetch_rusage(pid_t pid, rusage_info_v6 *out);`
  - `int sm_fetch_fdinfo(pid_t pid, struct sm_fdinfo_buffer *out);`
  - `int sm_fetch_socketinfo(pid_t pid, int fd, struct socket_fdinfo *out);`
  - `int sm_fetch_command(pid_t pid, char *buffer, size_t length);`
  - `int sm_lookup_username(uid_t uid, char *buffer, size_t length);`
- Wrap `malloc`/`free` behind Swift-friendly helpers. Swift retains ownership of buffers and ensures deallocation.

### 12. Concurrency & Error Handling
- All collector work occurs on `collectorQueue`.
- Log (`os_log`) warnings on first failure per PID to avoid spam. Keep counters for diagnostics.
- If any step fails catastrophically (e.g., `sysctl` returns EPERM), surface an empty array plus an error state so UI can notify users.

## Implementation Steps
1. Scaffold `ProcessCollector` with host CPU + memory sampling and caching infrastructure.
2. Add C helpers and bridging wrappers; verify they compile in Swift Package target.
3. Implement PID snapshot + task info + command caching.
4. Layer in disk IO deltas using `rusage_info_v6`.
5. Implement per-PID network aggregation; gate behind compile-time flag until validated.
6. Update `SystemStats` and `SystemStatsObservable` to use new collector, but keep legacy fields populated for comparisons during rollout.
7. Remove `ps`/`nettop` code once parity tests pass.

## Testing Plan
- **Unit Tests**: add `ProcessCollectorTests` covering CPU delta logic, cache eviction, and socket aggregation using injected mock helpers.
- **Integration Tests**: create a runtime test harness that spawns synthetic CPU/network/disk loads and asserts expected deltas within tolerance.
- **Manual Verification**: compare outputs with `btop` and `nettop` for diverse workloads; validate command lines shown in UI.
- **Performance Regression**: instrument collector queue to measure time spent per refresh; ensure 95th percentile < 50 ms when < 300 processes.

## Deployment & Rollback
- Guard new collector behind `SystemStatsConfiguration.useNativeCollector` (default on in debug builds, off in release until validated).
- Provide fallback path (legacy collector) triggered by runtime flag or detection of repeated failures.
- Document release validation steps in `UPDATE_NOTES.md`.

## Risks & Mitigations
- **Permission Denial**: handle `EPERM` gracefully by zeroing metrics; surface `ProcessFlags` to UI.
- **High FD Counts**: limit per-process network inspection time (e.g., inspect at most 256 sockets per refresh, round-robin across calls).
- **API Changes**: wrap all private structure access with availability checks and fail-safe defaults for older macOS releases.

## Open Questions
- Do we expose configuration to cap command line length per user preferences?
- Should network sampling downgrade to the legacy `nettop` path when socket counters are unavailable?
- How aggressively should we recycle socket snapshots to balance accuracy and CPU usage?
