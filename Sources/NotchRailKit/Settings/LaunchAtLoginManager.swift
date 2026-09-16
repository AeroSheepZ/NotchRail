import Foundation
import ServiceManagement

/// 负责开机自启动管理 (基于 macOS 13+ SMAppService)
public enum LaunchAtLoginManager {

    /// 切换开机自启动的结果
    ///
    /// 调用方（设置面板）必须据此**如实回报**用户，不得静默吞掉失败。
    public enum Outcome: Equatable, Sendable {
        /// 切换成功且系统侧已生效
        case succeeded
        /// 已登记，但系统要求用户在「登录项」中批准后才生效
        case requiresApproval
        /// 当前系统版本不支持（需 macOS 13 及以上）
        case unsupportedSystem
        /// 注册 / 注销抛出错误（附系统给出的原因）
        case failed(String)
    }
    
    /// 获取当前开机启动注册状态（系统侧真值，唯一事实来源）
    public static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
    
    /// 设置开机自启开关，并**如实回报**结果
    ///
    /// 历史实现吞掉 `register()` 抛出的错误、只打印一行日志，调用方与用户均无从得知失败，
    /// 表现即「开关看着是开的、实际从未注册」。此处改为回报 `Outcome`，
    /// 由调用方决定如何呈现（AGENTS.md：严禁猜测性兜底，Fail-Fast）。
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Outcome {
        guard #available(macOS 13.0, *) else {
            return .unsupportedSystem
        }
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
            return SMAppService.mainApp.status == .requiresApproval ? .requiresApproval : .succeeded
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
