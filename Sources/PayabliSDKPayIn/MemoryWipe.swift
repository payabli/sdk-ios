import Foundation

/// Overwrites bytes with `memset_s`, which the compiler may not remove. A zeroing loop or a plain `memset`
/// over memory that is dropped or freed right after is a dead store the optimizer is free to delete.
enum MemoryWipe {
    /// Overwrites every byte of `bytes` in place, keeping its count.
    ///
    /// - Parameter bytes: the bytes to overwrite.
    static func overwrite(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { overwrite($0) }
    }

    /// Overwrites every byte the pointer covers.
    ///
    /// - Parameter buffer: the memory to overwrite.
    static func overwrite(_ buffer: UnsafeMutableRawBufferPointer) {
        guard let base = buffer.baseAddress else { return }
        overwrite(base, count: buffer.count)
    }

    /// Overwrites `count` bytes from `pointer`.
    ///
    /// - Parameter pointer: the first byte to overwrite.
    /// - Parameter count: how many bytes to overwrite.
    static func overwrite(_ pointer: UnsafeMutableRawPointer, count: Int) {
        guard count > 0 else { return }
        _ = memset_s(pointer, count, 0, count)
    }
}
