import AppKit

/// 菜单栏常驻入口：Top 5 快捷视图 + 今日统计 + 主窗口入口 + 退出。
final class StatusBar: NSObject, NSMenuDelegate {

    struct Actions {
        var requestPermission = CGRequestListenEventAccess
        var openURL: (URL) -> Bool = NSWorkspace.shared.open
        var terminate: (Any?) -> Void = NSApplication.shared.terminate
    }
    private let actions: Actions
    private let store: StatsStore
    init(store: StatsStore = .shared, actions: Actions = Actions(), loginLaunch: LoginLaunch = LoginLaunch()) {
        self.actions = actions
        self.loginLaunch = loginLaunch
        self.store = store
        super.init()
    }
    var monitoring: MonitoringController?
    private let loginLaunch: LoginLaunch
    private var state: MonitoringController.State = .paused
    private var statusItem: NSStatusItem?
    private weak var windowController: StatsWindowController?

    func install(windowController: StatsWindowController) {
        self.windowController = windowController

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ""
        item.button?.toolTip = "HotkeyStats — 热键统计"

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        setState(state)
    }

    func setState(_ state: MonitoringController.State) {
        self.state = state
        guard let button = statusItem?.button else { return }
        button.image = Self.icons[state]
        refreshRanking()
    }

    func refreshRanking() {
        guard let button = statusItem?.button else { return }
        let leader = store.todayLeader
        let title = RankingPresentation.title(leader: leader, running: state == .running)
        if button.title != title { button.title = title }
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        let hint = "HotkeyStats — " + state.rawValue +
            (state == .running && leader != nil ? " ｜ 今日第一名 " + leader! : "")
        if button.toolTip != hint {
            button.toolTip = hint
            button.setAccessibilityLabel(hint)
        }
    }

    /// 彩色应用图标不设为 template，避免系统将薄荷绿与黑底变成单色。
    /// 缓存四种状态，周期性权限检查不重复生成图像。
    private static let icons: [MonitoringController.State: NSImage] = {
        let base = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage(size: NSSize(width: 22, height: 22))
        var result: [MonitoringController.State: NSImage] = [:]
        for state in [MonitoringController.State.running, .paused, .permissionMissing, .failed] {
            let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
                base.draw(in: NSRect(x: 0, y: 1, width: 20, height: 20))
                if state != .running {
                    let badge = NSRect(x: 12, y: 0, width: 10, height: 10)
                    let color: NSColor = state == .failed ? .systemRed : .systemOrange
                    color.setFill()
                    NSBezierPath(ovalIn: badge).fill()
                    // 形状和文字共同区分状态，不仅依靠颜色。
                    let glyph = state == .paused ? "Ⅱ" : (state == .permissionMissing ? "!" : "×")
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor.black
                    ]
                    let size = (glyph as NSString).size(withAttributes: attributes)
                    (glyph as NSString).draw(at: NSPoint(x: badge.midX - size.width / 2,
                                                        y: badge.midY - size.height / 2),
                                              withAttributes: attributes)
                }
                return true
            }
            image.isTemplate = false
            result[state] = image
        }
        return result
    }()

    // MARK: 菜单内容（每次打开前动态重建）

    func menuNeedsUpdate(_ menu: NSMenu) {
        monitoring?.refresh()
        menu.removeAllItems()

        let top = store.sortedByCount.prefix(5)
        if let issue = store.storageIssue {
            let warning = NSMenuItem(title: "⚠ " + issue, action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            let retry = NSMenuItem(title: "重试保存", action: #selector(retrySave), keyEquivalent: "")
            retry.target = self
            menu.addItem(retry)
            menu.addItem(.separator())
        }

        let header = NSMenuItem(title: "— 使用最多的热键 —", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if top.isEmpty {
            let empty = NSMenuItem(title: "暂无数据，去按几个快捷键吧", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for r in top {
                let item = NSMenuItem(
                    title: "\(r.combo)   \(r.count) 次 — 记录于 \(store.source(for: r.combo))",
                    action: nil, keyEquivalent: ""
                )
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let today = NSMenuItem(
            title: "今日累计 \(store.todayTotal) 次 ｜ 共 \(store.records.count) 种组合键",
            action: nil, keyEquivalent: ""
        )
        today.isEnabled = false
        menu.addItem(today)

        menu.addItem(.separator())

        let open = NSMenuItem(title: "打开统计窗口…", action: #selector(openWindow), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        for (title, action) in [
            (monitoring?.isPaused == true ? "继续统计" : "暂停统计", #selector(togglePause)),
            ("重新检查权限", #selector(recheck)),
            ("打开输入监控设置…", #selector(openPermissions))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let login = NSMenuItem(title: loginLaunch.title, action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.isEnabled = loginLaunch.available
        login.state = loginLaunch.enabled ? .on : .off
        menu.addItem(login)
        let quit = NSMenuItem(title: "退出 HotkeyStats", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func retrySave() { store.save() }

    @objc private func togglePause() { monitoring?.togglePause() }
    @objc private func recheck() { monitoring?.refresh() }
    @objc private func toggleLogin() { loginLaunch.toggle() }
    @objc private func openPermissions() {
        _ = actions.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            _ = actions.openURL(url)
        }
    }

    @objc private func openWindow() {
        windowController?.showWindow()
    }

    @objc private func quit() {
        store.save()
        actions.terminate(nil)
    }
}
