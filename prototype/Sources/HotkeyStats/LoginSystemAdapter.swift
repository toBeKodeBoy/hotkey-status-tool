import AppKit
import ServiceManagement

// Read-only discovery is separate from user-authorized system operations.
struct LoginSystemOperations {
    var isApp: () -> Bool = { Bundle.main.bundleURL.pathExtension == "app" }
    var status: () -> SMAppService.Status = { SMAppService.mainApp.status }
    var register: () throws -> Void = SMAppService.mainApp.register
    var unregister: () throws -> Void = SMAppService.mainApp.unregister
    var openSettings: () -> Void = SMAppService.openSystemSettingsLoginItems
    var showError: () -> Void = {
        let alert = NSAlert()
        alert.messageText = "无法更改登录启动设置"
        alert.informativeText = "请检查应用安装位置和系统登录项设置。"
        alert.runModal()
    }
}
extension LoginLaunch {
    convenience init(operations: LoginSystemOperations = LoginSystemOperations()) {
        self.init(isApp: operations.isApp, status: operations.status,
                  register: operations.register, unregister: operations.unregister,
                  openSettings: operations.openSettings, showError: operations.showError)
    }
}
