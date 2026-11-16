import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// When this process started, for launch timing.
public enum ProcessLaunch {
/// Milliseconds since this process started, including the time before
    /// `main` (loading and linking); -1 where the start time is unknown.
    nonisolated public static func elapsedMilliseconds() -> Int {
        guard let start = startTime() else { return -1 }
        return Int(((Date().timeIntervalSince1970 - start) * 1_000).rounded())
    }

    nonisolated private static func startTime() -> TimeInterval? {
        #if canImport(Darwin)
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        return Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
        #elseif os(Linux)
        // Field 22 of /proc/self/stat is the start time in clock ticks after
        // boot; the boot time is the btime line of /proc/stat.
        guard let stat = try? String(contentsOfFile: "/proc/self/stat", encoding: .utf8),
              let close = stat.lastIndex(of: ")") else { return nil }
        let fields = stat[stat.index(after: close)...].split(separator: " ")
        guard fields.count > 19, let ticks = Double(fields[19]),
              let proc = try? String(contentsOfFile: "/proc/stat", encoding: .utf8),
              let line = proc.split(separator: "\n").first(where: { $0.hasPrefix("btime ") }),
              let boot = Double(line.dropFirst(6)) else { return nil }
        return boot + ticks / Double(sysconf(Int32(_SC_CLK_TCK)))
        #else
        return nil
        #endif
    }
}
