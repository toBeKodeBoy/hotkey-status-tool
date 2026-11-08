import AppKit
import CryptoKit

/// An absolute override permits isolated launches and portable local data without touching the default store.
enum DataLocation {
    static func reopenNotification(directory: URL) -> Notification.Name {
        let path = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return Notification.Name("local.HotkeyStats.reopen." + digest)
    }
    static func directory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["HOTKEYSTATS_DATA_DIR"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HotkeyStats", isDirectory: true)
    }
}

struct ApplicationBootstrap {
    var directory = DataLocation.directory()
    var acquire: (URL) throws -> InstanceLock? = { try InstanceLock(url: $0) }
    var createDirectory: (URL) throws -> Void = {
        try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
    }
    var announce: (URL) -> Void = { directory in
        DistributedNotificationCenter.default().postNotificationName(
            DataLocation.reopenNotification(directory: directory), object: nil, userInfo: nil, deliverImmediately: true)
    }
    var showError: () -> Void = {
        let alert = NSAlert()
        alert.messageText = "HotkeyStats 无法安全启动"
        alert.informativeText = "无法获取单实例锁。请检查应用支持目录的访问权限后重试。"
        alert.runModal()
    }
    var runApplication: () -> Void = {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    func run() -> Int32 {
        do {
            try createDirectory(directory)
            guard let lock = try acquire(directory.appendingPathComponent("instance.lock")) else {
                AppLogger.shared.log(.info, .duplicateInstance)
                AppLogger.shared.flush()
                // Allow a simultaneously starting primary to install its observer.
                for _ in 0..<5 { announce(directory); Thread.sleep(forTimeInterval: 0.1) }
                return 0
            }
            withExtendedLifetime(lock) { runApplication() }
            return 0
        } catch {
            AppLogger.shared.log(.error, .lockFailed)
            AppLogger.shared.flush()
            showError()
            return 1
        }
    }
}
