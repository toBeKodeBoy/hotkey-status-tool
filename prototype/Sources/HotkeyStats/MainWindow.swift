import AppKit
import SwiftUI

/// 主统计窗口：NSTableView 全量展示，按总次数降序。
final class StatsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var tableView: NSTableView!
    private var summaryLabel: NSTextField!
    private var state: MonitoringController.State = .paused
    private var sortKey = "总次数"
    private var ascending = false
    private var emptyLabel: NSTextField!
    private var data: [HotkeyRecord] = []

    private let store: StatsStore
    private let settings: AnalyticsSettings
    private var appFilter: NSPopUpButton!
    private var rangeFilter: NSPopUpButton!
    private var tableRange: NSPopUpButton!
    private var reloadTimer: Timer?
    private var conflictToggle: NSButton!
    private var ignoreToggle: NSButton!
    private var thresholdField: NSTextField!
    private var chart: NSHostingView<TrendView>!
    private var selectedCombo: String?

    init(store: StatsStore = .shared, settings: AnalyticsSettings = AnalyticsSettings()) {
        self.store = store
        self.settings = settings
        super.init()
    }

    func setState(_ state: MonitoringController.State) {
        self.state = state
        reload()
    }

    func showWindow() {
        if window == nil { buildWindow() }
        reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: UI 构建

    private func buildWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        win.isReleasedWhenClosed = false
        win.title = "热键统计"
        win.delegate = self
        win.center()

        // 汇总行
        summaryLabel = NSTextField(labelWithString: "")
        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.frame = NSRect(x: 16, y: 0, width: 728, height: 24)
        summaryLabel.autoresizingMask = [.width]

        // 表格
        tableView = NSTableView()
        let columns: [(String, CGFloat)] =
            [("组合键", 120), ("应用来源", 200), ("总次数", 90), ("今日", 80), ("最近使用", 180)]
        for (title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
            col.title = title == "总次数" ? "范围次数" : title
            col.width = width
            if ["总次数", "今日", "最近使用"].contains(title) { col.sortDescriptorPrototype = NSSortDescriptor(key: title, ascending: false) }
            tableView.addTableColumn(col)
        }
        tableView.sortDescriptors = [NSSortDescriptor(key: "总次数", ascending: false)]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowSizeStyle = .default
        tableView.allowsColumnResizing = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.frame = NSRect(x: 0, y: 24, width: 760, height: 260)

        // 清空按钮
        let clearButton = NSButton(title: "清空统计", target: self, action: #selector(clearStats))
        clearButton.bezelStyle = .rounded
        clearButton.frame = NSRect(x: 16, y: 600, width: 90, height: 28)
        clearButton.autoresizingMask = [.maxXMargin, .minYMargin]

        let refreshButton = NSButton(title: "刷新", target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: 114, y: 600, width: 70, height: 28)
        refreshButton.autoresizingMask = [.maxXMargin, .minYMargin]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 640))
        container.addSubview(summaryLabel)
        container.addSubview(scroll)
        emptyLabel = NSTextField(wrappingLabelWithString: "")
        emptyLabel.frame = NSRect(x: 30, y: 160, width: 700, height: 80)
        emptyLabel.alignment = .center
        emptyLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        container.addSubview(emptyLabel)
        container.addSubview(clearButton)
        container.addSubview(refreshButton)

        tableRange = NSPopUpButton(frame: NSRect(x: 204, y: 600, width: 130, height: 26))
        tableRange.addItems(withTitles: ["全部累计", "今日", "7 天", "30 天"])
        tableRange.target = self
        tableRange.action = #selector(filterChanged)
        tableRange.autoresizingMask = [.minYMargin]
        container.addSubview(tableRange)
        appFilter = NSPopUpButton(frame: NSRect(x: 16, y: 558, width: 220, height: 26))
        appFilter.target = self
        appFilter.action = #selector(filterChanged)
        rangeFilter = NSPopUpButton(frame: NSRect(x: 244, y: 558, width: 110, height: 26))
        rangeFilter.addItems(withTitles: ["7 天", "30 天"])
        rangeFilter.target = self
        rangeFilter.action = #selector(filterChanged)
        conflictToggle = NSButton(checkboxWithTitle: "高频提醒", target: self, action: #selector(settingsChanged))
        conflictToggle.frame = NSRect(x: 360, y: 558, width: 95, height: 26)
        conflictToggle.state = settings.enabled ? .on : .off
        thresholdField = NSTextField(string: String(settings.threshold))
        thresholdField.frame = NSRect(x: 460, y: 558, width: 60, height: 24)
        thresholdField.target = self
        thresholdField.action = #selector(settingsChanged)
        thresholdField.toolTip = "每应用 7 天次数阈值（正整数，回车保存）"
        ignoreToggle = NSButton(checkboxWithTitle: "忽略所选应用", target: self, action: #selector(ignoreChanged))
        ignoreToggle.frame = NSRect(x: 530, y: 558, width: 150, height: 26)
        chart = NSHostingView(rootView: TrendView(points: [], notice: "", conflicts: "", details: ""))
        chart.frame = NSRect(x: 0, y: 290, width: 760, height: 258)
        chart.autoresizingMask = [.width, .minYMargin]
        for control in [appFilter!, rangeFilter!, conflictToggle!, thresholdField!, ignoreToggle!] as [NSView] {
            control.autoresizingMask = [.minYMargin]
            container.addSubview(control)
        }
        container.addSubview(chart)
        win.minSize = NSSize(width: 760, height: 640)
        win.contentView = container
        window = win
    }

    // MARK: 数据

    func scheduleReload() {
        guard window != nil, reloadTimer == nil else { return }
        reloadTimer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.reloadTimer = nil
            self?.reload()
        }
        RunLoop.main.add(reloadTimer!, forMode: .common)
    }
    deinit { reloadTimer?.invalidate() }

    func reload() {
        guard window != nil else { return }
        let selectedID = appFilter.selectedItem?.representedObject as? String
        let wasUnknown = appFilter.selectedItem?.representedObject is NSNull
        appFilter.removeAllItems()
        appFilter.addItem(withTitle: "全部应用")
        if store.applicationRecords.contains(where: { $0.application.bundleID == nil }) {
            appFilter.addItem(withTitle: "未知应用")
            appFilter.lastItem?.representedObject = NSNull()
        }
        var applications: [String: String] = [:]
        for item in store.applicationRecords {
            if let id = item.application.bundleID { applications[id] = item.application.name }
        }
        for id in applications.keys.sorted() {
            appFilter.addItem(withTitle: applications[id]!)
            appFilter.lastItem?.representedObject = id
        }
        if let selectedID, let item = appFilter.itemArray.first(where: { $0.representedObject as? String == selectedID }) {
            appFilter.select(item)
        }
        if wasUnknown, let item = appFilter.itemArray.first(where: { $0.representedObject is NSNull }) {
            appFilter.select(item)
        }
        let unknownOnly = appFilter.selectedItem?.representedObject is NSNull
        let appID = appFilter.selectedItem?.representedObject as? String
        ignoreToggle.isEnabled = appID != nil
        ignoreToggle.state = appID.map { settings.ignored.contains($0) } == true ? .on : .off
        var scopedRecords = Array(store.records(bundleID: appID, unknownOnly: unknownOnly).values)
        let tableDays = [0, 1, 7, 30][min(3, max(0, tableRange.indexOfSelectedItem))]
        if tableDays > 0 {
            for position in scopedRecords.indices {
                scopedRecords[position].count = store.trend(days: tableDays, bundleID: appID,
                    combo: scopedRecords[position].combo, unknownOnly: unknownOnly).reduce(0) { $0 + $1.count }
            }
            scopedRecords.removeAll { $0.count == 0 }
        }
        data = RecordOrdering.sorted(scopedRecords, key: sortKey,
                                     ascending: ascending, today: store.today)
        emptyLabel.isHidden = !data.isEmpty
        let hints: [MonitoringController.State: String] = [.running: "使用快捷键后，这里会显示统计。", .paused: "请从菜单继续统计。", .permissionMissing: "请从菜单打开输入监控设置并授权。", .failed: "请重新检查权限；若系统要求，请退出后重新打开。"]
        emptyLabel.stringValue = state.rawValue + "\n" + hints[state]!
        let today = store.records(bundleID: appID, unknownOnly: unknownOnly).values.reduce(0) { $0 + $1.todayCount }
        summaryLabel.stringValue =
            "共 \(data.count) 种组合键（\(tableRange.titleOfSelectedItem ?? "")) ｜ \(state.rawValue) ｜ 今日累计 \(today) 次 ｜ 数据仅保存在本机"
        let days = rangeFilter.indexOfSelectedItem == 0 ? 7 : 30
        let warning = store.conflicts(threshold: settings.threshold, enabled: settings.enabled)
            .filter { conflict in
                !unknownOnly && (selectedCombo == nil || conflict.combo == selectedCombo) &&
                (appID == nil || conflict.applications.contains { $0.0.bundleID == appID })
            }
            .map { conflict in
                conflict.combo + "：多应用高频使用（7 天） " + conflict.applications.map { "\($0.0.name) \($0.1)次" }.joined(separator: "、")
            }.joined(separator: "；")
        let details = store.applicationRecords.filter {
            (appID == nil || $0.application.bundleID == appID) && (selectedCombo == nil || $0.combo == selectedCombo) && (!unknownOnly || $0.application.bundleID == nil)
        }.sorted { $0.combo < $1.combo }.map {
            "\($0.combo) — 记录于 \($0.application.name)：累计 \($0.count) 次"
        }.joined(separator: "\n")
        let notice = "统计时区：" + store.statisticsCalendar.timeZone.identifier +
            (store.hasUndatedHistory ? " ｜ 升级前日期时区未知，未纳入趋势" : "") +
            (selectedCombo.map { " ｜ " + $0 } ?? " ｜ 全部组合键")
        chart.rootView = TrendView(points: store.trend(days: days, bundleID: appID, combo: selectedCombo, unknownOnly: unknownOnly),
                                   notice: notice, conflicts: warning, details: details)
        tableView.reloadData()
    }

    @objc private func refresh() { selectedCombo = nil; reload() }
    @objc private func filterChanged() { selectedCombo = nil; reload() }
    @objc private func settingsChanged() {
        settings.enabled = conflictToggle.state == .on
        if let threshold = Int(thresholdField.stringValue), threshold > 0 { settings.threshold = threshold }
        thresholdField.stringValue = String(settings.threshold)
        reload()
    }
    @objc private func ignoreChanged() {
        guard let id = appFilter.selectedItem?.representedObject as? String else { return }
        var ignored = settings.ignored
        if ignoreToggle.state == .on { ignored.insert(id) } else { ignored.remove(id) }
        settings.ignored = ignored
        store.ignoredBundleIDs = ignored
        reload()
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < data.count else { return }
        let combo = data[row].combo
        if selectedCombo != combo { selectedCombo = combo; reload() }
    }

    @objc private func clearStats() {
        let alert = NSAlert()
        alert.messageText = "清空所有热键统计数据？"
        alert.informativeText = "此操作不可恢复。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear()
        }
    }
}

extension StatsWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        if let descriptor = tableView.sortDescriptors.first {
            sortKey = descriptor.key ?? "总次数"
            ascending = descriptor.ascending
        }
        reload()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { data.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        let r = data[row]
        let text: String
        switch id {
        case "组合键": text = r.combo
        case "应用来源": text = (appFilter.selectedItem?.representedObject as? String).map { id in
            store.applicationRecords.first { $0.application.bundleID == id }?.application.name ?? id
        } ?? store.source(for: r.combo)
        case "总次数": text = "\(r.count)"
        case "今日": text = r.todayDate == store.today ? "\(r.todayCount)" : "0"
        case "最近使用":
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = store.statisticsCalendar.timeZone
            f.dateFormat = "MM-dd HH:mm"
            text = f.string(from: r.lastSeen)
        default: text = ""
        }
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("cell"), owner: nil)
            as? NSTextField ?? {
                let t = NSTextField(labelWithString: "")
                t.identifier = NSUserInterfaceItemIdentifier("cell")
                return t
            }()
        cell.stringValue = text
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }
}
