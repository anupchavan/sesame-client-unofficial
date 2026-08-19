import Foundation

/// Lightweight file logger (~/Library/Logs/Sesame.log). Frame-level logging only when
/// SESAME_DEBUG=1; errors and state changes always.
enum WSLog {
    static let verbose = ProcessInfo.processInfo.environment["SESAME_DEBUG"] == "1"
    private static let queue = DispatchQueue(label: "wslog", qos: .utility)
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Sesame.log")
    }()

    static func log(_ line: @autoclosure () -> String, always: Bool = false) {
        guard verbose || always else { return }
        let s = "\(ISO8601DateFormatter().string(from: Date())) \(line())\n"
        queue.async {
            if let h = try? FileHandle(forWritingTo: url) {
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: Data(s.utf8))
                try? h.close()
            } else {
                try? Data(s.utf8).write(to: url)
            }
        }
    }
}
