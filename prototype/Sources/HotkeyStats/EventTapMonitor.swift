import CoreGraphics
import Foundation

/// 全局按键监听（CGEventTap，listen-only：只旁路观察，不拦截不修改任何事件）。
final class EventTapMonitor {

    static let shared = EventTapMonitor()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var enabled = false
    private let store: StatsStore

    init(store: StatsStore = .shared) {
        self.store = store
    }

    /// 在主 RunLoop 上安装事件监听。返回是否创建成功（失败通常是辅助功能未授权）。
    @discardableResult
    func start() -> Bool {
        if let tap {
            if CFMachPortIsValid(tap) { return true }
            stop()
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,              // ★ 合规底线：只听不拦
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let monitor = Unmanaged<EventTapMonitor>
                    .fromOpaque(refcon!).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            AppLogger.shared.log(.error, .monitorFailed)
            return false
        }

        self.tap = tap
        enabled = true
        CGEvent.tapEnable(tap: tap, enable: true)

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            AppLogger.shared.log(.error, .sourceFailed)
            stop()
            return false
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        AppLogger.shared.log(.info, .monitorStarted)
        return true
    }

    func stop() {
        // 先关闭回调准入，再释放系统资源；避免暂停过程中迟到的事件入库。
        if enabled { AppLogger.shared.log(.info, .monitorStopped) }
        enabled = false
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard enabled else { return }
        // 系统超时/用户输入导致 tap 被禁用时自愈重启
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                AppLogger.shared.log(.warning, .monitorRecovered)
            }
            return
        }
        // 先过滤暂停及重复事件；普通输入在解析后返回，不写入调试日志。
        guard type == .keyDown, CountingPolicy.accepts(isRunning: enabled,
            autorepeat: event.getIntegerValueField(.keyboardEventAutorepeat)) else { return }

        let keycode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let parsed = ComboParser.parse(keycode: keycode, flagsRaw: event.flags.rawValue)

        guard parsed.isHotkey else { return }   // 纯打字不进入内存模型
        store.record(combo: parsed.combo, keycode: keycode, flags: event.flags.rawValue)
        AppLogger.shared.logHotkey(parsed.combo)
    }
}
