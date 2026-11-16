import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// A connection to systemd-journald's native protocol socket.
///
/// Each entry is one datagram of `FIELD=value` lines (values containing a
/// newline use the binary form: name, newline, little-endian 64-bit length,
/// value, newline), as documented in systemd's "Native Journal Protocol".
/// Using the socket directly keeps libsystemd out of the build.
final class JournalConnection: Sendable {
    static let socketPath = "/run/systemd/journal/socket"

    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

    /// Opens the socket, or returns nil when journald is not running.
    static func open() -> JournalConnection? {
        #if os(Linux)
        guard FileManager.default.fileExists(atPath: socketPath) else { return nil }
        let descriptor = socket(AF_UNIX, Int32(SOCK_DGRAM.rawValue) | Int32(SOCK_CLOEXEC.rawValue), 0)
        guard descriptor >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        let path = Array(socketPath.utf8)
        guard path.count < capacity else {
            close(descriptor)
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path)
            buffer[path.count] = 0
        }
        // Connecting fixes the destination, so `send` can be used from any
        // thread without sharing an address buffer.
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }
        return JournalConnection(descriptor: descriptor)
        #else
        return nil
        #endif
    }

    /// Sends one entry. Returns false when journald refused it (for example
    /// an entry larger than a datagram), so the caller can fall back.
    func send(_ fields: [(String, String)]) -> Bool {
        let datagram = Self.encode(fields)
        let sent = datagram.withUnsafeBytes { buffer in
            #if canImport(Glibc)
            Glibc.send(descriptor, buffer.baseAddress, buffer.count, Int32(MSG_NOSIGNAL))
            #elseif canImport(Musl)
            Musl.send(descriptor, buffer.baseAddress, buffer.count, Int32(MSG_NOSIGNAL))
            #else
            Darwin.send(descriptor, buffer.baseAddress, buffer.count, 0)
            #endif
        }
        return sent == datagram.count
    }

    /// Field names must be uppercase ASCII letters, digits and underscores,
    /// not starting with an underscore (those are trusted, journald-set fields).
    static func encode(_ fields: [(String, String)]) -> [UInt8] {
        var datagram: [UInt8] = []
        for (name, value) in fields {
            let name = sanitizedFieldName(name)
            let bytes = Array(value.utf8)
            datagram += Array(name.utf8)
            if bytes.contains(0x0a) {
                datagram.append(0x0a)
                var length = UInt64(bytes.count).littleEndian
                withUnsafeBytes(of: &length) { datagram += $0 }
                datagram += bytes
            } else {
                datagram.append(UInt8(ascii: "="))
                datagram += bytes
            }
            datagram.append(0x0a)
        }
        return datagram
    }

    static func sanitizedFieldName(_ name: String) -> String {
        var result = String(name.uppercased().map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "_"
        })
        while result.hasPrefix("_") { result.removeFirst() }
        return result.isEmpty ? "FIELD" : String(result.prefix(64))
    }
}

enum StandardError {
    static var isTerminal: Bool { isatty(2) == 1 }

    /// One `write(2)` per line, so lines from different threads do not
    /// interleave.
    static func write(_ line: String) {
        let bytes = Array(line.utf8)
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                #if canImport(Glibc)
                let written = Glibc.write(2, base + offset, buffer.count - offset)
                #elseif canImport(Musl)
                let written = Musl.write(2, base + offset, buffer.count - offset)
                #else
                let written = Darwin.write(2, base + offset, buffer.count - offset)
                #endif
                guard written > 0 else { return }
                offset += written
            }
        }
    }
}
