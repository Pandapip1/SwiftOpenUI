import Foundation
import Synchronization
import CHelperProcessSandbox
#if canImport(Glibc)
import Glibc
#endif
#if os(macOS)
import XPC
#endif

/// A helper process of the app: started on demand, spoken to over a byte stream, and killable at
/// any moment (a helper that overruns is ended, with everything running in it). One API on every
/// platform; what each offers:
///
/// | platform | the app's helper (`Launcher.app`) |
/// |---|---|
/// | macOS | the app's bundled XPC service, one instance per connection (its Info.plist sets `_MultipleInstances`), handed one end of a socket pair |
/// | Linux | the app's own executable, run with the given arguments; stdin/stdout carry the stream |
/// | iOS, iPadOS, tvOS, visionOS | none: apps cannot start processes |
///
/// `Launcher.executable` runs a given helper executable as a child process where processes can be
/// started (macOS and Linux), for tests and development builds.
public enum HelperProcess {
    /// The app's end of a running helper.
    public struct Connection: Sendable {
        /// Descriptors the app reads from and writes to (the same socket for an XPC service).
        public let readFD: Int32
        public let writeFD: Int32
        /// The helper's process ID where known, else 0.
        public let pid: Int32
        /// Ends the helper at once (SIGKILL); safe to call more than once.
        public let kill: @Sendable () -> Void
    }

    public struct LaunchFailure: Error, CustomStringConvertible, Sendable {
        public let description: String
    }

    /// The key under which an XPC helper receives its end of the socket pair, in the one message
    /// the app sends it (the XPC service reads it with `xpc_dictionary_dup_fd`).
    public static let xpcChannelKey = "channel"

    /// How a helper is started.
    public struct Launcher: Sendable {
        enum Kind: Sendable {
            case xpcService(name: String)
            case executable(URL, arguments: [String])
        }
        let kind: Kind

        /// The app's own helper, where the platform can start one (see `HelperProcess`): on macOS the
        /// XPC service `<bundle id>.<serviceBundleName>` when the bundle carries it; on Linux the
        /// app's executable run with `arguments`. Nil elsewhere, and on macOS when the bundle has no
        /// such service (SwiftPM and xtool builds).
        public static func app(serviceBundleName: String, arguments: [String], bundle: Bundle = .main) -> Launcher? {
            #if os(macOS)
            let service = bundle.bundleURL.appendingPathComponent("Contents/XPCServices/\(serviceBundleName).xpc")
            guard let identifier = bundle.bundleIdentifier, FileManager.default.fileExists(atPath: service.path) else {
                return nil
            }
            return Launcher(kind: .xpcService(name: "\(identifier).\(serviceBundleName)"))
            #elseif os(Linux)
            return Launcher(kind: .executable(URL(fileURLWithPath: "/proc/self/exe"), arguments: arguments))
            #else
            return nil
            #endif
        }

        /// `executable` run as a child process with `arguments`, with an empty environment and
        /// nothing on stderr. Nil where processes cannot be started.
        public static func executable(_ executable: URL, arguments: [String]) -> Launcher? {
            #if os(macOS) || os(Linux)
            return Launcher(kind: .executable(executable, arguments: arguments))
            #else
            return nil
            #endif
        }

        public func launch() throws -> Connection {
            switch kind {
            case .xpcService(let name): return try Self.launchXPCService(name)
            case .executable(let url, let arguments): return try Self.launchChild(url, arguments: arguments)
            }
        }

        private static func launchXPCService(_ name: String) throws -> Connection {
            #if os(macOS)
            var fds: [Int32] = [-1, -1]
            guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
                throw LaunchFailure(description: "socketpair failed (\(errno))")
            }
            // A helper that went away must not take the app down with SIGPIPE.
            var on: Int32 = 1
            _ = setsockopt(fds[0], SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let connection = xpc_connection_create(name, nil)
            xpc_connection_set_event_handler(connection) { _ in }
            xpc_connection_resume(connection)
            let message = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_fd(message, HelperProcess.xpcChannelKey, fds[1])
            xpc_connection_send_message(connection, message)
            close(fds[1])
            let held = Mutex<xpc_connection_t?>(connection)
            return Connection(readFD: fds[0], writeFD: fds[0], pid: 0) {
                guard let connection = held.withLock({ value -> xpc_connection_t? in
                    defer { value = nil }
                    return value
                }) else { return }
                let pid = xpc_connection_get_pid(connection)
                if pid > 0 { _ = Foundation.kill(pid, SIGKILL) }
                xpc_connection_cancel(connection)
            }
            #else
            throw LaunchFailure(description: "XPC services exist only on macOS")
            #endif
        }

        private static func launchChild(_ executable: URL, arguments: [String]) throws -> Connection {
            #if os(macOS) || os(Linux)
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            // Nothing of the app's environment: a helper needs none, and secrets must not leak into it.
            process.environment = [:]
            let toHelper = Pipe(), fromHelper = Pipe()
            process.standardInput = toHelper
            process.standardOutput = fromHelper
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { throw LaunchFailure(description: "\(error)") }
            // The connection owns duplicates of the app's two pipe ends; the Pipe and Process objects
            // (and the child's ends, which only the child needs) go away with this scope.
            let readFD = dup(fromHelper.fileHandleForReading.fileDescriptor)
            let writeFD = dup(toHelper.fileHandleForWriting.fileDescriptor)
            guard readFD >= 0, writeFD >= 0 else { throw LaunchFailure(description: "dup failed (\(errno))") }
            let pid = process.processIdentifier
            let once = Mutex(false)
            return Connection(readFD: readFD, writeFD: writeFD, pid: pid) {
                guard once.withLock({ done in defer { done = true }; return !done }) else { return }
                _ = Foundation.kill(pid, SIGKILL)
                // Reap it, so a killed helper never lingers as a zombie.
                DispatchQueue.global(qos: .utility).async {
                    var status: Int32 = 0
                    _ = waitpid(pid, &status, 0)
                }
            }
            #else
            throw LaunchFailure(description: "This platform cannot start processes")
            #endif
        }
    }

    /// The helper's side, first thing in its main: closes every descriptor it inherited except
    /// stdin, stdout and stderr, and confines the process where the platform allows it (Linux: no
    /// new privileges, and a seccomp filter refusing sockets, exec, ptrace and file creation or
    /// writing). An XPC service is already confined by its own sandbox. Returns whether a
    /// confinement was installed here.
    @discardableResult
    public static func confineCurrentProcess() -> Bool {
        for fd in Int32(3)..<Int32(1024) { _ = close(fd) }
        return sou_helper_process_confine() == 0
    }
}
