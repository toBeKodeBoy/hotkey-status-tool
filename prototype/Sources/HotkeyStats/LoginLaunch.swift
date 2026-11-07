import AppKit
import ServiceManagement

final class LoginLaunch {
    private let isApp: () -> Bool
    private let status: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let openSettings: () -> Void
    private let showError: () -> Void
    init(isApp: @escaping () -> Bool, status: @escaping () -> SMAppService.Status,
         register: @escaping () throws -> Void, unregister: @escaping () throws -> Void,
         openSettings: @escaping () -> Void, showError: @escaping () -> Void) {
        self.isApp = isApp; self.status = status; self.register = register
        self.unregister = unregister; self.openSettings = openSettings; self.showError = showError
    }
    var available: Bool { isApp() }
    var enabled: Bool { available && status() == .enabled }
    var title: String {
        guard available else { return "登录时启动（请使用应用包）" }
        switch status() {
        case .requiresApproval: return "登录时启动（需要系统批准）"
        case .notFound: return "登录时启动（需重新注册）"
        default: return "登录时启动"
        }
    }
    func toggle() {
        guard available else { return }
        do {
            // 成功请求与系统最终状态分开：菜单始终重新读取系统 status。
            if enabled { try unregister(); AppLogger.shared.log(.info, .loginDisabled) }
            else if status() == .requiresApproval {
                AppLogger.shared.log(.warning, .loginApproval)
                openSettings()
            } else { try register(); AppLogger.shared.log(.info, .loginEnabled) }
        } catch {
            AppLogger.shared.log(.error, .loginFailed)
            showError()
        }
    }
}
