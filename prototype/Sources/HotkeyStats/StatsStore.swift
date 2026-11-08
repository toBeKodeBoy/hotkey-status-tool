import Foundation

/// Main RunLoop only; all persisted counts are application aggregates, never raw events.
final class StatsStore {
    static let shared = StatsStore()
    private(set) var applicationRecords: [AppHotkeyRecord] = []
    var onChange: (() -> Void)?
    var ignoredBundleIDs: Set<String> = []
    private var unsavedCount = 0
    private var totalCount = 0
    private let fileURL: URL
    private let clock: () -> Date
    private(set) var statisticsCalendar: StatisticsCalendar
    private var canSave = true
    private(set) var storageIssue: String?
    private struct Header: Decodable { let schemaVersion: Int }
    private struct LegacyFile: Codable { let schemaVersion: Int; let records: [HotkeyRecord] }
    private struct FileModel: Codable {
        let schemaVersion: Int
        let timeZoneIdentifier: String
        let applicationRecords: [AppHotkeyRecord]
    }
    private struct V3File: Decodable {
        let schemaVersion: Int
        let timeZoneIdentifier: String?
        let applicationRecords: [V3Record]
    }
    private struct V3Record: Decodable {
        let application: ApplicationIdentity
        let combo: String
        let keycode: Int
        let flagsRaw: UInt64
        let count: Int
        let todayCount: Int
        let todayDate: String
        let firstSeen: Date
        let lastSeen: Date
    }
    private struct RecordKey: Hashable { let combo: String; let bundleID: String? }
    private var index: [RecordKey: Int] = [:]

    init(fileURL: URL? = nil, clock: @escaping () -> Date = Date.init,
         timeZone: TimeZone = .current, applicationSupportDirectory: URL? = nil) {
        let directory = applicationSupportDirectory.map { $0.appendingPathComponent("HotkeyStats", isDirectory: true) }
            ?? DataLocation.directory()
        self.fileURL = fileURL ?? directory.appendingPathComponent("records.json")
        self.clock = clock
        statisticsCalendar = StatisticsCalendar(timeZone: timeZone)
        do {
            try FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        } catch {
            protect("无法创建统计目录")
            AppLogger.shared.log(.error, .directoryFailed)
        }
        load()
    }

    var today: String { statisticsCalendar.day(clock()) }
    var hasUndatedHistory: Bool { applicationRecords.contains { !$0.legacyToday.isEmpty } }

    @discardableResult
    func record(combo: String, keycode: Int, flags: UInt64,
                application: ApplicationIdentity = .unknown) -> Bool {
        if let id = application.bundleID, ignoredBundleIDs.contains(id) { return false }
        guard totalCount < Int.max else {
            storageIssue = "计数已达上限，未新增记录"
            return false
        }
        let now = clock()
        let day = statisticsCalendar.day(now)
        let key = RecordKey(combo: combo, bundleID: application.bundleID)
        let position: Int
        if let existing = index[key] {
            position = existing
        } else {
            position = applicationRecords.count
            index[key] = position
            applicationRecords.append(AppHotkeyRecord(application: application, combo: combo,
                keycode: keycode, flagsRaw: flags, count: 0, firstSeen: now, lastSeen: now,
                daily: [:], legacyToday: []))
        }
        totalCount += 1
        applicationRecords[position].application = application
        applicationRecords[position].count += 1
        applicationRecords[position].daily[day, default: 0] += 1
        applicationRecords[position].firstSeen = min(applicationRecords[position].firstSeen, now)
        applicationRecords[position].lastSeen = max(applicationRecords[position].lastSeen, now)
        unsavedCount += 1
        if unsavedCount >= 50 { save() }
        onChange?()
        return true
    }

    var records: [String: HotkeyRecord] { records(bundleID: nil) }
    func records(bundleID: String?, unknownOnly: Bool = false) -> [String: HotkeyRecord] {
        let day = today
        var result: [String: HotkeyRecord] = [:]
        for item in applicationRecords where (bundleID == nil || item.application.bundleID == bundleID) && (!unknownOnly || item.application.bundleID == nil) {
            if var existing = result[item.combo] {
                existing.count += item.count
                existing.todayCount += item.daily[day, default: 0]
                existing.firstSeen = min(existing.firstSeen, item.firstSeen)
                existing.lastSeen = max(existing.lastSeen, item.lastSeen)
                result[item.combo] = existing
            } else {
                result[item.combo] = HotkeyRecord(combo: item.combo, keycode: item.keycode,
                    flagsRaw: item.flagsRaw, count: item.count, todayCount: item.daily[day, default: 0],
                    todayDate: day, firstSeen: item.firstSeen, lastSeen: item.lastSeen)
            }
        }
        return result
    }
    var sortedByCount: [HotkeyRecord] {
        records.values.sorted { $0.count == $1.count ? $0.combo < $1.combo : $0.count > $1.count }
    }
    var todayTotal: Int { records.values.reduce(0) { $0 + $1.todayCount } }
    var todayLeader: String? {
        records.values.filter { $0.todayCount > 0 }.sorted {
            $0.todayCount == $1.todayCount ? $0.combo < $1.combo : $0.todayCount > $1.todayCount
        }.first?.combo
    }
    func source(for combo: String) -> String {
        applicationRecords.filter { $0.combo == combo }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return ($0.application.bundleID ?? "") < ($1.application.bundleID ?? "")
        }.first?.application.name ?? ApplicationIdentity.unknown.name
    }
    func trend(days: Int, bundleID: String? = nil, combo: String? = nil, unknownOnly: Bool = false) -> [TrendPoint] {
        let items = applicationRecords.filter {
            (bundleID == nil || $0.application.bundleID == bundleID) && (combo == nil || $0.combo == combo) && (!unknownOnly || $0.application.bundleID == nil)
        }
        return statisticsCalendar.days(ending: clock(), count: days).map { day in
            TrendPoint(day: day, count: items.reduce(0) { $0 + $1.daily[day, default: 0] })
        }
    }
    func conflicts(threshold: Int = 20, enabled: Bool = true) -> [HotkeyConflict] {
        guard enabled, threshold > 0 else { return [] }
        let days = statisticsCalendar.days(ending: clock(), count: 7)
        var grouped: [String: [(ApplicationIdentity, Int)]] = [:]
        for item in applicationRecords {
            guard let id = item.application.bundleID, !ignoredBundleIDs.contains(id) else { continue }
            let count = days.reduce(0) { $0 + item.daily[$1, default: 0] }
            if count >= threshold { grouped[item.combo, default: []].append((item.application, count)) }
        }
        return grouped.keys.sorted().compactMap { combo in
            guard let apps = grouped[combo], apps.count >= 2 else { return nil }
            return HotkeyConflict(combo: combo, applications: apps.sorted { $0.0.bundleID! < $1.0.bundleID! })
        }
    }
    func clear() {
        applicationRecords.removeAll()
        totalCount = 0
        index.removeAll()
        AppLogger.shared.log(.info, .recordsCleared)
        save()
        onChange?()
    }
    func save() {
        guard canSave else {
            AppLogger.shared.log(.warning, .saveBlocked)
            return
        }
        do {
            let model = FileModel(schemaVersion: 4, timeZoneIdentifier: statisticsCalendar.timeZone.identifier,
                                  applicationRecords: applicationRecords)
            try JSONEncoder().encode(model).write(to: fileURL, options: .atomic)
            unsavedCount = 0
            storageIssue = nil
            AppLogger.shared.log(.debug, .recordsSaved)
        } catch {
            storageIssue = "保存失败：数据暂存内存，请检查磁盘空间和目录权限"
            AppLogger.shared.log(.error, .saveFailed)
        }
    }
    private func protect(_ message: String) {
        canSave = false
        storageIssue = message + "：已停止写入以保护原文件"
    }
    private func load() {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch {
            if (error as NSError).domain == NSCocoaErrorDomain &&
                (error as NSError).code == NSFileReadNoSuchFileError {
                AppLogger.shared.log(.debug, .recordsMissing)
            } else {
                protect("读取统计文件失败")
                AppLogger.shared.log(.error, .decodeFailed)
            }
            return
        }
        do {
            let header = try JSONDecoder().decode(Header.self, from: data)
            guard [1, 2, 3, 4].contains(header.schemaVersion) else {
                protect("未知数据版本")
                AppLogger.shared.log(.warning, .unsupportedSchema)
                return
            }
            if header.schemaVersion == 4 {
                let file = try JSONDecoder().decode(FileModel.self, from: data)
                guard let zone = TimeZone(identifier: file.timeZoneIdentifier) else { throw InvalidData.invalid }
                statisticsCalendar = StatisticsCalendar(timeZone: zone)
                try validate(file.applicationRecords)
                applicationRecords = file.applicationRecords
            } else {
                let migrated: [AppHotkeyRecord]
                if header.schemaVersion == 3 {
                    let file = try JSONDecoder().decode(V3File.self, from: data)
                    if let id = file.timeZoneIdentifier {
                        guard let zone = TimeZone(identifier: id) else { throw InvalidData.invalid }
                        statisticsCalendar = StatisticsCalendar(timeZone: zone)
                    }
                    migrated = try file.applicationRecords.map { item in
                        let legacy = HotkeyRecord(combo: item.combo, keycode: item.keycode,
                            flagsRaw: item.flagsRaw, count: item.count, todayCount: item.todayCount,
                            todayDate: item.todayDate, firstSeen: item.firstSeen, lastSeen: item.lastSeen)
                        try validateLegacy(legacy)
                        return AppHotkeyRecord(application: item.application, combo: item.combo,
                            keycode: item.keycode, flagsRaw: item.flagsRaw, count: item.count,
                            firstSeen: item.firstSeen, lastSeen: item.lastSeen,
                            daily: file.timeZoneIdentifier == nil ? [:] : [item.todayDate: item.todayCount],
                            legacyToday: file.timeZoneIdentifier == nil ? [legacy] : [])
                    }
                } else {
                    let file = try JSONDecoder().decode(LegacyFile.self, from: data)
                    migrated = try migrate(file.records, version: header.schemaVersion)
                }
                try validate(migrated)
                AppLogger.shared.log(.info, .migrationStarted)
                do {
                    let backup = fileURL.deletingLastPathComponent()
                        .appendingPathComponent("records-v\(header.schemaVersion)-backup-\(UUID().uuidString).json")
                    try data.write(to: backup, options: .atomic)
                } catch {
                    protect("迁移备份失败")
                    AppLogger.shared.log(.error, .backupFailed)
                    return
                }
                applicationRecords = migrated
                save()
                AppLogger.shared.log(.info, .migrationFinished)
            }
            totalCount = applicationRecords.reduce(0) { $0 + $1.count }
            for (position, record) in applicationRecords.enumerated() {
                index[RecordKey(combo: record.combo, bundleID: record.application.bundleID)] = position
            }
            AppLogger.shared.log(.debug, .recordsLoaded)
        } catch {
            protect("统计文件损坏或字段无效")
            AppLogger.shared.log(.error, .decodeFailed)
        }
    }
    private enum InvalidData: Error { case invalid }
    private func validate(_ records: [AppHotkeyRecord]) throws {
        var keys = Set<RecordKey>()
        var total = 0
        for record in records {
            guard record.count >= 0, record.firstSeen <= record.lastSeen,
                  !record.combo.isEmpty, !record.application.name.isEmpty,
                  record.application.bundleID != "",
                  keys.insert(RecordKey(combo: record.combo, bundleID: record.application.bundleID)).inserted
            else { throw InvalidData.invalid }
            var known = 0
            for (day, count) in record.daily {
                guard statisticsCalendar.isValid(day), count >= 0,
                      !known.addingReportingOverflow(count).overflow else { throw InvalidData.invalid }
                known += count
            }
            guard known <= record.count, !total.addingReportingOverflow(record.count).overflow
            else { throw InvalidData.invalid }
            total += record.count
            var legacyTotal = 0
            for legacy in record.legacyToday {
                try validateLegacy(legacy)
                guard !legacyTotal.addingReportingOverflow(legacy.count).overflow else { throw InvalidData.invalid }
                legacyTotal += legacy.count
            }
            guard legacyTotal <= record.count - known else { throw InvalidData.invalid }
        }
    }
    private func validateLegacy(_ record: HotkeyRecord) throws {
        guard record.count >= 0, record.todayCount >= 0, record.todayCount <= record.count,
              record.firstSeen <= record.lastSeen, statisticsCalendar.isValid(record.todayDate)
        else { throw InvalidData.invalid }
    }
    private func migrate(_ source: [HotkeyRecord], version: Int) throws -> [AppHotkeyRecord] {
        var result: [AppHotkeyRecord] = []
        var positions: [String: Int] = [:]
        for record in source {
            try validateLegacy(record)
            let parsed = ComboParser.parse(keycode: record.keycode, flagsRaw: record.flagsRaw)
            if version == 1 && !parsed.isHotkey { continue }
            let combo = version == 1 ? parsed.combo : record.combo
            if let position = positions[combo] {
                // v1 aliases intentionally merge; duplicate v2 keys are corrupt, not last-writer wins.
                guard version == 1, !result[position].count.addingReportingOverflow(record.count).overflow
                else { throw InvalidData.invalid }
                result[position].count += record.count
                result[position].firstSeen = min(result[position].firstSeen, record.firstSeen)
                result[position].lastSeen = max(result[position].lastSeen, record.lastSeen)
                result[position].legacyToday.append(record)
            } else {
                positions[combo] = result.count
                result.append(AppHotkeyRecord(application: .unknown, combo: combo, keycode: record.keycode,
                    flagsRaw: record.flagsRaw, count: record.count, firstSeen: record.firstSeen,
                    lastSeen: record.lastSeen, daily: [:], legacyToday: [record]))
            }
        }
        return result
    }
}
