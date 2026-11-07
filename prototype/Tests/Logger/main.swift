import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
var now = Date(timeIntervalSince1970: 1793970000)
var failures = 0
let logger = AppLogger(directory: root, maxBytes: 500, retentionDays: 30,
                       clock: { now }, fallback: { failures += 1 })
for level in AppLogger.Level.allCases { logger.log(level, .started) }
logger.flush()
let first = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)[0]
let content = try String(contentsOf: first, encoding: .utf8)
check(content.contains("[ERROR]"), "levels")
check(content.contains("Application started"), "message")
logger.log(.info, .stopped)
logger.flush()
check((try! String(contentsOf: first, encoding: .utf8)).contains("Application stopped"), "append")
for _ in 0..<20 { logger.log(.debug, .started) }
logger.flush()
check((try! Data(contentsOf: first)).count <= 500, "cap")
let unrelated = root.appendingPathComponent("notes.log")
try Data().write(to: unrelated)
let future = root.appendingPathComponent("2099-01-01.log")
try Data().write(to: future)
now = now.addingTimeInterval(31 * 86400)
logger.log(.warning, .permissionMissing)
logger.flush()
check(!FileManager.default.fileExists(atPath: first.path), "retention")
check(FileManager.default.fileExists(atPath: unrelated.path), "unrelated preserved")
check(FileManager.default.fileExists(atPath: future.path), "future preserved")
check(failures == 0, "normal writes")
let blocked = root.appendingPathComponent("blocked")
try Data().write(to: blocked)
let bad = AppLogger(directory: blocked, clock: { now }, fallback: { failures += 1 })
bad.log(.error, .saveFailed)
bad.flush()
check(failures == 1, "fallback")

// 当天日志如果已经是符号链接，写入必须失败，不能顺着链接写到目录外。
let linkedRoot = root.appendingPathComponent("linked")
try FileManager.default.createDirectory(at: linkedRoot, withIntermediateDirectories: true)
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
formatter.dateFormat = "yyyy-MM-dd"
let outside = root.appendingPathComponent("outside")
try Data("unchanged".utf8).write(to: outside)
try FileManager.default.createSymbolicLink(
    at: linkedRoot.appendingPathComponent(formatter.string(from: now) + ".log"),
    withDestinationURL: outside
)
let linked = AppLogger(directory: linkedRoot, clock: { now })
linked.log(.error, .saveFailed)
linked.flush()
let outsideText = try String(contentsOf: outside, encoding: .utf8)
check(outsideText == "unchanged", "symlink preserved")

// 省略 clock 和 fallback，覆盖默认参数，并在目录不可写时走到默认的 NSLog。
let defaulted = AppLogger(directory: blocked)
defaulted.log(.info, .started)
defaulted.flush()
print("Logger tests passed")

let project = root.appendingPathComponent("project")
try FileManager.default.createDirectory(at: project.appendingPathComponent("prototype/Sources/HotkeyStats"), withIntermediateDirectories: true)
let source = project.appendingPathComponent("prototype/Sources/HotkeyStats/AppLogger.swift")
try Data().write(to: source)
check(AppLogger.logDirectory(sourcePath: source.path, override: nil) == project.appendingPathComponent("logs"), "project logs")
check(AppLogger.logDirectory(sourcePath: "/missing/source.swift", override: root.path).path == root.path, "explicit log directory")
check(AppLogger.logDirectory(sourcePath: "/missing/source.swift", override: nil).path.hasSuffix("Library/Logs/HotkeyStats"), "installed fallback")
let hotkeyRoot = root.appendingPathComponent("hotkeys")
let hotkeyLogger = AppLogger(directory: hotkeyRoot, clock: { now })
hotkeyLogger.logHotkey("⌘C")
hotkeyLogger.logHotkey("⌃⌥⇧⌘F1")
hotkeyLogger.logHotkey("⌘C\n[ERROR] injected")
hotkeyLogger.flush()
let hotkeyFile = try FileManager.default.contentsOfDirectory(at: hotkeyRoot, includingPropertiesForKeys: nil)[0]
let hotkeyText = try String(contentsOf: hotkeyFile, encoding: .utf8)
check(hotkeyText.contains("[DEBUG] Hotkey counted: \"⌘C\""), "hotkey name")
check(hotkeyText.contains("⌃⌥⇧⌘F1"), "multiple modifiers")
check(hotkeyText.split(separator: "\n").count == 3, "one line per event")
check(hotkeyText.contains("\\n[ERROR] injected"), "escaped newline")
