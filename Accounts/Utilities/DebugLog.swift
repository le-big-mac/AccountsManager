import Foundation

enum DebugLog {
    #if DEBUG
    private static let enabled = ProcessInfo.processInfo.environment["ACCOUNTS_DEBUG_LOG"] == "1"
    #else
    private static let enabled = false
    #endif

    private static let logURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Accounts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    static func write(_ message: String) {
        guard enabled else { return }
        let entry = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = entry.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logURL)
        }
    }

    static func clear() {
        guard enabled else { return }
        try? FileManager.default.removeItem(at: logURL)
    }

    static var path: String { logURL.path }
}
