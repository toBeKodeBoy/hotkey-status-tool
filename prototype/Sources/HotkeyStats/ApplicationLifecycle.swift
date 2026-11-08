import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusbar: StatusBar
    private let statsWindow: StatsWindowController
    private let store: StatsStore
    private let defaults: UserDefaults
    private(set) var saveTimer: Timer?
    private(set) var permissionTimer: Timer?
    private(set) var dayTimer: Timer?
    private var dayObservers: [NSObjectProtocol] = []
    private var reopenObserver: NSObjectProtocol?
    private let monitoring: MonitoringController
    init(store: StatsStore = .shared, defaults: UserDefaults = .standard,
         monitoring: MonitoringController? = nil) {
        self.store = store
        self.defaults = defaults
        self.statusbar = StatusBar(store: store)
        self.statsWindow = StatsWindowController(store: store, settings: AnalyticsSettings(defaults: defaults))
        self.monitoring = monitoring ?? MonitoringController(defaults: defaults,
            permission: CGPreflightListenEventAccess,
            start: EventTapMonitor.shared.start, stop: EventTapMonitor.shared.stop)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.log(.info, .started)
        NSApp.setActivationPolicy(.accessory)   // Info.plist 的 LSUIElement 已隐藏 Dock；此处兜底

        statusbar.install(windowController: statsWindow)
        statusbar.monitoring = monitoring
        store.ignoredBundleIDs = AnalyticsSettings(defaults: defaults).ignored
        store.onChange = { [weak self] in
            self?.statusbar.refreshRanking()
            self?.statsWindow.scheduleReload()
        }
        refreshDay()
        dayObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshDay() })
        dayObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshDay() })
        monitoring.onChange = { [weak self] state in
            self?.statusbar.setState(state)
            self?.statsWindow.setState(state)
        }
        reopenObserver = DistributedNotificationCenter.default().addObserver(
            forName: store.reopenNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.statsWindow.showWindow() }
        monitoring.refresh()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.monitoring.refresh()
        }

        // 定时落盘：每 5 分钟
        saveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.store.save()
        }
    }

    private func refreshDay() {
        statusbar.refreshRanking()
        statsWindow.reload()
        dayTimer?.invalidate()
        let calendar = store.statisticsCalendar.calendar
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        dayTimer = Timer(fire: nextDay, interval: 0, repeats: false) { [weak self] _ in self?.refreshDay() }
        RunLoop.main.add(dayTimer!, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        dayTimer?.invalidate()
        permissionTimer?.invalidate()
        saveTimer?.invalidate()
        for observer in dayObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        monitoring.shutdown()
        if let observer = reopenObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            reopenObserver = nil
        }
        dayObservers.removeAll()
        store.save()
        AppLogger.shared.log(.info, .stopped)
        AppLogger.shared.flush()
    }

    func applicationDidBecomeActive(_ notification: Notification) { monitoring.refresh() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statsWindow.showWindow()
        return true
    }

}
