import Foundation

/// 统计存储：内存聚合 + JSON 持久化。
/// 事件回调跑在主 RunLoop 上，因此本类只在主线程使用。
final class StatsStore {

    static let shared = StatsStore()

    private(set) var records: [String: HotkeyRecord] = [:]

    /// 数据变更时通知 UI 刷新
    var onChange: (() -> Void)?

    private var unsavedCount = 0
    private let fileURL: URL
    private static let schemaVersion = 2
    private var canSave = true
    private(set) var storageIssue: String?
    private func setStorageIssue(_ issue: String?) {
        storageIssue = issue
    }

    private struct FileModel: Codable {
        let schemaVersion: Int
        let records: [HotkeyRecord]
    }

    init(fileURL: URL? = nil) {
        let defaultDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HotkeyStats", isDirectory: true)
        self.fileURL = fileURL ?? defaultDir.appendingPathComponent("records.json")
        do {
            try FileManager.default.createDirectory(
                at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch { AppLogger.shared.log(.error, .directoryFailed) }
        load()
    }

    // MARK: 记录

    func record(combo: String, keycode: Int, flags: UInt64) {
        let now = Date()
        var r = records[combo] ?? HotkeyRecord(
            combo: combo, keycode: keycode, flagsRaw: flags,
            count: 0, todayCount: 0, todayDate: DayKey.today,
            firstSeen: now, lastSeen: now
        )
        if r.todayDate != DayKey.today {   // 跨天惰性归零
            r.todayCount = 0
            r.todayDate = DayKey.today
        }
        r.count += 1
        r.todayCount += 1
        r.lastSeen = now
        records[combo] = r

        unsavedCount += 1
        onChange?()
        if unsavedCount >= 50 { save() }   // 批量落盘，避免频繁 IO
    }

    // MARK: 查询

    var sortedByCount: [HotkeyRecord] {
        records.values.sorted { $0.count > $1.count }
    }

    var todayTotal: Int {
        records.values
            .filter { $0.todayDate == DayKey.today }
            .reduce(0) { $0 + $1.todayCount }
    }

    // MARK: 清空

    func clear() {
        AppLogger.shared.log(.info, .recordsCleared)
        records.removeAll()
        save()
        onChange?()
    }

    // MARK: 持久化

    func save() {
        // 未知格式或备份失败时保持只读，不让退出保存覆盖原文件。
        guard canSave else { setStorageIssue("保存已阻止：原始文件受保护"); AppLogger.shared.log(.warning, .saveBlocked); return }
        let model = FileModel(schemaVersion: Self.schemaVersion, records: sortedByCount)
        do {
            let data = try JSONEncoder().encode(model)
            try data.write(to: fileURL, options: .atomic)
            unsavedCount = 0
            setStorageIssue(nil)
            AppLogger.shared.log(.debug, .recordsSaved)
        } catch {
            setStorageIssue("保存失败：数据暂存内存，请检查磁盘空间和目录权限")
            AppLogger.shared.log(.error, .saveFailed)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            AppLogger.shared.log(.debug, .recordsMissing)
            return
        }
        guard let model = try? JSONDecoder().decode(FileModel.self, from: data) else {
            AppLogger.shared.log(.error, .decodeFailed)
            return
        }
        guard model.schemaVersion == 1 || model.schemaVersion == Self.schemaVersion else {
            AppLogger.shared.log(.warning, .unsupportedSchema)
            setStorageIssue("未知数据版本：已停止写入以保护原文件")
            canSave = false // 不覆盖未知的新版本数据。
            return
        }
        if model.schemaVersion == 1 {
            AppLogger.shared.log(.info, .migrationStarted)
            do {
                let backup = fileURL.deletingLastPathComponent()
                    .appendingPathComponent("records-v1-backup-\(UUID().uuidString).json")
                try data.write(to: backup, options: .atomic)
            } catch {
                setStorageIssue("迁移备份失败：已停止写入以保护原文件")
                canSave = false // 备份失败时保留原文件，避免退出或定时保存覆盖它。
                AppLogger.shared.log(.error, .backupFailed)
                return
            }
            // 必须先完成磁盘备份，再合并历史计数；日志不包含记录内容。
            records = Self.migrate(model.records)
            AppLogger.shared.log(.info, .migrationFinished)
            save()
            return
        }
        AppLogger.shared.log(.debug, .recordsLoaded)
        records = Dictionary(model.records.map { ($0.combo, $0) }, uniquingKeysWith: { _, new in new })
    }

    private static func migrate(_ source: [HotkeyRecord]) -> [String: HotkeyRecord] {
        let today = DayKey.today
        var result: [String: HotkeyRecord] = [:]
        for var record in source {
            let parsed = ComboParser.parse(keycode: record.keycode, flagsRaw: record.flagsRaw)
            guard parsed.isHotkey else { continue }
            record.combo = parsed.combo
            if record.todayDate != today { record.todayCount = 0 }
            record.todayDate = today
            if var existing = result[record.combo] {
                existing.count += record.count
                existing.todayCount += record.todayCount
                existing.firstSeen = min(existing.firstSeen, record.firstSeen)
                existing.lastSeen = max(existing.lastSeen, record.lastSeen)
                result[record.combo] = existing
            } else {
                result[record.combo] = record
            }
        }
        return result
    }

}
