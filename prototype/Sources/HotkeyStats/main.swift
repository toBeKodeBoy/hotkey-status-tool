import AppKit

// MARK: - 应用入口

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusbar = StatusBar()
    private let statsWindow = StatsWindowController()
    private var saveTimer: Timer?
    private var permissionTimer: Timer?
    private var reopenObserver: NSObjectProtocol?
    private let monitoring = MonitoringController(defaults: .standard,
        permission: { CGPreflightListenEventAccess() },
        start: { EventTapMonitor.shared.start() }, stop: { EventTapMonitor.shared.stop() })

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.log(.info, .started)
        NSApp.setActivationPolicy(.accessory)   // Info.plist 的 LSUIElement 已隐藏 Dock；此处兜底

        statusbar.install(windowController: statsWindow)
        statusbar.monitoring = monitoring
        monitoring.onChange = { [weak self] state in
            self?.statusbar.setState(state)
            self?.statsWindow.setState(state)
        }
        reopenObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.HotkeyStats.reopen"), object: nil, queue: .main
        ) { [weak self] _ in self?.statsWindow.showWindow() }
        monitoring.refresh()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.monitoring.refresh()
        }

        // 定时落盘：每 5 分钟
        saveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            StatsStore.shared.save()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventTapMonitor.shared.stop()
        StatsStore.shared.save()
        AppLogger.shared.log(.info, .stopped)
        AppLogger.shared.flush()
    }

    func applicationDidBecomeActive(_ notification: Notification) { monitoring.refresh() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statsWindow.showWindow()
        return true
    }

}

// MARK: - Top-level 启动

let lockDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("HotkeyStats", isDirectory: true)
let instanceLock: InstanceLock
do {
    try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
    guard let acquired = try InstanceLock(url: lockDirectory.appendingPathComponent("instance.lock")) else {
        AppLogger.shared.log(.info, .duplicateInstance)
        AppLogger.shared.flush()
        // Retry briefly so a primary instance still launching can install its observer.
        for _ in 0..<5 {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("local.HotkeyStats.reopen"), object: nil, userInfo: nil, deliverImmediately: true)
            Thread.sleep(forTimeInterval: 0.1)
        }
        exit(0)
    }
    instanceLock = acquired
} catch {
    AppLogger.shared.log(.error, .lockFailed)
    AppLogger.shared.flush()
    let alert = NSAlert()
    alert.messageText = "HotkeyStats 无法安全启动"
    alert.informativeText = "无法获取单实例锁。请检查应用支持目录的访问权限后重试。"
    alert.runModal()
    exit(1)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
