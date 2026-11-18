import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The system resolver (getaddrinfo), returning raw address bytes: 4 for
/// IPv4, 16 for IPv6, in the resolver's order without duplicates. Callers
/// decide what the addresses are allowed to be; this only asks the system.
/// The socket constants differ between Darwin and Glibc, which is why this
/// lives here rather than in applications.
public enum HostAddressLookup {
    public struct Failure: LocalizedError, Sendable {
        public let host: String
        public var errorDescription: String? { "Could not find \(host)" }
        public init(host: String) { self.host = host }
    }

    /// Resolves `host` for a TCP connection to `port`. Blocking; call it off
    /// the main thread.
    public static func resolve(host: String, port: Int) throws -> [[UInt8]] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        #if canImport(Glibc) || canImport(Musl)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let first = result else {
            throw Failure(host: host)
        }
        defer { freeaddrinfo(first) }
        var out: [[UInt8]] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            if let sa = info.pointee.ai_addr {
                var bytes: [UInt8]?
                switch Int32(sa.pointee.sa_family) {
                case AF_INET:
                    bytes = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                        withUnsafeBytes(of: sin.pointee.sin_addr) { Array($0) }
                    }
                case AF_INET6:
                    bytes = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                        withUnsafeBytes(of: sin6.pointee.sin6_addr) { Array($0) }
                    }
                default:
                    bytes = nil
                }
                if let bytes, !out.contains(bytes) { out.append(bytes) }
            }
            cursor = info.pointee.ai_next
        }
        guard !out.isEmpty else { throw Failure(host: host) }
        return out
    }
}
