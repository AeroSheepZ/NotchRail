import SwiftUI
import AppKit

/// 偏好设置的分区（侧边栏条目与内容路由的唯一来源）
private enum SettingsTab: Int, CaseIterable, Identifiable {
    case general
    case timing
    case apps
    case about

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general: return "常规"
        case .timing: return "悬停与动效"
        case .apps: return "应用管理"
        case .about: return "诊断与关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .timing: return "timer"
        case .apps: return "app.badge.checkmark"
        case .about: return "info.circle"
        }
    }
}

/// 偏好设置主视图 (macOS 27 原生 HIG 现代化液体玻璃与微卡片风格，彻底杜绝 Emoji)
public struct SettingsView: View {
    @ObservedObject var preferenceStore = PreferenceStore.shared
    @ObservedObject var permissionManager = PermissionManager.shared
    @ObservedObject private var screenManager = ScreenManager.shared
    private let iconResolver = IconResolver.shared
    
    /// 版式尺寸的唯一来源（设置窗口与内容区共用）
    public enum SettingsLayout {
        public static let WINDOW_WIDTH: CGFloat = 720
        public static let WINDOW_HEIGHT: CGFloat = 540
        public static let SIDEBAR_WIDTH: CGFloat = 180
    }

    @State private var selectedTab: SettingsTab? = .general
    @State private var searchText: String = ""
    @State private var showResetAlert: Bool = false
    @State private var isRefreshingPermissions: Bool = false
    @State private var isManualScanning: Bool = false
    @State private var launchAtLoginMessage: String? = nil
    @State private var snapshotRevision: Int = 0
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
                .opacity(0.4)
            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: SettingsLayout.WINDOW_WIDTH, height: SettingsLayout.WINDOW_HEIGHT)
        .alert("确定要恢复所有出厂设置吗？", isPresented: $showResetAlert) {
            Button("取消", role: .cancel) {}
            Button("恢复默认", role: .destructive) {
                preferenceStore.resetToDefaults()
            }
        } message: {
            Text("所有触发模式、动画时延与显示策略都将被重置为出厂推荐配置。")
        }
        .onAppear {
            launchAtLoginMessage = nil
            syncLaunchAtLoginMirror()
        }
        // 纯观察者：仅当当前前台活动屏幕快照实际变更时触发增量重绘
        .onReceive(NotificationCenter.default.publisher(for: .menuBarSnapshotUpdated)) { notif in
            guard let snapshot = notif.object as? MenuBarSnapshot,
                  snapshot.displayID == activeDisplayID else { return }
            snapshotRevision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .activeDisplayChanged)) { _ in
            snapshotRevision &+= 1
        }
    }

    // MARK: - 开机自启动同步

    private func syncLaunchAtLoginMirror() {
        let actual = LaunchAtLoginManager.isEnabled
        guard preferenceStore.preferences.launchAtLogin != actual else { return }
        if preferenceStore.preferences.launchAtLogin && !actual {
            launchAtLoginMessage = "系统侧未生效（可能已在「系统设置 → 通用 → 登录项」中被关闭），已按系统的真实状态回写。"
        }
        preferenceStore.update { $0.launchAtLogin = actual }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        let outcome = LaunchAtLoginManager.setEnabled(enabled)
        let actual = LaunchAtLoginManager.isEnabled
        preferenceStore.update { $0.launchAtLogin = actual }

        switch outcome {
        case .succeeded:
            launchAtLoginMessage = actual == enabled ? nil : "系统侧未按预期变更，请检查「系统设置 → 通用 → 登录项」。"
        case .requiresApproval:
            launchAtLoginMessage = "已在系统中登记，但需在「系统设置 → 通用 → 登录项」中允许 NotchRail 后方能生效。"
        case .unsupportedSystem:
            launchAtLoginMessage = "当前系统版本不支持自动启动注册（需 macOS 13 及以上）。"
        case .failed(let reason):
            launchAtLoginMessage = "注册失败：\(reason)"
        }
    }

    // MARK: - 侧边栏 (macOS 27 系统级通透质感)

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label {
                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium))
                    } icon: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13, weight: .regular))
                    }
                    .tag(tab)
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.sidebar)
            
            Spacer()
            
            // 底部版本号显示（单一事实来源）
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 4, height: 4)
                Text("v\(NotchRailVersion.CURRENT_VERSION)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: SettingsLayout.SIDEBAR_WIDTH)
    }

    // MARK: - 内容区路由

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedTab ?? .general {
        case .general:
            ScrollView {
                generalTab
                    .padding(20)
            }
        case .timing:
            ScrollView {
                timingTab
                    .padding(20)
            }
        case .apps:
            appsTab
                .padding(20)
        case .about:
            ScrollView {
                aboutTab
                    .padding(20)
            }
        }
    }
    
    // MARK: - Tab 1: 常规设置 (General)
    
    private var generalTab: some View {
        VStack(spacing: 20) {
            // 卡片 1: 呼出与按键
            SettingsCardView(title: "灵动岛呼出与按键") {
                // 1.1 打开方式
                SettingsRowView {
                    SettingsIconBadge(systemName: "macwindow.badge.plus", color1: .purple, color2: .indigo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("灵动岛打开方式")
                            .font(.system(size: 13, weight: .medium))
                        Text(triggerModeDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { preferenceStore.preferences.triggerMode },
                        set: { val in preferenceStore.update { $0.triggerMode = val } }
                    )) {
                        ForEach(TriggerMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 175)
                }
                
                cardDivider
                
                // 1.2 全局快捷键开关
                SettingsRowView {
                    SettingsIconBadge(systemName: "keyboard", color1: .indigo, color2: .blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("启用全局自定义快捷键")
                            .font(.system(size: 13, weight: .medium))
                        Text("随时通过物理快捷键一键唤起或收起灵动岛")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { preferenceStore.preferences.hotKeyEnabled },
                        set: { val in preferenceStore.update { $0.hotKeyEnabled = val } }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                
                cardDivider
                
                // 1.3 快捷键录制项（受 hotKeyEnabled 联动）
                let isHotKeyOn = preferenceStore.preferences.hotKeyEnabled
                SettingsRowView {
                    SettingsIconBadge(systemName: "command", color1: .blue, color2: .cyan)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("全局唤醒快捷键")
                            .font(.system(size: 13, weight: .medium))
                        Text(isHotKeyOn ? "点击键帽即可录制专属快捷键（默认 ⌥ ~）" : "快捷键已停用，开启上方开关后方可录制与触发")
                            .font(.caption)
                            .foregroundColor(isHotKeyOn ? .secondary : .orange)
                    }
                    Spacer()
                    HotKeyRecorderView(
                        keyCode: Binding(
                            get: { preferenceStore.preferences.hotKeyCode },
                            set: { val in preferenceStore.update { $0.hotKeyCode = val } }
                        ),
                        modifiers: Binding(
                            get: { preferenceStore.preferences.hotKeyModifiers },
                            set: { val in preferenceStore.update { $0.hotKeyModifiers = val } }
                        ),
                        isEnabled: isHotKeyOn
                    )
                }
                .opacity(isHotKeyOn ? 1.0 : 0.4)
            }
            
            // 卡片 2: 交互与视觉
            SettingsCardView(title: "交互行为与触觉反馈") {
                // 触觉反馈
                SettingsRowView {
                    SettingsIconBadge(systemName: "hand.tap", color1: .pink, color2: .red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("交互触觉振动反馈")
                            .font(.system(size: 13, weight: .medium))
                        Text("展开、收起、拖拽重排及点击状态项时提供原生触觉微动")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { preferenceStore.preferences.enableHapticFeedback },
                        set: { val in preferenceStore.update { $0.enableHapticFeedback = val } }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
            
            // 卡片 3: 多显示器策略与跨屏排序 (严格联动)
            let isMainScreenOnly = preferenceStore.preferences.externalDisplayMode == .mainScreenOnly
            SettingsCardView(title: "多显示器协同策略") {
                // 3.1 多屏策略选择
                SettingsRowView {
                    SettingsIconBadge(systemName: "display.2", color1: .blue, color2: .indigo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("多显示器策略")
                            .font(.system(size: 13, weight: .medium))
                        Text(preferenceStore.preferences.externalDisplayMode == .followFocusedScreen
                             ? "跟随前台活动屏：仅在当前工作的屏幕激活展开，待命屏幕保持静默收起"
                             : "仅主显示器：灵动岛固定驻留在内置刘海屏，外接屏完全不启用")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { preferenceStore.preferences.externalDisplayMode },
                        set: { val in
                            preferenceStore.update { $0.externalDisplayMode = val }
                            // 联动复位：切换至仅主屏时原子关闭跨屏同步，杜绝幽灵残留
                            if val == .mainScreenOnly {
                                PreferenceStore.shared.setSyncItemOrderAcrossDisplays(false)
                            }
                        }
                    )) {
                        ForEach(ExternalDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 175)
                }
                
                cardDivider
                
                // 3.2 跨屏排序同步（受 externalDisplayMode 强联动）
                SettingsRowView {
                    SettingsIconBadge(systemName: "arrow.triangle.2.circlepath", color1: .teal, color2: .green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("跨显示器同步应用排序")
                            .font(.system(size: 13, weight: .medium))
                        if isMainScreenOnly {
                            Text("当前多显示器策略为「仅主屏」，外接屏未启用灵动岛，无需跨屏同步排序")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("默认关闭（各屏幕独立排序）。开启后对任一屏幕的排序调整将自动同步至所有连接的显示器")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: {
                            isMainScreenOnly ? false : preferenceStore.preferences.syncItemOrderAcrossDisplays
                        },
                        set: { val in
                            guard !isMainScreenOnly else { return }
                            PreferenceStore.shared.setSyncItemOrderAcrossDisplays(val)
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(isMainScreenOnly)
                }
                .opacity(isMainScreenOnly ? 0.4 : 1.0)
            }
            
            // 卡片 4: 系统与常驻
            SettingsCardView(title: "系统常驻与启动") {
                // 4.1 菜单栏常驻图标
                SettingsRowView {
                    SettingsIconBadge(systemName: "menubar.rectangle", color1: .orange, color2: .yellow)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("在系统顶部菜单栏显示常驻图标")
                            .font(.system(size: 13, weight: .medium))
                        Text("在菜单栏右侧常驻小黄岛图标，方便快速呼出快捷菜单")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { preferenceStore.preferences.showMenuBarIcon },
                        set: { val in preferenceStore.update { $0.showMenuBarIcon = val } }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                
                cardDivider
                
                // 4.2 开机自启
                SettingsRowView {
                    SettingsIconBadge(systemName: "power.circle", color1: .green, color2: .mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("开机登录时自动启动 NotchRail")
                            .font(.system(size: 13, weight: .medium))
                        if let msg = launchAtLoginMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("系统登录后自启守护进程，保持灵动岛随时候命")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { preferenceStore.preferences.launchAtLogin },
                        set: { val in applyLaunchAtLogin(val) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
    }
    
    private var triggerModeDescription: String {
        switch preferenceStore.preferences.triggerMode {
        case .hover:
            return "仅悬停：鼠标停留在顶部刘海或热区时自动展开，移出后收起（不响应点击）"
        case .click:
            return "仅点击：鼠标划过不展开，点击胶囊或顶部中央热区切换展开与收起"
        case .hoverAndClick:
            return "悬停或点击（默认）：既支持鼠标悬停自动展开，亦可随时点击切换"
        }
    }
    
    // MARK: - Tab 2: 悬停与动效 (Timing)
    
    private var timingTab: some View {
        VStack(spacing: 20) {
            let allowsHover = preferenceStore.preferences.triggerMode.respondsToHover
            SettingsCardView(title: "响应延迟与防误触时序") {
                // 移入展开防抖延迟（受 triggerMode 联动）
                SettingsRowView {
                    SettingsIconBadge(systemName: "arrow.right.to.line.compact", color1: .purple, color2: .indigo)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("移入展开防抖延迟")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(Int(preferenceStore.preferences.hoverExpandDelayMs)) ms")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { preferenceStore.preferences.hoverExpandDelayMs },
                                set: { val in preferenceStore.update { $0.hoverExpandDelayMs = val } }
                            ),
                            in: 50...300,
                            step: 10
                        )
                        .disabled(!allowsHover)
                        
                        if allowsHover {
                            Text("光标进入刘海区域或热区后停留超过此时间方触发展开，防止快速划过误触。推荐 120ms。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("当前打开方式为「仅鼠标点击」，移入展开防抖延迟已被停用。")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .opacity(allowsHover ? 1.0 : 0.4)
                
                cardDivider
                
                // 移出收起缓冲时间
                SettingsRowView {
                    SettingsIconBadge(systemName: "arrow.left.to.line.compact", color1: .indigo, color2: .blue)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("移出收起缓冲时间")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(Int(preferenceStore.preferences.collapseDelayMs)) ms")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { preferenceStore.preferences.collapseDelayMs },
                                set: { val in preferenceStore.update { $0.collapseDelayMs = val } }
                            ),
                            in: 150...600,
                            step: 10
                        )
                        
                        Text("光标离开灵动岛后保留的缓冲宽限期，期间重新移入可无缝中断收起。推荐 300ms。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 恢复默认按钮卡片
            HStack {
                Button("恢复出厂全部配置") {
                    showResetAlert = true
                }
                .controlSize(.small)
                .foregroundColor(.red)
                
                Spacer()
                
                Button("恢复推荐时延 (120ms / 300ms)") {
                    preferenceStore.update {
                        $0.hoverExpandDelayMs = IslandTheme.Timing.HOVER_EXPAND_DELAY * 1000.0
                        $0.collapseDelayMs = IslandTheme.Timing.COLLAPSE_DELAY * 1000.0
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Tab 3: 应用管理 (Apps) - 纯观察者化双看板
    
    private var activeDisplayID: CGDirectDisplayID {
        screenManager.currentGeometry.displayID
    }
    
    private var appsTab: some View {
        VStack(spacing: 12) {
            // 0. 当前前台活动屏横条 (零 Emoji，精细 SF Symbols)
            let currentGeom = screenManager.currentGeometry
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.accentColor)
                Text("当前前台活动屏幕：\(currentGeom.displayName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("实时焦点联动")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.1))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            
            // 1. 搜索栏与刷新按钮
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("搜索应用名称或 Bundle ID...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                
                Button {
                    isManualScanning = true
                    Task { @MainActor in
                        MenuBarSyncCoordinator.shared.scheduleSync(immediate: true, showProgress: true)
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        isManualScanning = false
                    }
                } label: {
                    Label(isManualScanning ? "扫描中..." : "重新扫描菜单栏", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(isManualScanning)
            }
            
            // 2. 双分区滚动看板 (纯只读展示，绝不抢占截图通道)
            let allItems = filteredItems(revision: snapshotRevision)
            let overflowItems = allItems.filter { $0.isOverflowed }
            let visibleItems = allItems.filter { !$0.isOverflowed }
            
            ScrollView {
                VStack(spacing: 16) {
                    // 分区 A: 灵动岛展示项 (已溢出)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("灵动岛展示项 (已溢出 · \(overflowItems.count) 项)", systemImage: "macwindow.on.rectangle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.orange)
                            
                            Spacer()
                            
                            if !PreferenceStore.shared.customItemOrder(for: activeDisplayID).isEmpty {
                                Button("恢复默认排序") {
                                    PreferenceStore.shared.resetCustomItemOrder(for: activeDisplayID)
                                }
                                .font(.system(size: 10, weight: .medium))
                                .controlSize(.mini)
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("提示：在灵动岛展开时可长按图标流体拖拽重排顺序")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 4)
                        
                        if overflowItems.isEmpty {
                            HStack {
                                Spacer()
                                Text(searchText.isEmpty ? "当前屏幕暂无被遮挡图标，状态栏空间充裕" : "未搜索到匹配的灵动岛展示项")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 22)
                                Spacer()
                            }
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                            )
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(overflowItems.enumerated()), id: \.element.id) { index, entry in
                                    appRow(for: entry)
                                    if index < overflowItems.count - 1 {
                                        Divider()
                                            .opacity(0.3)
                                            .padding(.leading, 52)
                                    }
                                }
                            }
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                            )
                        }
                    }
                    
                    // 分区 B: 原生菜单栏可见项
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("原生菜单栏可见项 (未遮挡 · \(visibleItems.count) 项)", systemImage: "menubar.dock.rectangle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("提示：原生菜单栏项可按住 ⌘ (Command) 键在系统状态栏直接拖拽")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 4)
                        
                        if visibleItems.isEmpty {
                            HStack {
                                Spacer()
                                Text(searchText.isEmpty ? "当前屏幕暂无原生可见项" : "未搜索到匹配的原生可见项")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 22)
                                Spacer()
                            }
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                            )
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, entry in
                                    appRow(for: entry)
                                    if index < visibleItems.count - 1 {
                                        Divider()
                                            .opacity(0.3)
                                            .padding(.leading, 52)
                                    }
                                }
                            }
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Tab 4: 诊断与关于 (Diagnostics & About)
    
    private var aboutTab: some View {
        VStack(spacing: 20) {
            // 应用标志与权威版本
            VStack(spacing: 8) {
                if let iconImage = NSApp.applicationIconImage ?? NSImage(named: "AppIcon") {
                    Image(nsImage: iconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                } else {
                    Image(systemName: "menubar.dock.rectangle")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                
                Text("NotchRail")
                    .font(.title2.weight(.bold))
                
                let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                let bundleBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                let displayVer = bundleVersion ?? NotchRailVersion.CURRENT_VERSION
                let displayBuild = bundleBuild ?? NotchRailVersion.CURRENT_BUILD
                
                Text("MacBook 物理刘海与状态栏沉浸式扩展 · v\(displayVer) (\(displayBuild))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
            
            // 核心权限卡片
            SettingsCardView(title: "核心系统运行权限诊断") {
                SettingsRowView {
                    SettingsIconBadge(systemName: "accessibility", color1: .purple, color2: .indigo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("辅助功能权限 (Accessibility)")
                            .font(.system(size: 13, weight: .medium))
                        Text("用于派发点击并唤起被遮挡应用的原生菜单与控制面板")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    permissionStatusBadge(granted: permissionManager.isAccessibilityGranted)
                    Button("授权") {
                        permissionManager.openSystemSettings()
                    }
                    .controlSize(.small)
                }
                
                cardDivider
                
                SettingsRowView {
                    SettingsIconBadge(systemName: "camera.metering.matrix", color1: .blue, color2: .cyan)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("屏幕录制权限 (Screen Recording)")
                            .font(.system(size: 13, weight: .medium))
                        Text("用于原生高精度合成捕获菜单栏状态项的高清实时图标")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    permissionStatusBadge(granted: permissionManager.isScreenCaptureGranted)
                    Button("授权") {
                        permissionManager.openScreenCaptureSettings()
                    }
                    .controlSize(.small)
                }
            }
            
            // 快捷操作
            HStack(spacing: 12) {
                Button {
                    isRefreshingPermissions = true
                    permissionManager.checkAccessibility(prompt: false)
                    permissionManager.checkScreenCapture(prompt: false)
                    MenuBarSyncCoordinator.shared.scheduleSync(immediate: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isRefreshingPermissions = false
                    }
                } label: {
                    Label(isRefreshingPermissions ? "检测中..." : "重新检测权限并同步", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                
                Button("GitHub 源码仓库") {
                    if let url = URL(string: "https://github.com/AeroSheepZ/NotchRail") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
                
                Button("退出 NotchRail", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
                .tint(.red)
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - 辅助结构与方法 (纯观察者，杜绝主动抓取)
    
    private var cardDivider: some View {
        Divider()
            .opacity(0.3)
            .padding(.leading, 52)
    }
    
    private struct AppListEntry: Identifiable {
        var id: String { uniqueKey }
        let uniqueKey: String
        let originalIndex: Int
        let item: MenuBarItem
        let key: String
        let title: String
        let bundleID: String
        let isOverflowed: Bool
        let statusIcon: NSImage?
    }
    
    private func resolveAppEntry(item: MenuBarItem, index: Int) -> AppListEntry {
        let bundleID = item.bundleIdentifier ?? "win.\(item.windowID)"
        let title = item.title ?? bundleID
        let key = item.preferenceKey
        // 纯观察者：仅读内存现有缓存，零副作用
        let statusImage: NSImage? = iconResolver.image(for: item)
        
        return AppListEntry(
            uniqueKey: "\(bundleID)_\(item.windowID)",
            originalIndex: index,
            item: item,
            key: key,
            title: title,
            bundleID: bundleID,
            isOverflowed: item.displayMode == .overflowed,
            statusIcon: statusImage
        )
    }
    
    private func filteredItems(revision: Int) -> [AppListEntry] {
        let displayID = activeDisplayID
        // 纯观察者：读取指定屏有效快照，绝不在后台触发重扫或截图任务
        let currentSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: displayID)
        let menuBarItems = currentSnapshot?.allItems ?? []
        var result: [AppListEntry] = []
        
        for (index, item) in menuBarItems.enumerated() {
            let entry = resolveAppEntry(item: item, index: index)
            result.append(entry)
        }
        
        if !searchText.isEmpty {
            result = result.filter {
                fuzzyMatch(query: searchText, in: $0.title) || fuzzyMatch(query: searchText, in: $0.bundleID)
            }
        }
        
        let customOrder = PreferenceStore.shared.customItemOrder(for: displayID)
        let itemComparator = MenuBarItem.comparator(for: customOrder)
        result.sort { lhs, rhs in
            if lhs.isOverflowed != rhs.isOverflowed {
                return lhs.isOverflowed && !rhs.isOverflowed
            }
            if lhs.isOverflowed && rhs.isOverflowed {
                if itemComparator(lhs.item, rhs.item) {
                    return true
                }
                if itemComparator(rhs.item, lhs.item) {
                    return false
                }
                return lhs.originalIndex < rhs.originalIndex
            }
            return lhs.originalIndex > rhs.originalIndex
        }
        
        return result
    }
    
    private func fuzzyMatch(query: String, in target: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let t = target.lowercased()
        guard !q.isEmpty else { return true }
        if t.contains(q) { return true }
        
        var targetIndex = t.startIndex
        for char in q {
            guard let found = t[targetIndex...].firstIndex(of: char) else {
                return false
            }
            targetIndex = t.index(after: found)
        }
        return true
    }
    
    @ViewBuilder
    private func appRow(for entry: AppListEntry) -> some View {
        let iconHeight: CGFloat = 16
        let containerWidth: CGFloat = {
            if let img = entry.statusIcon, img.size.height > 0 {
                let ratio = img.size.width / img.size.height
                return max(28.0, min(76.0, iconHeight * ratio + 10))
            }
            return 28.0
        }()
        
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                
                if let statusImg = entry.statusIcon {
                    Image(nsImage: statusImg)
                        .interpolation(.high)
                        .antialiased(true)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: iconHeight)
                } else {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .frame(width: containerWidth, height: 26)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Text(entry.bundleID)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if entry.isOverflowed {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                    Text("岛内展示 (已溢出)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 5, height: 5)
                    Text("原生可见")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(NSColor.separatorColor).opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func permissionStatusBadge(granted: Bool) -> some View {
        if granted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text("已授权")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())
        } else {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text("未授权")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

// MARK: - macOS 27 HIG 现代辅助组件体系

/// 彩色渐变图标徽章 (macOS 27 宝石拟态质感，带内高光)
private struct SettingsIconBadge: View {
    let systemName: String
    let color1: Color
    let color2: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color1, color2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // 顶层微高光描边
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .frame(width: 28, height: 28)
    }
}

/// 现代微卡片包裹视图 (macOS 27 液体材质与次像素边框)
private struct SettingsCardView<Content: View>: View {
    let title: String?
    let content: Content
    
    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
    }
}

/// 现代设置项单行视图 (开阔呼吸感内边距)
private struct SettingsRowView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
