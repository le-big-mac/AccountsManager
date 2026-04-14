import Foundation

enum PersistentStoreBackup {
    private static let maxBackupCount = 20

    static func backupDefaultStore() {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let storeURL = applicationSupport.appendingPathComponent("default.store")

        guard fileManager.fileExists(atPath: storeURL.path),
              (try? storeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 else {
            DebugLog.write("SwiftData store backup skipped: no existing default.store")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let backupRoot = applicationSupport
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent("Store Backups", isDirectory: true)
        let backupDirectory = backupRoot
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let source = applicationSupport.appendingPathComponent("default.store\(suffix)")
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = backupDirectory.appendingPathComponent(source.lastPathComponent)
                try fileManager.copyItem(at: source, to: destination)
            }

            try pruneBackups(in: backupRoot, fileManager: fileManager)
            DebugLog.write("SwiftData store backed up to \(backupDirectory.path)")
        } catch {
            DebugLog.write("SwiftData store backup failed: \(error.localizedDescription)")
        }
    }

    private static func pruneBackups(in backupRoot: URL, fileManager: FileManager) throws {
        guard let backups = try? fileManager.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let sortedBackups = backups.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        for backup in sortedBackups.dropFirst(maxBackupCount) {
            try fileManager.removeItem(at: backup)
        }
    }
}
