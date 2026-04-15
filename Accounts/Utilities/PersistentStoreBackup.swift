import Foundation

enum PersistentStoreBackup {
    private static let maxBackupCount = 20
    private static let storeBaseName = "Accounts.store"

    static var storeURL: URL {
        accountsApplicationSupport.appendingPathComponent(storeBaseName)
    }

    static func prepareStore() {
        migrateLegacyStoreIfNeeded()
        backupStore()
    }

    private static var rootApplicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    private static var accountsApplicationSupport: URL {
        rootApplicationSupport.appendingPathComponent("Accounts", isDirectory: true)
    }

    private static var legacyStoreURL: URL {
        rootApplicationSupport.appendingPathComponent("default.store")
    }

    private static func migrateLegacyStoreIfNeeded() {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: storeURL.path),
              fileManager.fileExists(atPath: legacyStoreURL.path),
              storeLooksLikeAccountsStore(legacyStoreURL) else {
            return
        }

        do {
            try fileManager.createDirectory(at: accountsApplicationSupport, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let source = rootApplicationSupport.appendingPathComponent("default.store\(suffix)")
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = accountsApplicationSupport.appendingPathComponent("\(storeBaseName)\(suffix)")
                try fileManager.copyItem(at: source, to: destination)
            }
            DebugLog.write("Migrated legacy SwiftData store to \(storeURL.path)")
        } catch {
            DebugLog.write("Legacy SwiftData store migration failed: \(error.localizedDescription)")
        }
    }

    private static func backupStore() {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: storeURL.path),
              (try? storeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 else {
            DebugLog.write("SwiftData store backup skipped: no existing \(storeBaseName)")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let backupRoot = accountsApplicationSupport.appendingPathComponent("Store Backups", isDirectory: true)
        let backupDirectory = backupRoot
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let source = accountsApplicationSupport.appendingPathComponent("\(storeBaseName)\(suffix)")
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = backupDirectory.appendingPathComponent("default.store\(suffix)")
                try fileManager.copyItem(at: source, to: destination)
            }

            try pruneBackups(in: backupRoot, fileManager: fileManager)
            DebugLog.write("SwiftData store backed up to \(backupDirectory.path)")
        } catch {
            DebugLog.write("SwiftData store backup failed: \(error.localizedDescription)")
        }
    }

    private static func storeLooksLikeAccountsStore(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = handle.readDataToEndOfFile()
        guard let contents = String(data: data, encoding: .isoLatin1) else { return false }
        return contents.contains("ZACCOUNT") && contents.contains("ZHOLDING")
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
