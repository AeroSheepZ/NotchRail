import Foundation

/// 灵动岛触发方式
public enum TriggerMode: String, Codable, CaseIterable, Sendable {
    case hover = "hover"
    case click = "click"
    case hoverAndClick = "hoverAndClick"
    
    public var displayName: String {
        switch self {
        case .hover: return "鼠标悬停（默认）"
        case .click: return "仅点击展开"
        case .hoverAndClick: return "悬停或点击"
        }
    }
}

/// 多显示器策略
public enum ExternalDisplayMode: String, Codable, CaseIterable, Sendable {
    case followFocusedScreen = "followFocusedScreen"
    case mainScreenOnly = "mainScreenOnly"
    case disabled = "disabled"
    
    public var displayName: String {
        switch self {
        case .followFocusedScreen: return "跟随当前聚焦屏幕（默认）"
        case .mainScreenOnly: return "仅在主显示器（刘海屏）显示"
        case .disabled: return "外接显示器完全禁用"
        }
    }
}

/// 用户个性化偏好配置模型
public struct UserPreferences: Codable, Equatable, Sendable {
    /// 灵动岛打开方式
    public var triggerMode: TriggerMode
    /// 点击图标派发原生菜单后是否自动收起灵动岛
    public var autoCollapseOnClick: Bool
    /// 是否开启触觉反馈
    public var enableHapticFeedback: Bool
    /// 无溢出隐藏图标时是否完全隐藏胶囊
    public var hideWhenNoOverflow: Bool
    /// 多显示器策略
    public var externalDisplayMode: ExternalDisplayMode
    /// 是否在 macOS 菜单栏显示常驻小托盘图标
    public var showMenuBarIcon: Bool
    /// 悬停防抖延迟 (ms)
    public var hoverExpandDelayMs: Double
    /// 移出收起宽限延迟 (ms)
    public var collapseDelayMs: Double
    /// 忽略/黑名单应用 Bundle ID 列表
    public var ignoredBundleIDs: [String]
    /// 是否开机自启动
    public var launchAtLogin: Bool
    /// 用户是否已选择跳过「屏幕录制权限」引导
    public var skipScreenCapturePrompt: Bool
    
    public init(
        triggerMode: TriggerMode = .hover,
        autoCollapseOnClick: Bool = true,
        enableHapticFeedback: Bool = true,
        hideWhenNoOverflow: Bool = false,
        externalDisplayMode: ExternalDisplayMode = .followFocusedScreen,
        showMenuBarIcon: Bool = true,
        hoverExpandDelayMs: Double = IslandTheme.Timing.HOVER_EXPAND_DELAY * 1000.0,
        collapseDelayMs: Double = IslandTheme.Timing.COLLAPSE_DELAY * 1000.0,
        ignoredBundleIDs: [String] = [],
        launchAtLogin: Bool = false,
        skipScreenCapturePrompt: Bool = false
    ) {
        self.triggerMode = triggerMode
        self.autoCollapseOnClick = autoCollapseOnClick
        self.enableHapticFeedback = enableHapticFeedback
        self.hideWhenNoOverflow = hideWhenNoOverflow
        self.externalDisplayMode = externalDisplayMode
        self.showMenuBarIcon = showMenuBarIcon
        self.hoverExpandDelayMs = hoverExpandDelayMs
        self.collapseDelayMs = collapseDelayMs
        self.ignoredBundleIDs = ignoredBundleIDs
        self.launchAtLogin = launchAtLogin
        self.skipScreenCapturePrompt = skipScreenCapturePrompt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.triggerMode = try container.decodeIfPresent(TriggerMode.self, forKey: .triggerMode) ?? .hover
        self.autoCollapseOnClick = try container.decodeIfPresent(Bool.self, forKey: .autoCollapseOnClick) ?? true
        self.enableHapticFeedback = try container.decodeIfPresent(Bool.self, forKey: .enableHapticFeedback) ?? true
        self.hideWhenNoOverflow = try container.decodeIfPresent(Bool.self, forKey: .hideWhenNoOverflow) ?? false
        
        // 兼容处理历史字段 followCursor 与 followFocusedScreen
        if let rawMode = try? container.decode(String.self, forKey: .externalDisplayMode) {
            if rawMode == "followCursor" || rawMode == "followFocusedScreen" {
                self.externalDisplayMode = .followFocusedScreen
            } else if let mode = ExternalDisplayMode(rawValue: rawMode) {
                self.externalDisplayMode = mode
            } else {
                self.externalDisplayMode = .followFocusedScreen
            }
        } else {
            self.externalDisplayMode = .followFocusedScreen
        }
        
        self.showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        self.hoverExpandDelayMs = try container.decodeIfPresent(Double.self, forKey: .hoverExpandDelayMs) ?? (IslandTheme.Timing.HOVER_EXPAND_DELAY * 1000.0)
        self.collapseDelayMs = try container.decodeIfPresent(Double.self, forKey: .collapseDelayMs) ?? (IslandTheme.Timing.COLLAPSE_DELAY * 1000.0)
        self.ignoredBundleIDs = try container.decodeIfPresent([String].self, forKey: .ignoredBundleIDs) ?? []
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.skipScreenCapturePrompt = try container.decodeIfPresent(Bool.self, forKey: .skipScreenCapturePrompt) ?? false
    }
}
