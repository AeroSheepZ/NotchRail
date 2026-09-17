import Foundation

/// 灵动岛触发方式
public enum TriggerMode: String, Codable, CaseIterable, Sendable {
    case hover = "hover"
    case click = "click"
    case hoverAndClick = "hoverAndClick"
    
    public var displayName: String {
        switch self {
        case .hover: return "仅鼠标悬停"
        case .click: return "仅鼠标点击"
        case .hoverAndClick: return "悬停或点击（默认推荐）"
        }
    }
    
    /// 该档是否响应**悬停**唤出（含移出自动收起）
    ///
    /// 三档语义的**唯一定义处**：视图层、状态机、鼠标监听一律引用本属性，
    /// **不得**各自再写一次 `== .click` / `!= .click` 之类比较 ——
    /// 同一枚举散落多处口径正是 ADR 0015 背景第 1 条那类漂移缺陷的成因。
    public var respondsToHover: Bool {
        self == .hover || self == .hoverAndClick
    }
    
    /// 该档是否响应**点击灵动岛本体**唤出（展开/收起切换）
    ///
    /// 「仅鼠标悬停」档**刻意不响应点击**：若响应，该档与「悬停或点击」将退化为
    /// 可观察行为完全相同的两个选项（「假选择」，见 ADR 0015 决议 1）。
    public var respondsToCapsuleTap: Bool {
        self == .click || self == .hoverAndClick
    }
}

/// 多显示器策略
///
/// **仅两档**（ADR 0015）。历史第三档（原意「外接屏彻底禁用」）已删除，理由是它与
/// `.mainScreenOnly` 的**可观察行为完全相同**，且实现里存在两处相反口径：
/// `IslandWindowCoordinator.allowsPanel` 把它当作「不允许非主屏」，而
/// `ScreenManager.effectiveGeometry(for:)` 又把它并进 `.followFocusedScreen` 分支。
/// 历史落盘值由 `UserPreferences.init(from:)` 显式迁移到 `.mainScreenOnly`，保留其真实行为。
public enum ExternalDisplayMode: String, Codable, CaseIterable, Sendable {
    case followFocusedScreen = "followFocusedScreen"
    case mainScreenOnly = "mainScreenOnly"

    /// 历史第三档的原始编码值：**仅供解码迁移读取**，不得作为新增档位复用
    fileprivate static let LEGACY_THIRD_CASE_RAW = "disabled"

    public var displayName: String {
        switch self {
        case .followFocusedScreen: return "跟随前台活动屏（默认推荐）"
        case .mainScreenOnly: return "仅在主显示器（刘海屏）显示"
        }
    }
}

/// 用户个性化偏好配置模型
public struct UserPreferences: Codable, Equatable, Sendable {
    /// 灵动岛打开方式
    public var triggerMode: TriggerMode
    // 注：历史上曾有「点击图标后是否自动收起灵动岛」偏好项，已于 ADR 0015 删除 ——
    // 收起是平台不变式（灵动岛视口层级高于原生菜单窗口，不收起则菜单被遮挡），
    // 不可由偏好关闭，故不再提供该开关，派发成功后一律原子收起。
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
    /// 共享排序持久键
    public static let SHARED_DISPLAY_KEY = "shared"

    /// 是否在所有显示器之间共享相同的状态项排序（默认关闭，ADR 0014 决议 2）
    public var syncItemOrderAcrossDisplays: Bool
    /// 按屏幕独立持久化的状态项自定义排序字典（分区键为屏幕稳定持久标识，ADR 0014 决议 1）
    public var customItemOrdersByDisplay: [String: [String]]
    /// 历史向后兼容排序包装（读写共享分区）
    public var customItemOrder: [String] {
        get {
            customItemOrdersByDisplay[Self.SHARED_DISPLAY_KEY] ?? []
        }
        set {
            customItemOrdersByDisplay[Self.SHARED_DISPLAY_KEY] = newValue
            if syncItemOrderAcrossDisplays {
                for k in customItemOrdersByDisplay.keys {
                    customItemOrdersByDisplay[k] = newValue
                }
            }
        }
    }
    /// 是否开机自启动
    public var launchAtLogin: Bool
    /// 用户是否已选择跳过「屏幕录制权限」引导
    public var skipScreenCapturePrompt: Bool
    
    /// 获取指定屏幕持久键下的排序
    public func itemOrder(for displayKey: String) -> [String] {
        if syncItemOrderAcrossDisplays {
            return customItemOrdersByDisplay[Self.SHARED_DISPLAY_KEY] ?? []
        }
        return customItemOrdersByDisplay[displayKey] ?? []
    }

    /// 写入指定屏幕持久键下的排序
    public mutating func setItemOrder(_ order: [String], for displayKey: String) {
        if syncItemOrderAcrossDisplays {
            customItemOrdersByDisplay[Self.SHARED_DISPLAY_KEY] = order
            for k in customItemOrdersByDisplay.keys {
                customItemOrdersByDisplay[k] = order
            }
        } else {
            customItemOrdersByDisplay[displayKey] = order
        }
    }

    /// 重置指定屏幕持久键下的排序
    public mutating func resetItemOrder(for displayKey: String) {
        if syncItemOrderAcrossDisplays {
            customItemOrdersByDisplay[Self.SHARED_DISPLAY_KEY] = []
            for k in customItemOrdersByDisplay.keys {
                customItemOrdersByDisplay[k] = []
            }
        } else {
            customItemOrdersByDisplay[displayKey] = []
        }
    }
    
    /// 悬停防抖时延 (秒)
    public var hoverExpandDuration: TimeInterval {
        hoverExpandDelayMs / 1000.0
    }
    
    /// 移出收起宽限时延 (秒)
    public var collapseDuration: TimeInterval {
        collapseDelayMs / 1000.0
    }
    
    public init(
        triggerMode: TriggerMode = .hoverAndClick,
        enableHapticFeedback: Bool = true,
        hideWhenNoOverflow: Bool = false,
        externalDisplayMode: ExternalDisplayMode = .followFocusedScreen,
        showMenuBarIcon: Bool = true,
        hoverExpandDelayMs: Double = IslandTheme.Timing.HOVER_EXPAND_DELAY * 1000.0,
        collapseDelayMs: Double = IslandTheme.Timing.COLLAPSE_DELAY * 1000.0,
        syncItemOrderAcrossDisplays: Bool = false,
        customItemOrdersByDisplay: [String: [String]] = [:],
        customItemOrder: [String] = [],
        launchAtLogin: Bool = false,
        skipScreenCapturePrompt: Bool = false
    ) {
        self.triggerMode = triggerMode
        self.enableHapticFeedback = enableHapticFeedback
        self.hideWhenNoOverflow = hideWhenNoOverflow
        self.externalDisplayMode = externalDisplayMode
        self.showMenuBarIcon = showMenuBarIcon
        self.hoverExpandDelayMs = hoverExpandDelayMs
        self.collapseDelayMs = collapseDelayMs
        self.syncItemOrderAcrossDisplays = syncItemOrderAcrossDisplays
        var initialOrders = customItemOrdersByDisplay
        if initialOrders.isEmpty && !customItemOrder.isEmpty {
            initialOrders[Self.SHARED_DISPLAY_KEY] = customItemOrder
        }
        self.customItemOrdersByDisplay = initialOrders
        self.launchAtLogin = launchAtLogin
        self.skipScreenCapturePrompt = skipScreenCapturePrompt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.triggerMode = try container.decodeIfPresent(TriggerMode.self, forKey: .triggerMode) ?? .hoverAndClick
        self.enableHapticFeedback = try container.decodeIfPresent(Bool.self, forKey: .enableHapticFeedback) ?? true
        self.hideWhenNoOverflow = try container.decodeIfPresent(Bool.self, forKey: .hideWhenNoOverflow) ?? false
        
        // 多显示器策略解码：历史遗留值一律**显式迁移**，绝不在 rawValue 查不到时静默落回默认档 ——
        // 静默落回会把曾选「仅主屏」的用户悄悄切换成「多屏独立多轨」，那是语义漂移而非兼容。
        if let rawMode = try? container.decode(String.self, forKey: .externalDisplayMode) {
            if rawMode == "followCursor" || rawMode == "followFocusedScreen" {
                self.externalDisplayMode = .followFocusedScreen
            } else if rawMode == ExternalDisplayMode.LEGACY_THIRD_CASE_RAW {
                self.externalDisplayMode = .mainScreenOnly
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
        self.syncItemOrderAcrossDisplays = try container.decodeIfPresent(Bool.self, forKey: .syncItemOrderAcrossDisplays) ?? false
        
        var orders = try container.decodeIfPresent([String: [String]].self, forKey: .customItemOrdersByDisplay) ?? [:]
        // 历史单数组向后兼容迁移：既有配置解码迁移至共享分区
        if orders.isEmpty {
            enum LegacyKeys: String, CodingKey {
                case customItemOrder
            }
            if let legacyContainer = try? decoder.container(keyedBy: LegacyKeys.self),
               let legacyOrder = try? legacyContainer.decodeIfPresent([String].self, forKey: .customItemOrder),
               !legacyOrder.isEmpty {
                orders[Self.SHARED_DISPLAY_KEY] = legacyOrder
            }
        }
        self.customItemOrdersByDisplay = orders
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.skipScreenCapturePrompt = try container.decodeIfPresent(Bool.self, forKey: .skipScreenCapturePrompt) ?? false
    }
}
