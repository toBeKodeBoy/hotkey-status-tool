import Foundation
import Darwin
import ServiceManagement
func check(_ value: @autoclosure () -> Bool) { precondition(value()) }
if CommandLine.arguments.count > 1 {
    let lock = try InstanceLock(url: URL(fileURLWithPath: CommandLine.arguments[1]))
    exit(lock == nil ? 23 : 0)
}
let suiteName = UUID().uuidString
let defaults = UserDefaults(suiteName: suiteName)!
defer { defaults.removePersistentDomain(forName: suiteName) }
var allowed = true
var starts = 0
var stops = 0
var success = true
let control = MonitoringController(defaults: defaults, permission: { allowed }, start: { starts += 1; return success }, stop: { stops += 1 })
control.refresh()
check(control.state == .running)
control.togglePause()
check(control.state == .paused)
check(defaults.bool(forKey: "isPaused"))
allowed = false
control.refresh()
check(control.state == .permissionMissing)
allowed = true
control.refresh()
check(control.state == .paused)
let restored = MonitoringController(defaults: defaults, permission: { true }, start: { fatalError("paused restart must not start") }, stop: {})
restored.refresh()
check(restored.state == .paused)
var updates = 0
control.onChange = { _ in updates += 1 }
control.togglePause()
check(updates == 1)
check(control.state == .running)
success = false
control.refresh()
check(control.state == .failed)
check(starts == 3 && stops > 0)
check(CountingPolicy.accepts(isRunning: true, autorepeat: 0))
check(!CountingPolicy.accepts(isRunning: true, autorepeat: 1))
check(!CountingPolicy.accepts(isRunning: false, autorepeat: 0))
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let lock = root.appendingPathComponent("instance.lock")
var first: InstanceLock? = try InstanceLock(url: lock)
check(first != nil)
let duplicate = try InstanceLock(url: lock)
check(duplicate == nil)
first = nil
let acquired = try InstanceLock(url: lock)
check(acquired != nil)
print("Runtime tests passed")

let child = Process()
child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
child.arguments = [lock.path]
try child.run()
child.waitUntilExit()
check(child.terminationStatus == 23)
do {
    _ = try InstanceLock(url: root.appendingPathComponent("missing/lock"))
    fatalError("missing parent must fail")
} catch {}
let symlink = root.appendingPathComponent("symlink")
try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: lock)
do { _ = try InstanceLock(url: symlink); fatalError("symlink must fail") } catch {}

var appAvailable = false
var loginStatus: SMAppService.Status = .notRegistered
var registered = 0, unregistered = 0, settings = 0, errors = 0
var failRegistration = false
let login = LoginLaunch(isApp: { appAvailable }, status: { loginStatus }, register: {
    if failRegistration { throw CocoaError(.fileWriteNoPermission) }
    registered += 1
}, unregister: { unregistered += 1 }, openSettings: { settings += 1 }, showError: { errors += 1 })
check(!login.available && !login.enabled)
check(login.title.contains("应用包"))
login.toggle()
check(registered == 0)
appAvailable = true
check(login.title == "登录时启动")
login.toggle()
check(registered == 1)
loginStatus = .enabled
check(login.enabled)
login.toggle()
check(unregistered == 1)
loginStatus = .requiresApproval
check(login.title.contains("批准"))
login.toggle()
check(settings == 1)
loginStatus = .notFound
check(login.title.contains("重新注册"))
failRegistration = true
login.toggle()
check(errors == 1)
let time = Date(timeIntervalSince1970: 1000)
func record(_ name: String, _ count: Int, _ todayCount: Int, _ day: String, _ offset: Double) -> HotkeyRecord {
    HotkeyRecord(combo: name, keycode: 0, flagsRaw: 0, count: count, todayCount: todayCount,
                 todayDate: day, firstSeen: time, lastSeen: time.addingTimeInterval(offset))
}
let records = [record("B", 2, 20, "old", 1), record("A", 1, 2, "today", 0), record("C", 2, 1, "today", 1)]
for (key, expected) in [("总次数", ["B", "C", "A"]), ("今日", ["A", "C", "B"]), ("最近使用", ["B", "C", "A"])] {
    check(RecordOrdering.sorted(records, key: key, ascending: false, today: "today").map { $0.combo } == expected)
    check(RecordOrdering.sorted(records, key: key, ascending: true, today: "today").first!.combo == expected.last!)
}
check(RecordOrdering.sorted([], key: "今日", ascending: true, today: "today").isEmpty)
print("Login and ordering tests passed")

let ties = [record("B", 2, 1, "today", 0), record("A", 1, 1, "today", 1)]
check(RecordOrdering.sorted(ties, key: "今日", ascending: false, today: "today").map { $0.combo } == ["A", "B"])
// 周期性检查保持同一状态时，不能重复输出状态日志。
AppLogger.shared.flush()
let logRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOTKEYSTATS_LOG_DIR"]!)
let logFile = try FileManager.default.contentsOfDirectory(at: logRoot, includingPropertiesForKeys: nil).first!
let beforeRefresh = try Data(contentsOf: logFile)
control.refresh()
AppLogger.shared.flush()
let afterRefresh = try Data(contentsOf: logFile)
check(beforeRefresh == afterRefresh)
let logText = String(decoding: afterRefresh, as: UTF8.self)
check(logText.contains("Pause requested"))
check(logText.contains("Monitoring unavailable"))
check(logText.contains("Login launch update failed"))
print("Critical-path logging tests passed")

check(MonitoringController.State(rawValue: "统计中") == .running)
check(MonitoringController.State.running.rawValue == "统计中")
do {
    _ = try InstanceLock(url: root.appendingPathComponent("failure.lock"), acquire: { _ in errno = EIO; return -1 })
    fatalError("unexpected lock success")
} catch { check((error as NSError).code == Int(EIO)) }
let oldRecords = [record("A", 1, 10, "old", 0), record("B", 2, 1, "today", 0)]
check(RecordOrdering.sorted(oldRecords, key: "今日", ascending: true, today: "today").first!.combo == "A")
// 两元素双向输入覆盖比较器的相等、小于、大于与跨日分支。
for lhs in records + ties + oldRecords {
    for rhs in records + ties + oldRecords {
        for key in ["总次数", "今日", "最近使用"] {
            for ascending in [true, false] {
                let pair = RecordOrdering.sorted([lhs, rhs], key: key, ascending: ascending, today: "today")
                check(pair.count == 2)
            }
        }
    }
}

control.shutdown()
