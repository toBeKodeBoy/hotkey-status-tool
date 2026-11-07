import AppKit
import CoreGraphics
import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

func sameTime(_ lhs: Date, _ rhs: Date) -> Bool {
    abs(lhs.timeIntervalSince(rhs)) < 0.001
}

func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

let cmd = CGEventFlags.maskCommand.rawValue
let shift = CGEventFlags.maskShift.rawValue
let ctrl = CGEventFlags.maskControl.rawValue
let option = CGEventFlags.maskAlternate.rawValue
let fn = CGEventFlags.maskSecondaryFn.rawValue
let caps = CGEventFlags.maskAlphaShift.rawValue
let nonCoalesced = CGEventFlags.maskNonCoalesced.rawValue

let names: [(Int, String, Bool)] = [
    (0, "A", true), (1, "S", true), (2, "D", true), (3, "F", true), (4, "H", true), (5, "G", true),
    (6, "Z", true), (7, "X", true), (8, "C", true), (9, "V", true), (11, "B", true), (12, "Q", true),
    (13, "W", true), (14, "E", true), (15, "R", true), (16, "Y", true), (17, "T", true),
    (31, "O", true), (32, "U", true), (34, "I", true), (35, "P", true), (37, "L", true),
    (38, "J", true), (40, "K", true), (45, "N", true), (46, "M", true),
    (36, "Return", false), (48, "Tab", false), (49, "Space", false), (53, "Esc", false),
    (51, "Delete", false), (117, "ForwardDelete", false),
    (123, "←", false), (124, "→", false), (125, "↓", false), (126, "↑", false),
    (115, "Home", false), (119, "End", false), (116, "PageUp", false), (121, "PageDown", false),
    (105, "F13", false), (107, "F14", false), (113, "F15", false),
    (122, "F1", false), (120, "F2", false), (99, "F3", false), (118, "F4", false),
    (96, "F5", false), (97, "F6", false), (98, "F7", false), (100, "F8", false),
    (101, "F9", false), (109, "F10", false), (103, "F11", false), (111, "F12", false),
    (29, "0", true), (18, "1", true), (19, "2", true), (20, "3", true), (21, "4", true),
    (23, "5", true), (22, "6", true), (26, "7", true), (28, "8", true), (25, "9", true),
    (33, "[", true), (30, "]", true), (42, "\\", true), (39, "'", true), (41, ";", true),
    (27, "-", true), (24, "=", true), (43, ",", true), (47, ".", true), (44, "/", true), (50, "`", true),
]
for (code, name, isCharacter) in names {
    check(KeyMapper.name(for: code) == name, "key mapping: \(code)")
    check(KeyMapper.isCharacterKey(code) == isCharacter, "character class: \(code)")
    let typed = ComboParser.parse(keycode: code, flagsRaw: shift)
    check(typed.isHotkey == !isCharacter, "shift classification: \(code)")
    if !isCharacter {
        check(typed.combo == "⇧" + name, "shift name: \(code)")
    }
    check(ComboParser.parse(keycode: code, flagsRaw: cmd).combo == "⌘" + name, "command mapping: \(code)")
}
check(!ComboParser.parse(keycode: 8, flagsRaw: 0).isHotkey, "plain typing")
check(!ComboParser.parse(keycode: 8, flagsRaw: caps).isHotkey, "caps lock is not a hotkey")
check(ComboParser.parse(keycode: 8, flagsRaw: cmd | caps | nonCoalesced).combo == "⌘C", "ignored flag bits")
check(ComboParser.parse(keycode: 8, flagsRaw: ctrl).combo == "⌃C", "control")
check(ComboParser.parse(keycode: 8, flagsRaw: option).combo == "⌥C", "option")
check(ComboParser.parse(keycode: 8, flagsRaw: fn | shift).combo == "fn⇧C", "fn keeps shift letter")
check(
    ComboParser.parse(keycode: 8, flagsRaw: fn | ctrl | option | shift | cmd).combo == "fn⌃⌥⇧⌘C",
    "modifier order"
)
check(KeyMapper.name(for: 255) == "Key(255)", "unknown key")
check(!KeyMapper.isCharacterKey(255), "unknown key is not a character")
check(ComboParser.parse(keycode: 255, flagsRaw: shift).combo == "⇧Key(255)", "shift unknown key")

let dir = try tempDir()
defer { try? FileManager.default.removeItem(at: dir) }
let url = dir.appendingPathComponent("records.json")
let now = Date()
let earlier = Date(timeIntervalSince1970: 1_700_000_000)
let later = Date(timeIntervalSince1970: 1_700_100_000)
func record(
    _ combo: String, _ code: Int, _ flags: UInt64, _ count: Int, _ day: String,
    first: Date = now, last: Date = now
) -> HotkeyRecord {
    HotkeyRecord(
        combo: combo, keycode: code, flagsRaw: flags, count: count,
        todayCount: count, todayDate: day, firstSeen: first, lastSeen: last
    )
}
struct Fixture: Codable { let schemaVersion: Int; let records: [HotkeyRecord] }
let original = try JSONEncoder().encode(Fixture(schemaVersion: 1, records: [
    record("wrong1", 8, cmd, 3, DayKey.today, first: earlier, last: earlier),
    record("wrong2", 8, cmd, 4, "2000-01-01", first: later, last: later),
    record("typing", 45, shift, 2, DayKey.today),
]))
try original.write(to: url)
let store = StatsStore(fileURL: url)
check(store.records.count == 1, "merge and filter migration")
let merged = store.records["⌘C"]!
check(merged.count == 7, "merge totals")
check(store.todayTotal == 3, "today counts")
check(sameTime(merged.firstSeen, earlier), "earliest first seen")
check(sameTime(merged.lastSeen, later), "latest last seen")
let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
let backup = files.first { $0.lastPathComponent.hasPrefix("records-v1-backup-") }!
let backupData = try Data(contentsOf: backup)
check(backupData == original, "exact backup")
let reopened = StatsStore(fileURL: url)
check(reopened.records["⌘C"]?.count == 7, "migration idempotence")
let backupsAfterReload = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("records-v1-backup-") }
check(backupsAfterReload.count == 1, "reload does not back up again")
let file = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
check(file.schemaVersion == 2, "version saved")

let duplicateDir = try tempDir()
defer { try? FileManager.default.removeItem(at: duplicateDir) }
let duplicateURL = duplicateDir.appendingPathComponent("records.json")
try JSONEncoder().encode(Fixture(schemaVersion: 2, records: [
    record("⌘C", 8, cmd, 1, DayKey.today),
    record("⌘C", 8, cmd, 9, DayKey.today),
])).write(to: duplicateURL)
let duplicateStore = StatsStore(fileURL: duplicateURL)
check(duplicateStore.records["⌘C"]?.count == 9, "duplicate load keeps the later record")

let unknownDir = try tempDir()
defer { try? FileManager.default.removeItem(at: unknownDir) }
let unknownURL = unknownDir.appendingPathComponent("records.json")
let unknownOriginal = try JSONEncoder().encode(Fixture(schemaVersion: 99, records: [
    record("⌘C", 8, cmd, 5, DayKey.today),
]))
try unknownOriginal.write(to: unknownURL)
let unknownStore = StatsStore(fileURL: unknownURL)
check(unknownStore.records.isEmpty, "unknown version is not loaded")
unknownStore.record(combo: "⌘C", keycode: 8, flags: cmd)
unknownStore.save()
let unknownFileAfterSave = try Data(contentsOf: unknownURL)
check(unknownFileAfterSave == unknownOriginal, "unknown version is not overwritten")

let corruptDir = try tempDir()
defer { try? FileManager.default.removeItem(at: corruptDir) }
let corruptURL = corruptDir.appendingPathComponent("records.json")
let corruptOriginal = Data("not-json".utf8)
try corruptOriginal.write(to: corruptURL)
let corruptStore = StatsStore(fileURL: corruptURL)
check(corruptStore.records.isEmpty, "corrupt file is not loaded")
let corruptFileAfterLoad = try Data(contentsOf: corruptURL)
check(corruptFileAfterLoad == corruptOriginal, "loading a corrupt file does not rewrite it")

let lockedDir = try tempDir()
defer {
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path)
    try? FileManager.default.removeItem(at: lockedDir)
}
let lockedURL = lockedDir.appendingPathComponent("records.json")
try original.write(to: lockedURL)
try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedDir.path)
let lockedStore = StatsStore(fileURL: lockedURL)
check(lockedStore.records.isEmpty, "backup failure leaves memory empty")
let fileAfterFailedBackup = try Data(contentsOf: lockedURL)
check(fileAfterFailedBackup == original, "backup failure does not overwrite")
lockedStore.record(combo: "⌘C", keycode: 8, flags: cmd)
lockedStore.save()
let fileAfterBlockedSave = try Data(contentsOf: lockedURL)
check(fileAfterBlockedSave == original, "later save stays blocked after backup failure")

let freshDir = try tempDir()
defer { try? FileManager.default.removeItem(at: freshDir) }
let freshURL = freshDir.appendingPathComponent("records.json")
let fresh = StatsStore(fileURL: freshURL)
var changes = 0
fresh.onChange = { changes += 1 }
fresh.record(combo: "⌘A", keycode: 0, flags: cmd)
let firstSeen = fresh.records["⌘A"]!.firstSeen
fresh.record(combo: "⌘A", keycode: 0, flags: cmd)
check(fresh.records["⌘A"]?.count == 2, "repeat increments total")
check(fresh.records["⌘A"]?.todayCount == 2, "repeat increments today")
check(sameTime(fresh.records["⌘A"]!.firstSeen, firstSeen), "first seen stays")
fresh.record(combo: "⌘B", keycode: 11, flags: cmd)
fresh.record(combo: "⌘B", keycode: 11, flags: cmd)
fresh.record(combo: "⌘B", keycode: 11, flags: cmd)
fresh.record(combo: "⌘C", keycode: 8, flags: cmd)
check(fresh.sortedByCount.map(\.combo) == ["⌘B", "⌘A", "⌘C"], "sorted by count")
check(fresh.todayTotal == 6, "today total sums current day")
check(!FileManager.default.fileExists(atPath: freshURL.path), "records stay in memory before 50")
for _ in 0..<44 { fresh.record(combo: "⌘A", keycode: 0, flags: cmd) }
check(FileManager.default.fileExists(atPath: freshURL.path), "50th new record is saved")
let savedAt50 = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: freshURL))
check(savedAt50.records.first { $0.combo == "⌘A" }?.count == 46, "saved count includes the 50th record")
fresh.record(combo: "⌘A", keycode: 0, flags: cmd)
let still50 = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: freshURL))
check(still50.records.first { $0.combo == "⌘A" }?.count == 46, "51st record waits for the next save")
check(changes == 51, "each record notifies")

let previousDay = try JSONEncoder().encode(Fixture(schemaVersion: 2, records: [
    record("⌘C", 8, cmd, 4, "2000-01-01"),
]))
let rolloverDir = try tempDir()
defer { try? FileManager.default.removeItem(at: rolloverDir) }
let rolloverURL = rolloverDir.appendingPathComponent("records.json")
try previousDay.write(to: rolloverURL)
let rollover = StatsStore(fileURL: rolloverURL)
check(rollover.todayTotal == 0, "old today count is not today")
rollover.record(combo: "⌘C", keycode: 8, flags: cmd)
check(rollover.records["⌘C"]?.count == 5, "rollover keeps the cumulative count")
check(rollover.records["⌘C"]?.todayCount == 1, "rollover starts today at 1")
check(rollover.records["⌘C"]?.todayDate == DayKey.today, "rollover stamps today")

let clearDir = try tempDir()
defer { try? FileManager.default.removeItem(at: clearDir) }
let clearURL = clearDir.appendingPathComponent("records.json")
let clearing = StatsStore(fileURL: clearURL)
var clearChanges = 0
clearing.onChange = { clearChanges += 1 }
clearing.record(combo: "⌘C", keycode: 8, flags: cmd)
clearing.clear()
check(clearing.records.isEmpty, "clear removes memory records")
check(clearChanges == 2, "clear notifies")
let cleared = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: clearURL))
check(cleared.schemaVersion == 2 && cleared.records.isEmpty, "clear persists an empty file")
let clearedAgain = StatsStore(fileURL: clearURL)
check(clearedAgain.records.isEmpty, "cleared file reloads empty")

let saveDir = try tempDir()
defer {
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: saveDir.path)
    try? FileManager.default.removeItem(at: saveDir)
}
let saveURL = saveDir.appendingPathComponent("records.json")
let saving = StatsStore(fileURL: saveURL)
saving.record(combo: "⌘C", keycode: 8, flags: cmd)
saving.save()
check(saving.storageIssue == nil, "successful save clears warning")
let savedOnce = try Data(contentsOf: saveURL)
try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: saveDir.path)
saving.record(combo: "⌘C", keycode: 8, flags: cmd)
saving.save()
check(saving.storageIssue != nil, "failed save exposes menu status")
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: saveDir.path)
check(saving.records["⌘C"]?.count == 2, "failed save keeps the new count in memory")
let fileAfterFailedSave = try Data(contentsOf: saveURL)
check(fileAfterFailedSave == savedOnce, "failed save does not change the file")

saving.save()
check(saving.storageIssue == nil, "retry save clears warning")
check(unknownStore.storageIssue != nil, "unknown schema exposes protected status")
check(lockedStore.storageIssue != nil, "backup failure exposes protected status")

// 初始化控制器会订阅共享存储；空窗口状态下主动触发回调，不能访问未创建的控件。
let controller = StatsWindowController()
StatsStore.shared.onChange?()
withExtendedLifetime(controller) {}
print("PASS: mapping, filtering, migration, backup, restart, save, clear, unopened window callback")
