import AppKit

func checkLifecycle(store: StatsStore, defaults: UserDefaults, directory: URL) {
    precondition(DataLocation.directory(environment: ["HOTKEYSTATS_DATA_DIR": directory.path]).path == directory.path)
    precondition(DataLocation.directory(environment: [:]).lastPathComponent == "HotkeyStats")
    precondition(DataLocation.directory(environment: ["HOTKEYSTATS_DATA_DIR": "relative"]).lastPathComponent == "HotkeyStats")
    let root = directory.appendingPathComponent("notification-root")
    let other = directory.appendingPathComponent("other-root")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let alias = directory.appendingPathComponent("notification-alias")
    try! FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
    precondition(DataLocation.reopenNotification(directory: root) == DataLocation.reopenNotification(directory: alias),
                 "same physical data root uses the same notification")
    precondition(DataLocation.reopenNotification(directory: root) != DataLocation.reopenNotification(directory: other),
                 "independent data roots never share notification channels")
    var ownNotifications = 0
    var foreignNotifications = 0
    let center = DistributedNotificationCenter.default()
    let own = center.addObserver(forName: DataLocation.reopenNotification(directory: root), object: nil, queue: .main) { _ in ownNotifications += 1 }
    let foreign = center.addObserver(forName: DataLocation.reopenNotification(directory: other), object: nil, queue: .main) { _ in foreignNotifications += 1 }
    ApplicationBootstrap().announce(root)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    precondition(ownNotifications == 1 && foreignNotifications == 0, "reopen delivery is isolated")
    center.removeObserver(own)
    center.removeObserver(foreign)
    var bootstrap = ApplicationBootstrap()
    bootstrap.directory = directory.appendingPathComponent("bootstrap")
    bootstrap.runApplication = {}
    precondition(bootstrap.run() == 0, "primary lock")
    bootstrap.acquire = { _ in nil }
    precondition(bootstrap.run() == 0, "duplicate notification")
    bootstrap.createDirectory = { _ in throw NSError(domain: "fixture", code: 1) }
    DispatchQueue.main.async { NSApp.stopModal(withCode: .alertFirstButtonReturn) }
    precondition(bootstrap.run() == 1, "startup failure visible")
    var allowed = false
    let monitoring = MonitoringController(defaults: defaults, permission: { allowed }, start: { true }, stop: {})
    let delegate = AppDelegate(store: store, defaults: defaults, monitoring: monitoring)
    let notification = Notification(name: NSApplication.didFinishLaunchingNotification)
    delegate.applicationDidFinishLaunching(notification)
    store.record(combo: "⌘L", keycode: 37, flags: CGEventFlags.maskCommand.rawValue)
    delegate.saveTimer?.fire()
    delegate.permissionTimer?.fire()
    delegate.dayTimer?.fire()
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    NotificationCenter.default.post(name: NSNotification.Name.NSSystemClockDidChange, object: nil)
    allowed = true
    delegate.applicationDidBecomeActive(notification)
    precondition(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
    DistributedNotificationCenter.default().postNotificationName(
        store.reopenNotification, object: nil, userInfo: nil, deliverImmediately: true)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    delegate.applicationWillTerminate(notification)
    delegate.applicationWillTerminate(notification)
    for window in NSApp.windows where window.title == "热键统计" { window.close() }
    _ = AppDelegate(store: store, defaults: defaults) // Native callbacks are bound, never invoked here.
    let operations = LoginSystemOperations()
    _ = operations.isApp()
    _ = operations.status() // Read-only system status discovery.
    DispatchQueue.main.async { NSApp.stopModal(withCode: .alertFirstButtonReturn) }
    operations.showError()
    _ = LoginLaunch(operations: operations)
}
