import AppKit

protocol FrontmostApplicationProviding {
    func current() -> ApplicationIdentity
}
struct WorkspaceApplicationProvider: FrontmostApplicationProviding {
    var snapshot: () -> (bundleID: String?, name: String?)? = {
        workspaceSnapshot(application: NSWorkspace.shared.frontmostApplication)
    }
    static func workspaceSnapshot(application: NSRunningApplication?) -> (bundleID: String?, name: String?)? {
        guard let application else { return nil }
        return (application.bundleIdentifier, application.localizedName)
    }
    func current() -> ApplicationIdentity {
        guard let app = snapshot(), let id = app.bundleID, !id.isEmpty else { return .unknown }
        return ApplicationIdentity(bundleID: id, name: app.name == "" ? id : (app.name ?? id))
    }
}

/// Capture context synchronously after filtering; UI work must never sample it later.
struct HotkeyRecorder {
    let store: StatsStore
    let provider: FrontmostApplicationProviding
    @discardableResult
    func receive(keycode: Int, flags: UInt64, running: Bool, autorepeat: Int64) -> Bool {
        guard CountingPolicy.accepts(isRunning: running, autorepeat: autorepeat) else { return false }
        let parsed = ComboParser.parse(keycode: keycode, flagsRaw: flags)
        guard parsed.isHotkey else { return false }
        guard store.record(combo: parsed.combo, keycode: keycode, flags: flags,
                           application: provider.current()) else { return false }
        AppLogger.shared.logHotkey(parsed.combo)
        return true
    }
}

final class AnalyticsSettings {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var threshold: Int {
        get { max(1, defaults.object(forKey: "conflictThreshold") as? Int ?? 20) }
        set { defaults.set(max(1, newValue), forKey: "conflictThreshold") }
    }
    var enabled: Bool {
        get { defaults.object(forKey: "conflictsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "conflictsEnabled") }
    }
    var ignored: Set<String> {
        get { Set(defaults.stringArray(forKey: "ignoredApplications") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "ignoredApplications") }
    }
}
