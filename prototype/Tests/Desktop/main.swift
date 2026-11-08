import AppKit
import Foundation
import ServiceManagement

if CommandLine.arguments.contains("--terminate-action") {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let actions = StatusBar.Actions()
    _ = actions.openURL(URL(string: "hotkeystats-test-unregistered-scheme://invalid")!)
    actions.terminate(nil)
}

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let suite = "HotkeyStats-desktop-" + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer {
    defaults.removePersistentDomain(forName: suite)
    AppLogger.shared.flush()
    try? FileManager.default.removeItem(at: directory)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var now = Date()
let store = StatsStore(fileURL: directory.appendingPathComponent("records.json"), clock: { now })
checkEventTap(store: store)
store.clear()
let controller = StatsWindowController(store: store, settings: AnalyticsSettings(defaults: defaults))
controller.reload() // A notification before first window must be safe.
controller.scheduleReload()
store.record(combo: "⌘T", keycode: 17, flags: CGEventFlags.maskCommand.rawValue,
             application: ApplicationIdentity(bundleID: "test.safari", name: "Safari"))
controller.showWindow()
controller.setState(.running)
controller.scheduleReload()
controller.scheduleReload()
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
let window = app.windows.first { $0.title == "热键统计" }!
precondition(window.contentView != nil && window.isVisible)
var actions = StatusBar.Actions()
var requested = false
var opened = false
var terminated = false
actions.requestPermission = { requested = true; return false }
actions.openURL = { _ in opened = true; return false }
actions.terminate = { _ in terminated = true }
var loginOperations = LoginSystemOperations()
loginOperations.isApp = { true }
var loginState = SMAppService.Status.notRegistered
loginOperations.status = { loginState }
loginOperations.register = {}
let status = StatusBar(store: store, actions: actions, loginLaunch: LoginLaunch(operations: loginOperations))
status.setState(.running)
status.refreshRanking()
let monitoring = MonitoringController(defaults: defaults, permission: { true }, start: { true }, stop: {})
status.monitoring = monitoring
status.install(windowController: controller)
for state in [MonitoringController.State.running, .paused, .permissionMissing, .failed] {
    status.setState(state)
    status.refreshRanking()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
let menu = NSMenu()
status.menuNeedsUpdate(menu)
precondition(menu.items.contains { $0.title.contains("Safari") }, "menu app source")
// Exercise controls through their real target/action wiring, using the injected store.
func activate(_ control: NSControl) {
    precondition(control.sendAction(control.action, to: control.target))
}
func activateMenu(_ title: String) {
    let item = menu.items.first { $0.title == title }!
    precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
}
activateMenu("暂停统计")
status.menuNeedsUpdate(menu)
precondition(menu.items.contains { $0.title == "继续统计" })
activateMenu("继续统计")
status.menuNeedsUpdate(menu)
activateMenu("重新检查权限")
activateMenu("打开输入监控设置…")
precondition(requested && opened, "permission actions use injected system interfaces")
activateMenu("登录时启动")
loginState = .enabled
status.menuNeedsUpdate(menu)
precondition(menu.items.first { $0.title == "登录时启动" }!.state == .on)
loginState = .notRegistered
activateMenu("打开统计窗口…")
activateMenu("退出 HotkeyStats")
precondition(terminated, "quit action saves and delegates termination")
let controls = window.contentView!.subviews
let popups = controls.compactMap { $0 as? NSPopUpButton }
let appFilter = popups.first { $0.itemTitles.contains("全部应用") }!
let tableRange = popups.first { $0.itemTitles.contains("全部累计") }!
let chartRange = popups.first { $0.itemTitles == ["7 天", "30 天"] }!
let ignore = controls.compactMap { $0 as? NSButton }.first { $0.title == "忽略所选应用" }!
let conflict = controls.compactMap { $0 as? NSButton }.first { $0.title == "高频提醒" }!
let threshold = controls.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
let table = controls.compactMap { $0 as? NSScrollView }.first!.documentView as! NSTableView
for _ in 0..<20 {
    store.record(combo: "⌘T", keycode: 17, flags: CGEventFlags.maskCommand.rawValue,
        application: ApplicationIdentity(bundleID: "test.editor", name: "Editor"))
    store.record(combo: "⌘T", keycode: 17, flags: CGEventFlags.maskCommand.rawValue,
        application: ApplicationIdentity(bundleID: "test.safari", name: "Safari"))
}
store.record(combo: "⌘A", keycode: 0, flags: CGEventFlags.maskCommand.rawValue)
controller.reload()
table.sortDescriptors = []
controller.tableView(table, sortDescriptorsDidChange: [])
table.sortDescriptors = [NSSortDescriptor(key: nil, ascending: true)]
controller.tableView(table, sortDescriptorsDidChange: [])
table.sortDescriptors = [NSSortDescriptor(key: "总次数", ascending: false)]
controller.tableView(table, sortDescriptorsDidChange: [])
tableRange.removeAllItems()
controller.reload()
tableRange.addItems(withTitles: ["全部累计", "今日", "7 天", "30 天"])
for index in 0..<tableRange.numberOfItems {
    tableRange.selectItem(at: index)
    activate(tableRange)
    precondition(controller.numberOfRows(in: table) == 2, "time range includes recorded combos")
}
appFilter.selectItem(withTitle: "Safari")
activate(appFilter)
precondition(controller.numberOfRows(in: table) == 1, "app filter")
for column in table.tableColumns {
    let cell = controller.tableView(table, viewFor: column, row: 0) as! NSTextField
    if column.title == "应用来源" { precondition(cell.stringValue == "Safari") }
}
precondition(controller.tableView(table, viewFor: nil, row: 0) == nil, "nil column")
let unsupported = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("unsupported"))
precondition((controller.tableView(table, viewFor: unsupported, row: 0) as! NSTextField).stringValue.isEmpty)
let todayColumn = table.tableColumns.first { $0.title == "今日" }!
now.addTimeInterval(86400)
precondition((controller.tableView(table, viewFor: todayColumn, row: 0) as! NSTextField).stringValue == "0", "stale day snapshot")
now.addTimeInterval(-86400)
ignore.state = .on
activate(ignore)
precondition(store.ignoredBundleIDs == ["test.safari"], "ignore switch writes isolated settings")
ignore.state = .off
activate(ignore)
precondition(store.ignoredBundleIDs.isEmpty, "ignore switch restored")
threshold.stringValue = "1"
activate(threshold)
threshold.stringValue = "0"
activate(threshold)
precondition(threshold.stringValue == "1", "invalid threshold resets to saved positive value")
conflict.state = .off
activate(conflict)
conflict.state = .on
activate(conflict)
chartRange.selectItem(at: 1)
activate(chartRange)
table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
appFilter.selectItem(withTitle: "未知应用")
activate(appFilter)
precondition(controller.numberOfRows(in: table) == 1 && !ignore.isEnabled, "unknown app filter")
appFilter.selectItem(at: 0)
activate(appFilter)
activate(ignore)
table.deselectAll(nil)
controller.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
let refresh = controls.compactMap { $0 as? NSButton }.first { $0.title == "刷新" }!
activate(refresh)
let imageURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("dist/coverage/window.png")
if let bitmap = window.contentView!.bitmapImageRepForCachingDisplay(in: window.contentView!.bounds) {
    window.contentView!.cacheDisplay(in: window.contentView!.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: imageURL)
}
appFilter.selectItem(withTitle: "Safari")
activate(appFilter)
store.clear()
let sourceColumn = table.tableColumns.first { $0.title == "应用来源" }!
precondition((controller.tableView(table, viewFor: sourceColumn, row: 0) as! NSTextField).stringValue == "test.safari",
             "source fallback during pending reload")
store.record(combo: "⌘T", keycode: 17, flags: CGEventFlags.maskCommand.rawValue,
             application: ApplicationIdentity(bundleID: "test.safari", name: "Safari"))
controller.reload()
let clear = controls.compactMap { $0 as? NSButton }.first { $0.title == "清空统计" }!
DispatchQueue.main.async { NSApp.stopModal(withCode: .alertSecondButtonReturn) }
activate(clear)
precondition(!store.records.isEmpty, "clear cancelled")
DispatchQueue.main.async { NSApp.stopModal(withCode: .alertFirstButtonReturn) }
activate(clear)
precondition(store.records.isEmpty, "clear confirmed on isolated store")
let badURL = directory.appendingPathComponent("bad.json")
try Data("invalid".utf8).write(to: badURL)
let badStore = StatsStore(fileURL: badURL)
let warningStatus = StatusBar(store: badStore, actions: actions)
warningStatus.install(windowController: controller)
let warningMenu = NSMenu()
warningStatus.menuNeedsUpdate(warningMenu)
let retry = warningMenu.items.first { $0.title == "重试保存" }!
precondition(NSApp.sendAction(retry.action!, to: retry.target, from: retry))
controller.reload()
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
status.menuNeedsUpdate(menu)
precondition(menu.items.contains { $0.title.contains("暂无数据") }, "empty menu")
window.close()
controller.reload()
controller.showWindow()
precondition(window.isVisible, "closed window safely reopened")
window.close()
func testDisposableController() {
    let disposable = StatsWindowController(store: store, settings: AnalyticsSettings(defaults: defaults))
    disposable.reload()
}
testDisposableController()
struct LegacyWindowFixture: Codable { let schemaVersion: Int; let records: [HotkeyRecord] }
let legacyURL = directory.appendingPathComponent("legacy-window.json")
let legacyRow = HotkeyRecord(combo: "⌘T", keycode: 17, flagsRaw: CGEventFlags.maskCommand.rawValue,
                            count: 1, todayCount: 1, todayDate: DayKey.today, firstSeen: now, lastSeen: now)
try JSONEncoder().encode(LegacyWindowFixture(schemaVersion: 2, records: [legacyRow])).write(to: legacyURL)
let disabledSettings = AnalyticsSettings(defaults: defaults)
disabledSettings.enabled = false
let legacyController = StatsWindowController(store: StatsStore(fileURL: legacyURL), settings: disabledSettings)
legacyController.showWindow()
for window in NSApp.windows where window.title == "热键统计" { window.close() }
checkLifecycle(store: store, defaults: defaults, directory: directory)
checkReviewRegressions(directory: directory)
print("PASS: isolated AppKit window, chart hosting, filters, settings, menu and reopen")
