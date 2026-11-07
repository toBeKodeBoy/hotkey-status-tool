import AppKit

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

    override init() {
        super.init()
        StatsStore.shared.onChange = { [weak self] in self?.reload() }
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
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
        summaryLabel.frame = NSRect(x: 16, y: 0, width: 528, height: 24)
        summaryLabel.autoresizingMask = [.width]

        // 表格
        tableView = NSTableView()
        let columns: [(String, CGFloat)] =
            [("组合键", 160), ("总次数", 90), ("今日", 80), ("最近使用", 180)]
        for (title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
            col.title = title
            col.width = width
            if title != "组合键" { col.sortDescriptorPrototype = NSSortDescriptor(key: title, ascending: false) }
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
        scroll.frame = NSRect(x: 0, y: 24, width: 560, height: 356)

        // 清空按钮
        let clearButton = NSButton(title: "清空统计", target: self, action: #selector(clearStats))
        clearButton.bezelStyle = .rounded
        clearButton.frame = NSRect(x: 16, y: 384, width: 90, height: 28)
        clearButton.autoresizingMask = [.maxXMargin, .minYMargin]

        let refreshButton = NSButton(title: "刷新", target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: 114, y: 384, width: 70, height: 28)
        refreshButton.autoresizingMask = [.maxXMargin, .minYMargin]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))
        container.addSubview(summaryLabel)
        container.addSubview(scroll)
        emptyLabel = NSTextField(wrappingLabelWithString: "")
        emptyLabel.frame = NSRect(x: 30, y: 160, width: 500, height: 80)
        emptyLabel.alignment = .center
        emptyLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        container.addSubview(emptyLabel)
        container.addSubview(clearButton)
        container.addSubview(refreshButton)

        win.contentView = container
        window = win
    }

    // MARK: 数据

    private func reload() {
        guard window != nil else { return }
        data = RecordOrdering.sorted(StatsStore.shared.sortedByCount, key: sortKey,
                                     ascending: ascending, today: DayKey.today)
        emptyLabel.isHidden = !data.isEmpty
        let hints: [MonitoringController.State: String] = [.running: "使用快捷键后，这里会显示统计。", .paused: "请从菜单继续统计。", .permissionMissing: "请从菜单打开输入监控设置并授权。", .failed: "请重新检查权限；若系统要求，请退出后重新打开。"]
        emptyLabel.stringValue = state.rawValue + "\n" + (hints[state] ?? "")
        let today = StatsStore.shared.todayTotal
        summaryLabel.stringValue =
            "共 \(data.count) 种组合键 ｜ \(state.rawValue) ｜ 今日累计 \(today) 次 ｜ 数据仅保存在本机"
        tableView.reloadData()
    }

    @objc private func refresh() { reload() }

    @objc private func clearStats() {
        let alert = NSAlert()
        alert.messageText = "清空所有热键统计数据？"
        alert.informativeText = "此操作不可恢复。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            StatsStore.shared.clear()
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
        case "总次数": text = "\(r.count)"
        case "今日": text = r.todayDate == DayKey.today ? "\(r.todayCount)" : "0"
        case "最近使用":
            let f = DateFormatter()
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
