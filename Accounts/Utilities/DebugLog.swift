import Foundation

enum DebugLog {
    private static let logURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Accounts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    static func write(_ message: String) {
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
        try? FileManager.default.removeItem(at: logURL)
    }

    static var path: String { logURL.path }
}
