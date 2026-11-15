import Foundation

/// A secret held in protected memory for its whole lifetime.
///
/// The bytes live in a dedicated allocation that is locked into RAM, kept
/// between inaccessible guard pages and made inaccessible itself whenever no
/// `withUnsafeBytes` call is running (libsodium's `sodium_malloc` on Linux,
/// the equivalent `mmap`/`mprotect`/`mlock` layout on Apple platforms). The
/// bytes are wiped when the object is deallocated.
///
/// The contents are fixed once initialised, so a `SecureBytes` may be shared
/// freely between threads and values. Read it only through
/// ``withUnsafeBytes(_:)`` and never let the buffer escape the closure.
/// Nothing converts it to `Data` or `String` implicitly: the
/// `unsafeUnprotected…` methods are the explicit, greppable places where
/// protection ends. `description`, `debugDescription` and reflection are
/// redacted so secrets don't reach logs through string interpolation.
///
/// `@unchecked Sendable`: the only mutable state is `activeReaders`, which is
/// read and written only while holding `lock`. The region's pointer and
/// count never change after `init`, and its bytes are never written after
/// `init` returns, so concurrent readers are safe. The pointer type itself is
/// not `Sendable`, which is why the conformance can't be checked.
public final class SecureBytes: @unchecked Sendable {
    private let region: ProtectedRegion
    private let lock = NSLock()
    private var activeReaders = 0

    /// Allocates `count` bytes of protected memory and lets `initializer`
    /// fill them. If `initializer` throws, the memory is wiped and released.
    public init(
        count: Int,
        initializingWith initializer: (UnsafeMutableRawBufferPointer) throws -> Void
    ) rethrows {
        let region = ProtectedRegion.allocate(count: count)
        region.wipe()
        do {
            try initializer(UnsafeMutableRawBufferPointer(start: region.start, count: count))
        } catch {
            region.release()
            throw error
        }
        region.makeInaccessible()
        self.region = region
    }

    /// Copies `bytes` into protected memory. The source is left untouched;
    /// wipe it yourself if you own it.
    public convenience init(copying bytes: UnsafeRawBufferPointer) {
        self.init(count: bytes.count) { destination in
            destination.copyMemory(from: bytes)
        }
    }

    /// Copies `data` into protected memory and then zeroes `data` in place.
    ///
    /// Only the storage `data` refers to is wiped. If that storage is shared
    /// with another `Data` value, Swift copies it before the wipe and the
    /// original survives, so call this with a value nothing else holds (for
    /// example the fresh result of an encoder).
    public convenience init(wiping data: inout Data) {
        self.init(count: data.count) { destination in
            data.withUnsafeBytes { destination.copyMemory(from: $0) }
        }
        data.withUnsafeMutableBytes { ProtectedRegion.wipe($0.baseAddress, count: $0.count) }
    }

    /// Copies the UTF-8 form of `string` into protected memory.
    ///
    /// Swift strings are immutable and cannot be wiped, so the caller's
    /// string remains in ordinary memory until it is released. Use this
    /// where a secret necessarily arrives as a `String` (decoded from a
    /// network response, typed by the user, or in tests), as early as
    /// possible, and drop the string promptly.
    public convenience init(copyingUTF8 string: String) {
        var string = string
        self.init(count: string.utf8.count) { destination in
            string.withUTF8 { destination.copyMemory(from: UnsafeRawBufferPointer($0)) }
        }
    }

    deinit {
        region.release()
    }

    /// The number of bytes held. Lengths are not treated as secret.
    public var count: Int { region.count }

    public var isEmpty: Bool { region.count == 0 }

    /// Calls `body` with read-only access to the secret.
    ///
    /// The buffer is valid only inside `body` and becomes inaccessible
    /// afterwards; do not store it or any pointer derived from it.
    public func withUnsafeBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        lock.lock()
        if activeReaders == 0 { region.makeReadOnly() }
        activeReaders += 1
        lock.unlock()
        defer {
            lock.lock()
            activeReaders -= 1
            if activeReaders == 0 { region.makeInaccessible() }
            lock.unlock()
        }
        return try body(UnsafeRawBufferPointer(start: region.start, count: region.count))
    }

    /// Returns an ordinary, unprotected `Data` copy of the secret.
    ///
    /// Protection ends here: the copy is neither locked nor wiped. Use it
    /// only where an API outside your control requires `Data`, keep the
    /// copy's lifetime as short as possible and comment the call site.
    public func unsafeUnprotectedData() -> Data {
        withUnsafeBytes { Data($0) }
    }

    /// Returns an ordinary, unprotected `String` copy of the secret if it is
    /// valid UTF-8.
    ///
    /// Protection ends here: Swift strings cannot be locked or wiped. Use it
    /// only at the last moment an API requires a `String` (an HTTP header,
    /// a form field), keep the copy's lifetime as short as possible and
    /// comment the call site.
    public func unsafeUnprotectedString() -> String? {
        withUnsafeBytes { String(bytes: $0, encoding: .utf8) }
    }
}

extension SecureBytes: Equatable {
    /// Compares contents in time independent of where they differ.
    public static func == (lhs: SecureBytes, rhs: SecureBytes) -> Bool {
        if lhs === rhs { return true }
        return lhs.withUnsafeBytes { left in
            rhs.withUnsafeBytes { right in ProtectedRegion.constantTimeEqual(left, right) }
        }
    }
}

extension SecureBytes: Hashable {
    /// Hashes only the length, so contents never reach a hasher. Equal
    /// secrets have equal lengths, which is all `Hashable` requires.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(count)
    }
}

/// Lets crypto APIs that accept `ContiguousBytes` (CryptoKit, swift-crypto)
/// read the key material directly, without a `Data` copy.
extension SecureBytes: ContiguousBytes {}

extension SecureBytes: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "SecureBytes(\(count) bytes, redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .class) }
}
