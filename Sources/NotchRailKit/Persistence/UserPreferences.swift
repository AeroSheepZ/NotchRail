import Foundation

/// 用户个性化偏好配置模型
public struct UserPreferences: Codable, Equatable, Sendable {
    public var ignoredBundleIDs: [String]
    public var hoverExpandDelayMs: Double
    public var collapseDelayMs: Double
    public var launchAtLogin: Bool
    /// 用户是否已选择跳过「屏幕录制权限」引导（避免每次启动都提示）
    public var skipScreenCapturePrompt: Bool
    
    public init(
        ignoredBundleIDs: [String] = [],
        hoverExpandDelayMs: Double = IslandTheme.Timing.HOVER_EXPAND_DELAY * 1000.0,
        collapseDelayMs: Double = IslandTheme.Timing.COLLAPSE_DELAY * 1000.0,
        launchAtLogin: Bool = false,
        skipScreenCapturePrompt: Bool = false
    ) {
        self.ignoredBundleIDs = ignoredBundleIDs
        self.hoverExpandDelayMs = hoverExpandDelayMs
        self.collapseDelayMs = collapseDelayMs
        self.launchAtLogin = launchAtLogin
        self.skipScreenCapturePrompt = skipScreenCapturePrompt
    }
}
