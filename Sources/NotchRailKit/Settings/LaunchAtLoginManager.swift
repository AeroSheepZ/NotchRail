import Foundation
import ServiceManagement

/// 负责开机自启动管理 (基于 macOS 13+ SMAppService)
public enum LaunchAtLoginManager {
    
    /// 获取当前开机启动注册状态
    public static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
    
    /// 设置开机自启开关
    public static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("⚠️ [NotchRail] 切换开机自启动状态失败: \(error)")
            }
        }
    }
}
