import AppKit
import ServiceManagement

// 系统副作用集中在适配层；策略测试不修改用户的真实登录项。
extension LoginLaunch {
    convenience init() {
        self.init(isApp: { Bundle.main.bundleURL.pathExtension == "app" },
                  status: { SMAppService.mainApp.status },
                  register: { try SMAppService.mainApp.register() },
                  unregister: { try SMAppService.mainApp.unregister() },
                  openSettings: { SMAppService.openSystemSettingsLoginItems() },
                  showError: {
                      let alert = NSAlert()
                      alert.messageText = "无法更改登录启动设置"
                      alert.informativeText = "请检查应用安装位置和系统登录项设置。"
                      alert.runModal()
                  })
    }
}
