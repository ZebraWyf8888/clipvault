import Foundation
import ServiceManagement

enum LoginItem {
    /// 仅在以 .app 形态运行时可用（SMAppService 依赖 bundle）。
    @discardableResult
    static func set(enabled: Bool) -> Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            NSLog("ClipVault: 非 .app 形态运行，无法设置开机自启")
            return false
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("ClipVault: 开机自启设置失败: \(error.localizedDescription)")
            return false
        }
    }
}
