#if os(Linux)
import CSodium
#elseif canImport(Darwin)
import Darwin
#endif

/// One allocation of protected memory and the platform calls that guard it.
///
/// - Linux: libsodium's `sodium_malloc`, which places the region between
///   inaccessible guard pages, `mlock`s it, excludes it from core dumps and
///   checks a canary on free. `sodium_free` zeroes it before unmapping.
/// - Apple platforms: the same layout built from `mmap`, `mprotect` and
///   `mlock` (libsodium isn't available to the Xcode build), wiped with
///   `memset_s`, which the compiler may not elide.
/// - Elsewhere: ordinary heap memory that is still wiped before it is freed.
///
/// In every case the bytes sit flush against the end of the usable region,
/// so on the guarded platforms an overrun faults on the trailing guard page.
/// Between accesses the data pages are made inaccessible.
struct ProtectedRegion {
    let start: UnsafeMutableRawPointer
    let count: Int
    #if !os(Linux) && canImport(Darwin)
    private let base: UnsafeMutableRawPointer
    private let dataPages: UnsafeMutableRawPointer
    private let dataLength: Int
    private let totalLength: Int
    #endif

    static func allocate(count: Int) -> ProtectedRegion {
        precondition(count >= 0, "SecureBytes cannot have a negative count")
        #if os(Linux)
        precondition(sodiumReady, "libsodium failed to initialise")
        // sodium_malloc(0) is valid but allocate at least one byte so the
        // returned pointer is always distinct and non-null.
        guard let start = sodium_malloc(Swift.max(count, 1)) else {
            fatalError("SecureBytes: sodium_malloc could not allocate \(count) bytes")
        }
        // sodium_malloc returns memory ending at the guard page only when
        // the requested size is used; with count 0 the one spare byte is
        // harmless.
        return ProtectedRegion(start: start, count: count)
        #elseif canImport(Darwin)
        let page = Int(getpagesize())
        let dataLength = (Swift.max(count, 1) + page - 1) / page * page
        let total = page + dataLength + page
        guard let base = mmap(nil, total, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0),
              base != MAP_FAILED else {
            fatalError("SecureBytes: mmap could not allocate \(count) bytes")
        }
        let dataPages = base + page
        // Leading and trailing guard pages.
        mprotect(base, page, PROT_NONE)
        mprotect(dataPages + dataLength, page, PROT_NONE)
        // Best effort: RLIMIT_MEMLOCK can refuse this, as libsodium tolerates.
        _ = mlock(dataPages, dataLength)
        return ProtectedRegion(
            start: dataPages + (dataLength - count), count: count, base: base,
            dataPages: dataPages, dataLength: dataLength, totalLength: total
        )
        #else
        let start = UnsafeMutableRawPointer.allocate(byteCount: Swift.max(count, 1), alignment: 16)
        return ProtectedRegion(start: start, count: count)
        #endif
    }

    func makeInaccessible() {
        #if os(Linux)
        _ = sodium_mprotect_noaccess(start)
        #elseif canImport(Darwin)
        mprotect(dataPages, dataLength, PROT_NONE)
        #endif
    }

    func makeReadOnly() {
        #if os(Linux)
        _ = sodium_mprotect_readonly(start)
        #elseif canImport(Darwin)
        mprotect(dataPages, dataLength, PROT_READ)
        #endif
    }

    func makeWritable() {
        #if os(Linux)
        _ = sodium_mprotect_readwrite(start)
        #elseif canImport(Darwin)
        mprotect(dataPages, dataLength, PROT_READ | PROT_WRITE)
        #endif
    }

    /// Zeroes the bytes. The region must be writable.
    func wipe() {
        Self.wipe(start, count: count)
    }

    /// Wipes and releases the region. The region must not be used afterwards.
    func release(beforeFree: (UnsafeRawBufferPointer) -> Void = { _ in }) {
        makeWritable()
        wipe()
        beforeFree(UnsafeRawBufferPointer(start: start, count: count))
        #if os(Linux)
        sodium_free(start)
        #elseif canImport(Darwin)
        Self.wipe(dataPages, count: dataLength)
        munlock(dataPages, dataLength)
        munmap(base, totalLength)
        #else
        start.deallocate()
        #endif
    }

    /// Zeroes `count` bytes at `pointer` in a way the optimiser keeps.
    static func wipe(_ pointer: UnsafeMutableRawPointer?, count: Int) {
        guard let pointer, count > 0 else { return }
        #if os(Linux)
        sodium_memzero(pointer, count)
        #elseif canImport(Darwin)
        _ = memset_s(pointer, count, 0, count)
        #else
        let bytes = pointer.bindMemory(to: UInt8.self, capacity: count)
        for index in 0..<count { withUnsafeMutablePointer(to: &bytes[index]) { $0.pointee = 0 } }
        #endif
    }

    /// Compares two buffers in time that depends only on their length.
    static func constantTimeEqual(_ lhs: UnsafeRawBufferPointer, _ rhs: UnsafeRawBufferPointer) -> Bool {
        guard lhs.count == rhs.count else { return false }
        guard let left = lhs.baseAddress, let right = rhs.baseAddress else { return true }
        #if os(Linux)
        return sodium_memcmp(left, right, lhs.count) == 0
        #else
        var difference: UInt8 = 0
        for index in 0..<lhs.count {
            difference |= left.load(fromByteOffset: index, as: UInt8.self)
                ^ right.load(fromByteOffset: index, as: UInt8.self)
        }
        return difference == 0
        #endif
    }
}

#if os(Linux)
/// `sodium_init` is idempotent and thread-safe; Swift runs this once.
private let sodiumReady: Bool = sodium_init() >= 0
#endif
