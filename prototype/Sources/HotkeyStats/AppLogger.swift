import Foundation

/// 状态事件使用固定文本；快捷键调试仅输出已经通过输入过滤的组合键名称。
final class AppLogger {
    enum Level: String, CaseIterable { case debug = "DEBUG", info = "INFO", warning = "WARNING", error = "ERROR" }
    enum Event: String {
        case started = "Application started", stopped = "Application stopped"
        case permissionMissing = "Keyboard monitoring permission missing"
        case monitorStarted = "Keyboard monitor started", monitorFailed = "Keyboard monitor creation failed"
        case monitorRecovered = "Keyboard monitor re-enabled"
        case saveFailed = "Statistics save failed", backupFailed = "Migration backup failed"
        case paused = "Monitoring paused", running = "Monitoring running"
        case monitoringFailed = "Monitoring unavailable"
        case pauseRequested = "Pause requested", resumeRequested = "Resume requested"
        case monitorStopped = "Keyboard monitor stopped", sourceFailed = "RunLoop source creation failed"
        case recordsMissing = "Statistics file unavailable", decodeFailed = "Statistics decode failed"
        case recordsLoaded = "Statistics loaded", recordsSaved = "Statistics saved"
        case recordsCleared = "Statistics cleared", saveBlocked = "Statistics save blocked to protect original file"
        case migrationStarted = "Statistics migration started", migrationFinished = "Statistics migration finished"
        case directoryFailed = "Statistics directory creation failed"
        case loginEnabled = "Login launch registered", loginDisabled = "Login launch unregistered"
        case loginApproval = "Login launch requires approval", loginFailed = "Login launch update failed"
        case duplicateInstance = "Duplicate instance rejected", lockFailed = "Instance lock acquisition failed"
        case unsupportedSchema = "Unsupported statistics schema"
    }
    static let shared = AppLogger()
    private let queue = DispatchQueue(label: "HotkeyStats.logger")
    private let directory: URL
    private let maxBytes: Int
    private let retentionDays: Int
    private let clock: () -> Date
    private let fallback: () -> Void

    /// Prefer the checkout for local debugging; never write inside an installed app bundle.
    static func logDirectory(sourcePath: String, override: String?) -> URL {
        if let override, override.hasPrefix("/") { return URL(fileURLWithPath: override) }
        let source = URL(fileURLWithPath: sourcePath)
        if FileManager.default.fileExists(atPath: source.path) {
            return source.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("logs")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HotkeyStats")
    }

    init(directory: URL = AppLogger.logDirectory(sourcePath: #filePath,
             override: ProcessInfo.processInfo.environment["HOTKEYSTATS_LOG_DIR"]),
         maxBytes: Int = 10 * 1024 * 1024, retentionDays: Int = 30,
         clock: @escaping () -> Date = Date.init,
         fallback: @escaping () -> Void = { NSLog("[HotkeyStats] diagnostic log write failed") }) {
        self.directory = directory
        self.maxBytes = max(0, maxBytes)
        self.retentionDays = max(1, retentionDays)
        self.clock = clock
        self.fallback = fallback
    }

    func log(_ level: Level, _ event: Event) {
        enqueue(level, message: event.rawValue)
    }

    /// 仅在快捷键实际计数后调用；转义控制字符，防止一条事件伪造多行日志。
    func logHotkey(_ combo: String) {
        enqueue(.debug, message: "Hotkey counted: " + String(combo.prefix(64)).debugDescription)
    }

    private func enqueue(_ level: Level, message: String) {
        let date = clock()
        queue.async { self.write(level, message: message, date: date) }
    }

    /// Call from outside the logger queue, including application termination.
    func flush() { queue.sync {} }

    private func write(_ level: Level, message: String, date: Date) {
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            formatter.dateFormat = "yyyy-MM-dd"
            let day = formatter.string(from: date)
            // Only exact daily names owned by this module are eligible for cleanup.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = formatter.timeZone
            let cutoff = calendar.date(byAdding: .day, value: -(retentionDays - 1), to: calendar.startOfDay(for: date))!
            for file in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
                let name = file.deletingPathExtension().lastPathComponent
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if file.pathExtension == "log", let stamp = formatter.date(from: name),
                   formatter.string(from: stamp) == name, stamp < cutoff,
                   values.isRegularFile == true, values.isSymbolicLink != true {
                    try fm.removeItem(at: file)
                }
            }
            let file = directory.appendingPathComponent(day + ".log")
            if !fm.fileExists(atPath: file.path) {
                try Data().write(to: file, options: .withoutOverwriting)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
            let data = Data("[\(formatter.string(from: date))] [\(level.rawValue)] \(message)\n".utf8)
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            if size <= UInt64(maxBytes), data.count <= maxBytes - Int(size) {
                try handle.write(contentsOf: data)
            }
        } catch { fallback() }
    }
}
