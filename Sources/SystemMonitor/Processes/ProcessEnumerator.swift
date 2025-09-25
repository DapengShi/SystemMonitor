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

import Foundation
import Darwin

protocol ProcessEnumeratorProtocol {
    func withProcessList<T>(_ body: (UnsafeBufferPointer<kinfo_proc>) throws -> T) rethrows -> T?
}

/// Handles sysctl-backed enumeration of processes while reusing allocation buffers.
final class ProcessEnumerator: ProcessEnumeratorProtocol {
    private var processListBuffer: UnsafeMutableRawPointer?
    private var processListCapacity: Int = 0
    private var processListLength: Int = 0

    deinit {
        processListBuffer?.deallocate()
    }

    func withProcessList<T>(_ body: (UnsafeBufferPointer<kinfo_proc>) throws -> T) rethrows -> T? {
        guard let buffer = fetchKinfoProcBuffer() else {
            return nil
        }
        let count = processListLength / MemoryLayout<kinfo_proc>.stride
        let typedPointer = buffer.bindMemory(to: kinfo_proc.self, capacity: count)
        let pointer = UnsafeBufferPointer(start: typedPointer, count: count)
        return try body(pointer)
    }

    private func fetchKinfoProcBuffer() -> UnsafeMutableRawPointer? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length: Int = 0
        let nameCount = UInt32(mib.count)
        let queryStatus = mib.withUnsafeMutableBufferPointer { ptr -> Int32 in
            sysctl(ptr.baseAddress, nameCount, nil, &length, nil, 0)
        }
        if queryStatus != 0 {
            return nil
        }

        if processListBuffer == nil || processListCapacity < length {
            allocateProcessBuffer(bytes: length)
        }

        var mutableLength = length
        let status = mib.withUnsafeMutableBufferPointer { ptr -> Int32 in
            sysctl(ptr.baseAddress, nameCount, processListBuffer, &mutableLength, nil, 0)
        }

        if status != 0 {
            return nil
        }

        processListLength = mutableLength
        return processListBuffer
    }

    private func allocateProcessBuffer(bytes: Int) {
        processListBuffer?.deallocate()
        let alignment = max(MemoryLayout<kinfo_proc>.alignment, MemoryLayout<Int>.alignment)
        processListBuffer = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: alignment)
        processListCapacity = bytes
        processListLength = bytes
    }
}
