import Foundation
import Darwin

/// Held for the lifetime of the primary process; never unlink the lock file.
final class InstanceLock {
    private let descriptor: Int32
    init?(url: URL, acquire: (Int32) -> Int32 = { flock($0, LOCK_EX | LOCK_NB) }) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if acquire(descriptor) != 0 {
            let code = errno
            Darwin.close(descriptor)
            if code == EWOULDBLOCK { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }
    deinit { Darwin.close(descriptor) }
}

enum CountingPolicy {
    static func accepts(isRunning: Bool, autorepeat: Int64) -> Bool {
        isRunning && autorepeat == 0
    }
}

final class MonitoringController {
    enum State: String {
        case running = "统计中", paused = "已暂停", permissionMissing = "无权限", failed = "监听失败"
    }
    private(set) var state: State = .paused
    private var lastLoggedState: State?
    var onChange: ((State) -> Void)?
    private let defaults: UserDefaults
    private let permission: () -> Bool
    private let start: () -> Bool
    private let stop: () -> Void
    var isPaused: Bool { defaults.bool(forKey: "isPaused") }
    init(defaults: UserDefaults, permission: @escaping () -> Bool,
         start: @escaping () -> Bool, stop: @escaping () -> Void) {
        self.defaults = defaults; self.permission = permission
        self.start = start; self.stop = stop
    }
    func shutdown() { stop() }
    func togglePause() {
        // 用户暂停意图独立于权限，授权恢复后不能自动取消暂停。
        AppLogger.shared.log(.info, isPaused ? .resumeRequested : .pauseRequested)
        defaults.set(!isPaused, forKey: "isPaused")
        refresh()
    }
    func refresh() {
        if !permission() { stop(); state = .permissionMissing }
        else if isPaused { stop(); state = .paused }
        else if start() { state = .running }
        else { stop(); state = .failed }
        // 每五秒刷新仍通知界面处理跨天展示，但只记录首次状态和状态变化，避免刷屏。
        if lastLoggedState != state {
            switch state {
            case .running: AppLogger.shared.log(.info, .running)
            case .paused: AppLogger.shared.log(.info, .paused)
            case .permissionMissing: AppLogger.shared.log(.warning, .permissionMissing)
            case .failed: AppLogger.shared.log(.error, .monitoringFailed)
            }
            lastLoggedState = state
        }
        onChange?(state)
    }
}
