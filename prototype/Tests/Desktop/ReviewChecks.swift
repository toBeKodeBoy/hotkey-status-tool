import AppKit
import SwiftUI

func checkReviewRegressions(directory: URL) {
    let suite = "HotkeyStats-review-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AnalyticsSettings(defaults: defaults)
    let store = StatsStore(fileURL: directory.appendingPathComponent("review.json"))
    let app = ApplicationIdentity(bundleID: "review.app", name: "Review App")
    let flags = CGEventFlags.maskCommand.rawValue
    store.record(combo: "⌘A", keycode: 0, flags: flags, application: app)
    let controller = StatsWindowController(store: store, settings: settings)
    controller.showWindow()
    let window = NSApp.windows.first { $0.title == "热键统计" && $0.isVisible }!
    let controls = window.contentView!.subviews
    let apps = controls.compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("全部应用") }!
    let ignore = controls.compactMap { $0 as? NSButton }.first { $0.title == "忽略所选应用" }!
    let table = controls.compactMap { $0 as? NSScrollView }.first!.documentView as! NSTableView
    func activate(_ control: NSControl) { precondition(control.sendAction(control.action, to: control.target)) }
    apps.selectItem(withTitle: "Review App")
    activate(apps)
    ignore.state = .on
    activate(ignore)
    store.clear()
    controller.reload()
    precondition(apps.itemArray.contains { $0.representedObject as? String == "review.app" },
                 "clearing records must retain ignored apps so users can unignore them")
    precondition(ignore.isEnabled && ignore.state == .on)
    ignore.state = .off
    activate(ignore)
    precondition(settings.ignored.isEmpty && store.ignoredBundleIDs.isEmpty)

    store.record(combo: "⌘A", keycode: 0, flags: flags, application: app)
    store.record(combo: "⌘T", keycode: 17, flags: flags, application: app)
    controller.reload()
    let comboColumn = table.tableColumns.first { $0.title == "组合键" }!
    func combo(at row: Int) -> String {
        (controller.tableView(table, viewFor: comboColumn, row: row) as! NSTextField).stringValue
    }
    let selected = (0..<controller.numberOfRows(in: table)).first { combo(at: $0) == "⌘A" }!
    table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
    controller.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
    for _ in 0..<5 { store.record(combo: "⌘T", keycode: 17, flags: flags, application: app) }
    controller.reload()
    precondition(table.selectedRow >= 0 && combo(at: table.selectedRow) == "⌘A",
                 "selection must follow combo identity after rank changes")
    let chart = controls.compactMap { $0 as? NSHostingView<TrendView> }.first!
    precondition(chart.rootView.notice.contains("⌘A"), "chart and selection agree")
    store.clear()
    controller.reload()
    precondition(table.selectedRow == -1 && !chart.rootView.notice.contains("⌘A"),
                 "removed selection resets the chart scope")
    window.close()
}
