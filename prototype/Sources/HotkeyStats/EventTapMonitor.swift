import CoreGraphics
import Foundation

/// 全局按键监听（CGEventTap，listen-only：只旁路观察，不拦截不修改任何事件）。
final class EventTapMonitor {

    static let shared = EventTapMonitor()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var enabled = false
    struct Services {
        var create = CGEvent.tapCreate
        var isValid = CFMachPortIsValid
        var enable = CGEvent.tapEnable
        var makeSource = CFMachPortCreateRunLoopSource
        var addSource = CFRunLoopAddSource
        var removeSource = CFRunLoopRemoveSource
        var invalidate = CFMachPortInvalidate
    }
    private let services: Services
    private let store: StatsStore

    init(store: StatsStore = .shared, services: Services = Services()) {
        self.services = services
        self.store = store
    }

    /// 在主 RunLoop 上安装事件监听。返回是否创建成功（失败通常是辅助功能未授权）。
    @discardableResult
    func start() -> Bool {
        if let tap {
            if services.isValid(tap) { return true }
            stop()
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = services.create(
            .cgSessionEventTap,
            .headInsertEventTap,
            .listenOnly,              // ★ 合规底线：只听不拦
            mask, { _, type, event, refcon in
                let monitor = Unmanaged<EventTapMonitor>
                    .fromOpaque(refcon!).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            refcon
        ) else {
            AppLogger.shared.log(.error, .monitorFailed)
            return false
        }

        self.tap = tap
        enabled = true
        services.enable(tap, true)

        guard let source = services.makeSource(kCFAllocatorDefault, tap, 0) else {
            AppLogger.shared.log(.error, .sourceFailed)
            stop()
            return false
        }
        self.source = source
        services.addSource(CFRunLoopGetMain(), source, .defaultMode)
        AppLogger.shared.log(.info, .monitorStarted)
        return true
    }

    func stop() {
        // 先关闭回调准入，再释放系统资源；避免暂停过程中迟到的事件入库。
        if enabled { AppLogger.shared.log(.info, .monitorStopped) }
        enabled = false
        if let source { services.removeSource(CFRunLoopGetMain(), source, .defaultMode) }
        if let tap { services.enable(tap, false); services.invalidate(tap) }
        source = nil
        tap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard enabled else { return }
        // 系统超时/用户输入导致 tap 被禁用时自愈重启
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                services.enable(tap, true)
                AppLogger.shared.log(.warning, .monitorRecovered)
            }
            return
        }
        guard type == .keyDown else { return }
        HotkeyRecorder(store: store, provider: WorkspaceApplicationProvider()).receive(
            keycode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue, running: enabled,
            autorepeat: event.getIntegerValueField(.keyboardEventAutorepeat))
    }
}
