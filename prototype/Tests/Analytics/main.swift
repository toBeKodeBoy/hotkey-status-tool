import Foundation
import CoreGraphics

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
var now = ISO8601DateFormatter().date(from: "2026-11-08T12:00:00Z")!
let url = directory.appendingPathComponent("records.json")
let store = StatsStore(fileURL: url, clock: { now }, timeZone: TimeZone(secondsFromGMT: 0)!)
let safari = ApplicationIdentity(bundleID: "com.apple.Safari", name: "Safari")
let editor = ApplicationIdentity(bundleID: "com.apple.TextEdit", name: "TextEdit")
let cmd = CGEventFlags.maskCommand.rawValue
for _ in 0..<3 { store.record(combo: "⌘T", keycode: 17, flags: cmd, application: safari) }
for _ in 0..<2 { store.record(combo: "⌘T", keycode: 17, flags: cmd, application: editor) }
check(store.records["⌘T"]?.count == 5, "global total")
check(store.applicationRecords.count == 2, "application identity")
check(store.todayLeader == "⌘T", "today leader before menu opens")
check(store.trend(days: 7).map(\.count) == [0,0,0,0,0,0,5], "seven days including today")
check(store.trend(days: 30).count == 30, "thirty days")
check(store.conflicts(threshold: 2).map(\.combo) == ["⌘T"], "threshold inclusive")
check(store.conflicts(threshold: 3).isEmpty, "both apps must reach threshold")
store.ignoredBundleIDs = [safari.bundleID!]
check(!store.record(combo: "⌘T", keycode: 17, flags: cmd, application: safari), "ignored event rejected")
check(store.records["⌘T"]?.count == 5, "ignore does not erase history")
check(store.conflicts(threshold: 2).isEmpty, "ignored app excluded from conflict")
store.ignoredBundleIDs = []
store.save()
let reopened = StatsStore(fileURL: url, clock: { now })
check(reopened.todayTotal == 5, "daily persistence")
check(reopened.applicationRecords.count == 2, "application persistence")
now.addTimeInterval(86400)
check(store.todayLeader == nil, "midnight without input")
check(store.trend(days: 7).map(\.count) == [0,0,0,0,0,5,0], "history survives midnight")
store.record(combo: "⌘C", keycode: 8, flags: cmd, application: safari)
check(store.todayLeader == "⌘C", "new day leader")
check(store.trend(days: 7, bundleID: safari.bundleID).reduce(0) { $0 + $1.count } == 4, "application trend")
store.clear()
check(store.applicationRecords.isEmpty && store.trend(days: 7).allSatisfy { $0.count == 0 }, "clear all dimensions")
let corruptURL = directory.appendingPathComponent("corrupt.json")
let corrupt = Data("not json".utf8)
try corrupt.write(to: corruptURL)
let protected = StatsStore(fileURL: corruptURL)
protected.record(combo: "⌘C", keycode: 8, flags: cmd)
protected.save()
let bytes = try Data(contentsOf: corruptURL)
check(bytes == corrupt && protected.storageIssue != nil, "decode failure protects bytes")
print("PASS: app attribution, daily trend, conflicts, live ranking, storage protection")

// Calendar and presentation boundary cases are independent of system locale and wall clock.
let calendar = StatisticsCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
check(calendar.isValid("2024-02-29") && !calendar.isValid("2023-02-29"), "strict leap dates")
check(!calendar.isValid("oops") && !calendar.isValid("2026-1-1"), "strict date syntax")
check(calendar.days(ending: now, count: 0).isEmpty, "empty range")
let dst = ISO8601DateFormatter().date(from: "2026-03-09T12:00:00Z")!
check(calendar.days(ending: dst, count: 3) == ["2026-03-07", "2026-03-08", "2026-03-09"], "DST natural days")
check(RankingPresentation.title(leader: nil, running: true).isEmpty, "no leader")
check(RankingPresentation.title(leader: "⌘T", running: false).isEmpty, "paused leader hidden")
check(RankingPresentation.title(leader: "⌘T", running: true) == "⌘T", "short leader")
check(RankingPresentation.title(leader: String(repeating: "A", count: 20), running: true).count == 12, "bounded title")
check(store.conflicts(threshold: 0).isEmpty && store.conflicts(enabled: false).isEmpty, "invalid and disabled conflict")
check(store.source(for: "missing") == "未知应用", "missing source")

final class FakeProvider: FrontmostApplicationProviding {
    var calls = 0
    func current() -> ApplicationIdentity { calls += 1; return safari }
}
let provider = FakeProvider()
let recorder = HotkeyRecorder(store: store, provider: provider)
check(!recorder.receive(keycode: 17, flags: cmd, running: false, autorepeat: 0), "paused input")
check(!recorder.receive(keycode: 17, flags: cmd, running: true, autorepeat: 1), "long press")
check(!recorder.receive(keycode: 17, flags: 0, running: true, autorepeat: 0), "typing")
check(provider.calls == 0, "filtered input never samples app")
store.ignoredBundleIDs = [safari.bundleID!]
check(!recorder.receive(keycode: 17, flags: cmd, running: true, autorepeat: 0), "ignored input")
store.ignoredBundleIDs = []
check(recorder.receive(keycode: 17, flags: cmd, running: true, autorepeat: 0), "valid input")
check(provider.calls == 2, "only eligible events sample app")
let suite = "HotkeyStats-tests-" + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let settings = AnalyticsSettings(defaults: defaults)
check(settings.enabled && settings.threshold == 20 && settings.ignored.isEmpty, "settings defaults")
settings.threshold = -1
check(settings.threshold == 1, "threshold clamped")
settings.threshold = 21
settings.enabled = false
settings.ignored = [safari.bundleID!]
check(settings.threshold == 21 && !settings.enabled && settings.ignored.count == 1, "settings persisted")

// Byte-preserving migration and protection use only temporary fixtures.
func legacy(_ count: Int = 5, date: String = "2026-11-08") -> HotkeyRecord {
    HotkeyRecord(combo: "⌘T", keycode: 17, flagsRaw: cmd, count: count,
                 todayCount: count, todayDate: date, firstSeen: now, lastSeen: now)
}
struct Legacy: Codable { let schemaVersion: Int; let records: [HotkeyRecord] }
func fixtureURL() -> URL { directory.appendingPathComponent(UUID().uuidString + ".json") }
let legacyURL = fixtureURL()
let legacyBytes = try JSONEncoder().encode(Legacy(schemaVersion: 2, records: [legacy()]))
try legacyBytes.write(to: legacyURL)
let migrated = StatsStore(fileURL: legacyURL, clock: { now })
check(migrated.hasUndatedHistory && migrated.todayTotal == 0, "unknown legacy time zone")
check(migrated.applicationRecords[0].legacyToday[0].todayCount == 5, "legacy evidence preserved")
check(migrated.source(for: "⌘T") == "未知应用", "legacy source")
check(migrated.sortedByCount.count == 1, "sorted query")
let backup = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .first { $0.lastPathComponent.hasPrefix("records-v2-backup-") }!
let backupBytes = try Data(contentsOf: backup)
check(backupBytes == legacyBytes, "exact legacy backup")
check(StatsStore(fileURL: legacyURL).records["⌘T"]?.count == 5, "migration restart")
let futureURL = fixtureURL()
let futureBytes = Data("{\"schemaVersion\":99}".utf8)
try futureBytes.write(to: futureURL)
let future = StatsStore(fileURL: futureURL)
future.clear()
let futureAfter = try Data(contentsOf: futureURL)
check(futureAfter == futureBytes, "unknown schema remains intact after clear")
let invalidURL = fixtureURL()
try JSONEncoder().encode(Legacy(schemaVersion: 2, records: [legacy(-1)])).write(to: invalidURL)
check(StatsStore(fileURL: invalidURL).storageIssue != nil, "negative counts rejected")

struct V3Row: Codable {
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
struct V3: Codable { let schemaVersion: Int; let timeZoneIdentifier: String?; let applicationRecords: [V3Row] }
let v3row = V3Row(application: safari, combo: "⌘T", keycode: 17, flagsRaw: cmd, count: 5,
                  todayCount: 2, todayDate: "2026-11-09", firstSeen: now, lastSeen: now)
for zone in [nil, "GMT", "not-a-zone"] as [String?] {
    let url = fixtureURL()
    try JSONEncoder().encode(V3(schemaVersion: 3, timeZoneIdentifier: zone, applicationRecords: [v3row])).write(to: url)
    let result = StatsStore(fileURL: url, clock: { now }, timeZone: TimeZone(secondsFromGMT: 0)!)
    if zone == nil {
        check(result.hasUndatedHistory && result.todayTotal == 0, "v3 missing zone retained")
    } else if zone == "GMT" {
        check(result.todayTotal == 2 && result.hasUndatedHistory, "v3 known date retained")
    } else {
        check(result.storageIssue != nil, "invalid zone protects v3")
    }
}
// Stable ties, application rename, unknown exclusion, combo filter and date window boundary.
store.clear()
store.record(combo: "⌘T", keycode: 17, flags: cmd, application: safari)
store.record(combo: "⌘T", keycode: 17, flags: cmd, application: editor)
check(store.source(for: "⌘T") == "Safari", "source tie is stable")
store.record(combo: "⌘T", keycode: 17, flags: cmd, application: ApplicationIdentity(bundleID: safari.bundleID, name: "Renamed"))
check(store.source(for: "⌘T") == "Renamed", "rename keeps identity")
store.record(combo: "⌘A", keycode: 0, flags: cmd)
store.record(combo: "⌘A", keycode: 0, flags: cmd)
store.record(combo: "⌘A", keycode: 0, flags: cmd)
check(store.todayLeader == "⌘A", "leader ties sorted by combo")
check(store.conflicts(threshold: 1).count == 1, "unknown excluded")
check(store.trend(days: 7, combo: "⌘T").last?.count == 3, "combo query")
check(store.records(bundleID: editor.bundleID)["⌘T"]?.count == 1, "app totals")
now.addTimeInterval(7 * 86400)
check(store.conflicts(threshold: 1).isEmpty, "seven day boundary expires")
print("PASS: calendar, settings, intake filtering, legacy/v3 migration and query boundaries")

check(store.trend(days: 7).first!.id.count == 10, "trend point stable identity")

struct V4: Codable {
    let schemaVersion: Int
    let timeZoneIdentifier: String
    let applicationRecords: [AppHotkeyRecord]
}
func appRecord(count: Int = 2, combo: String = "⌘T", application: ApplicationIdentity = safari,
               daily: [String: Int] = [:], legacy: [HotkeyRecord] = []) -> AppHotkeyRecord {
    AppHotkeyRecord(application: application, combo: combo, keycode: 17, flagsRaw: cmd,
                   count: count, firstSeen: now, lastSeen: now, daily: daily, legacyToday: legacy)
}
func checkInvalid(_ records: [AppHotkeyRecord], zone: String = "GMT") throws {
    let url = fixtureURL()
    let bytes = try JSONEncoder().encode(V4(schemaVersion: 4, timeZoneIdentifier: zone, applicationRecords: records))
    try bytes.write(to: url)
    let result = StatsStore(fileURL: url)
    check(result.storageIssue != nil && result.records.isEmpty, "invalid v4 protected")
    result.save()
    let after = try Data(contentsOf: url)
    check(after == bytes, "invalid v4 unchanged")
}
try checkInvalid([], zone: "bad-zone")
try checkInvalid([appRecord(count: -1)])
try checkInvalid([appRecord(combo: "")])
try checkInvalid([appRecord(application: ApplicationIdentity(bundleID: "", name: "bad"))])
try checkInvalid([appRecord(application: ApplicationIdentity(bundleID: "valid", name: ""))])
try checkInvalid([appRecord(), appRecord()])
try checkInvalid([appRecord(daily: ["bad-date": 1])])
try checkInvalid([appRecord(daily: ["2026-01-01": -1])])
try checkInvalid([appRecord(daily: ["2026-01-01": 3])])
try checkInvalid([appRecord(count: Int.max, daily: ["2026-01-01": Int.max, "2026-01-02": 1])])
try checkInvalid([appRecord(count: Int.max), appRecord(combo: "⌘A")])
try checkInvalid([appRecord(legacy: [legacy(-1)])])
var reversed = appRecord()
reversed.firstSeen = now.addingTimeInterval(1)
try checkInvalid([reversed])
let limitURL = fixtureURL()
try JSONEncoder().encode(V4(schemaVersion: 4, timeZoneIdentifier: "GMT",
    applicationRecords: [appRecord(count: Int.max)])).write(to: limitURL)
let limit = StatsStore(fileURL: limitURL)
check(!limit.record(combo: "⌘A", keycode: 0, flags: cmd), "overflow rejected without adding empty row")
check(limit.records.count == 1 && limit.storageIssue != nil, "overflow leaves data unchanged")

for version in [1, 2] {
    let url = fixtureURL()
    try JSONEncoder().encode(Legacy(schemaVersion: version, records: [legacy(), legacy()])).write(to: url)
    let result = StatsStore(fileURL: url)
    if version == 1 { check(result.records["⌘T"]?.count == 10, "v1 alias merge") }
    else { check(result.storageIssue != nil, "v2 duplicates rejected") }
}
let typingURL = fixtureURL()
var typing = legacy()
typing.flagsRaw = 0
try JSONEncoder().encode(Legacy(schemaVersion: 1, records: [typing])).write(to: typingURL)
check(StatsStore(fileURL: typingURL).records.isEmpty, "legacy typing filtered")
let overflowURL = fixtureURL()
try JSONEncoder().encode(Legacy(schemaVersion: 1, records: [legacy(Int.max), legacy()])).write(to: overflowURL)
check(StatsStore(fileURL: overflowURL).storageIssue != nil, "legacy merge overflow protected")

// Real temporary permission failures exercise error handling, without touching user files.
let locked = directory.appendingPathComponent("locked")
try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
let lockedURL = locked.appendingPathComponent("records.json")
try legacyBytes.write(to: lockedURL)
try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
let blocked = StatsStore(fileURL: lockedURL)
check(blocked.records.isEmpty && blocked.storageIssue != nil, "backup failure prevents migration")
blocked.save()
let lockedAfter = try Data(contentsOf: lockedURL)
check(lockedAfter == legacyBytes, "backup failure bytes protected")
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
let writable = StatsStore(fileURL: lockedURL)
writable.record(combo: "⌘A", keycode: 0, flags: cmd)
writable.save()
let beforeFailure = try Data(contentsOf: lockedURL)
try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
writable.record(combo: "⌘A", keycode: 0, flags: cmd)
writable.save()
check(writable.storageIssue != nil && writable.records["⌘A"]?.count == 2, "save failure preserves memory")
let afterFailure = try Data(contentsOf: lockedURL)
check(afterFailure == beforeFailure, "save failure preserves disk")
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
writable.save()
check(writable.storageIssue == nil, "retry clears save warning")
let parentFile = directory.appendingPathComponent("parent-file")
try Data().write(to: parentFile)
check(StatsStore(fileURL: parentFile.appendingPathComponent("child.json")).storageIssue != nil,
      "directory creation and read failure visible")
let unreadable = fixtureURL()
try legacyBytes.write(to: unreadable)
try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
check(StatsStore(fileURL: unreadable).storageIssue != nil, "read failure protects existing file")
try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
let batchURL = fixtureURL()
let batch = StatsStore(fileURL: batchURL)
var notifications = 0
batch.onChange = { notifications += 1 }
for _ in 0..<50 { batch.record(combo: "⌘T", keycode: 17, flags: cmd) }
check(StatsStore(fileURL: batchURL).records["⌘T"]?.count == 50 && notifications == 50,
      "50th count saved and broadcasts")
batch.record(combo: "⌘A", keycode: 0, flags: cmd)
check(batch.sortedByCount.map(\.combo) == ["⌘T", "⌘A"], "count ordering")
let tieURL = fixtureURL()
let tie = StatsStore(fileURL: tieURL)
tie.record(combo: "⌘T", keycode: 17, flags: cmd)
tie.record(combo: "⌘A", keycode: 0, flags: cmd)
check(tie.sortedByCount.map(\.combo) == ["⌘A", "⌘T"], "stable cumulative ties")
AppLogger.shared.flush()
print("PASS: malformed files, overflow limits, permissions, save failure and retry")

let isolatedDefault = StatsStore(applicationSupportDirectory: directory)
isolatedDefault.record(combo: "⌘T", keycode: 17, flags: cmd)
isolatedDefault.save()
check(FileManager.default.fileExists(atPath: directory.appendingPathComponent("HotkeyStats/records.json").path),
      "default filename uses injectable application support root")
for apps in [[ApplicationIdentity.unknown, safari], [safari, ApplicationIdentity.unknown]] {
    let sourceStore = StatsStore(fileURL: fixtureURL())
    for app in apps { sourceStore.record(combo: "⌘T", keycode: 17, flags: cmd, application: app) }
    check(sourceStore.source(for: "⌘T") == "未知应用", "unknown source stable in either insertion order")
}
check(WorkspaceApplicationProvider(snapshot: { nil }).current() == .unknown, "missing workspace app")
check(WorkspaceApplicationProvider(snapshot: { (nil, "Name") }).current() == .unknown, "missing bundle id")
check(WorkspaceApplicationProvider(snapshot: { ("", "Name") }).current() == .unknown, "empty bundle id")
check(WorkspaceApplicationProvider(snapshot: { ("test", nil) }).current().name == "test", "missing app name")
check(WorkspaceApplicationProvider(snapshot: { ("test", "Name") }).current().name == "Name", "workspace identity")
_ = WorkspaceApplicationProvider().current()
AppLogger.shared.flush()

check(batch.todayLeader == "⌘T", "leader count ordering")
check(WorkspaceApplicationProvider.workspaceSnapshot(application: nil) == nil, "workspace no foreground app")

check(store.records(bundleID: nil, unknownOnly: true)["⌘A"]?.count == 3, "unknown application filter")
check(store.trend(days: 30, unknownOnly: true).reduce(0) { $0 + $1.count } == 3, "unknown trend filter")
try checkInvalid([appRecord(count: 2, legacy: [legacy(3)])])
try checkInvalid([appRecord(count: Int.max, legacy: [legacy(Int.max), legacy(1)])])

check(WorkspaceApplicationProvider(snapshot: { ("test", "") }).current().name == "test", "empty app name falls back to identity")

check(store.records(bundleID: nil, days: 7).isEmpty, "expired records do not appear in range table")
check(store.records(bundleID: nil, days: 30)["⌘T"]?.count == 3, "range aggregate across apps")
check(store.records(bundleID: safari.bundleID, days: 30)["⌘T"]?.count == 2, "range app filter")
check(store.records(bundleID: nil, unknownOnly: true, days: 30)["⌘A"]?.count == 3, "range unknown filter")
check(store.records(bundleID: nil, days: 0).isEmpty, "empty range table")
let scaleURL = fixtureURL()
let scaleDay = StatisticsCalendar(timeZone: TimeZone(secondsFromGMT: 0)!).day(now)
let scaleRows = (0..<2000).map { appRecord(count: 1, combo: "⌘Key-\($0)", daily: [scaleDay: 1]) }
try JSONEncoder().encode(V4(schemaVersion: 4, timeZoneIdentifier: "GMT", applicationRecords: scaleRows)).write(to: scaleURL)
let scale = StatsStore(fileURL: scaleURL, clock: { now })
let queryStart = Date()
let result = scale.records(bundleID: nil, days: 30)
check(result.count == 2000 && result.values.reduce(0) { $0 + $1.count } == 2000, "single-pass range query at scale")
print("PASS: range aggregation over 2000 combos in \(Int(Date().timeIntervalSince(queryStart) * 1000)) ms")
