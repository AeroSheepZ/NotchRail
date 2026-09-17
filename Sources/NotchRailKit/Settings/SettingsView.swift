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

/// 偏好设置主视图
///
/// 版式：左侧分区侧边栏 + 右侧内容区。**刻意不使用 `TabView` + `.tabItem`** ——
/// 该组合在 macOS 上会渲染成传统顶部标签栏，观感陈旧（历史缺陷）。
public struct SettingsView: View {
    @ObservedObject var preferenceStore = PreferenceStore.shared
    @ObservedObject var permissionManager = PermissionManager.shared
    @ObservedObject private var screenManager = ScreenManager.shared
    /// 菜单栏图标解析器：**必须观察**，否则应用管理列表的图标永不刷新
    ///
    /// `IconResolver` 是 `ObservableObject`，`iconStates` 在每批图标落位后发布。
    /// 快照通知（`snapshotRevision` 的驱动源）**覆盖不到图标到达时刻**：
    /// `MenuBarSyncCoordinator.performSync` 先解析溢出项图标、随即发出 `.menuBarSnapshotUpdated`，
    /// 而「可见项」图标在其**之后**才解析 —— 而本面板列的是**全部项**。
    /// 故仅靠脉冲时，首帧取到的是尚未落位的 nil ⇒ 列表停在占位符不再重绘（历史回归）。
    @ObservedObject private var iconResolver = IconResolver.shared
    
    /// 版式尺寸的唯一来源（设置窗口与内容区共用，避免两处各写一份而失配）
    public enum SettingsLayout {
        /// 设置窗口内容区宽度
        public static let WINDOW_WIDTH: CGFloat = 680
        /// 设置窗口内容区高度
        public static let WINDOW_HEIGHT: CGFloat = 500
        /// 侧边栏宽度
        public static let SIDEBAR_WIDTH: CGFloat = 172
    }

    @State private var selectedTab: SettingsTab? = .general
    @State private var searchText: String = ""
    @State private var showResetAlert: Bool = false
    @State private var isRefreshingPermissions: Bool = false
    @State private var isManualScanning: Bool = false
    /// 开机自启动的如实回报（注册失败 / 待批准 / 与系统侧不一致时显示，正常态为 nil）
    @State private var launchAtLoginMessage: String? = nil
    /// 本面板所选屏幕的快照刷新脉冲（仅在**该屏**快照更新时自增，杜绝任一块屏广播导致整面板重算）
    @State private var snapshotRevision: Int = 0
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
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
        // 快照刷新：仅采纳当前活动屏幕的更新
        .onReceive(NotificationCenter.default.publisher(for: .menuBarSnapshotUpdated)) { notif in
            guard let snapshot = notif.object as? MenuBarSnapshot,
                  snapshot.displayID == activeDisplayID else { return }
            snapshotRevision &+= 1
        }
        // 活动屏切换：即刻刷新应用管理列表
        .onReceive(NotificationCenter.default.publisher(for: .activeDisplayChanged)) { _ in
            snapshotRevision &+= 1
        }
    }

    // MARK: - 开机自启动（偏好只是系统侧注册状态的镜像）

    /// 与系统侧对账：一律以系统真实状态回写偏好
    ///
    /// 若偏好为「开」而系统侧为「关」，**如实说明原因**而非静默掰回 ——
    /// 历史实现此处直接 `update` 回写、不给任何提示，用户只会看到开关自己弹回去。
    private func syncLaunchAtLoginMirror() {
        let actual = LaunchAtLoginManager.isEnabled
        guard preferenceStore.preferences.launchAtLogin != actual else { return }
        if preferenceStore.preferences.launchAtLogin && !actual {
            launchAtLoginMessage = "系统侧未生效（可能已在「系统设置 → 通用 → 登录项」中被关闭），已按系统的真实状态回写。"
        }
        preferenceStore.update { $0.launchAtLogin = actual }
    }

    /// 应用开机自启动开关：先按结果回写偏好，再据结果给出**可见**说明
    private func applyLaunchAtLogin(_ enabled: Bool) {
        let outcome = LaunchAtLoginManager.setEnabled(enabled)
        let actual = LaunchAtLoginManager.isEnabled
        // 偏好恒与系统侧真值一致，杜绝「开关是开的、系统里没注册」
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

    /// 侧边栏分区导航
    private var settingsSidebar: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.title, systemImage: tab.symbol)
                    .tag(tab)
            }
        }
        .listStyle(.sidebar)
        .frame(width: SettingsLayout.SIDEBAR_WIDTH)
    }

    /// 右侧内容区（按侧边栏选择路由，四个分区内容与旧版完全一致）
    @ViewBuilder
    private var settingsContent: some View {
        switch selectedTab ?? .general {
        case .general: generalTab
        case .timing: timingTab
        case .apps: appsTab
        case .about: aboutTab
        }
    }
    
    // MARK: - Tab 1: 常规设置 (General)
    
    private var generalTab: some View {
        Form {
            Section {
                Picker("灵动岛打开方式", selection: Binding(
                    get: { preferenceStore.preferences.triggerMode },
                    set: { val in preferenceStore.update { $0.triggerMode = val } }
                )) {
                    ForEach(TriggerMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                
                switch preferenceStore.preferences.triggerMode {
                case .hover:
                    Text("鼠标停留在顶部刘海或热区时自动展开，移出后自动收起。该档不响应点击 —— 点击灵动岛不会有任何反应（需要点击请选「悬停或点击」）。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .click:
                    Text("鼠标划过或停留均不展开。点击灵动岛即切换展开与收起，点击灵动岛以外区域亦收起。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .hoverAndClick:
                    Text("既支持鼠标悬停自动展开，亦可随时点击灵动岛切换展开与收起。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("外接平直屏在折叠常态下完全隐形，故「点击」在该屏对应的是顶部中央热区（水平居中、紧贴屏幕顶边），而非可见胶囊。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("灵动岛唤醒与展开")
            }
            
            Section {
                Toggle("交互触觉振动反馈", isOn: Binding(
                    get: { preferenceStore.preferences.enableHapticFeedback },
                    set: { val in preferenceStore.update { $0.enableHapticFeedback = val } }
                ))
                
                Toggle("无遮挡图标时自动隐藏紧凑胶囊", isOn: Binding(
                    get: { preferenceStore.preferences.hideWhenNoOverflow },
                    set: { val in preferenceStore.update { $0.hideWhenNoOverflow = val } }
                ))
                
                Text("该档语义为「无溢出即完全不出现」：当前屏 0 溢出期间灵动岛整体隐退并静默 —— 胶囊不显示，悬停、点击与菜单唤出均不生效。此项优先于上方的「灵动岛打开方式」。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("交互行为与视觉显示")
            }
            
            Section {
                Picker("多显示器策略", selection: Binding(
                    get: { preferenceStore.preferences.externalDisplayMode },
                    set: { val in preferenceStore.update { $0.externalDisplayMode = val } }
                )) {
                    ForEach(ExternalDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                
                switch preferenceStore.preferences.externalDisplayMode {
                case .followFocusedScreen:
                    Text("单前台独占激活：灵动岛仅在当前正在工作的前台活动屏幕上激活展开；待命屏幕保持静默收起（内置屏纯黑底座贴合刘海，外接屏完全隐形），杜绝未就绪的空白状态。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .mainScreenOnly:
                    Text("灵动岛固定驻留在主显示器（内置刘海屏）顶部；外接屏幕完全不启用灵动岛。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                Toggle("跨显示器同步应用排序", isOn: Binding(
                    get: { preferenceStore.preferences.syncItemOrderAcrossDisplays },
                    set: { val in PreferenceStore.shared.setSyncItemOrderAcrossDisplays(val) }
                ))
                
                Text("默认关闭（各屏幕维护独立的状态项拖拽排序）。开启后，对任一屏幕的排序调整将自动同步至所有连接的显示器。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("多显示器协同策略")
            }
            
            Section {
                Toggle("在系统顶部菜单栏显示常驻图标", isOn: Binding(
                    get: { preferenceStore.preferences.showMenuBarIcon },
                    set: { val in preferenceStore.update { $0.showMenuBarIcon = val } }
                ))
                
                Toggle("开机登录时自动启动 NotchRail", isOn: Binding(
                    get: { preferenceStore.preferences.launchAtLogin },
                    set: { val in applyLaunchAtLogin(val) }
                ))
                
                if let message = launchAtLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("系统与启动")
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 2: 悬停与动效 (Timing)
    
    private var timingTab: some View {
        Form {
            Section {
                let allowsHover = preferenceStore.preferences.triggerMode.respondsToHover
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("移入展开防抖延迟")
                        Spacer()
                        Text("\(Int(preferenceStore.preferences.hoverExpandDelayMs)) ms")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
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
                        Text("当前打开方式为「仅鼠标点击」，移入展开防抖延迟不生效。")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.vertical, 4)
                .opacity(allowsHover ? 1.0 : 0.5)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("移出收起缓冲时间")
                        Spacer()
                        Text("\(Int(preferenceStore.preferences.collapseDelayMs)) ms")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
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
                .padding(.vertical, 4)
                
                HStack {
                    Button("恢复全部出厂设置") {
                        showResetAlert = true
                    }
                    .controlSize(.small)
                    .foregroundColor(.orange)
                    
                    Spacer()
                    
                    Button("恢复推荐时延") {
                        preferenceStore.update {
                            $0.hoverExpandDelayMs = IslandTheme.Timing.HOVER_EXPAND_DELAY * 1000.0
                            $0.collapseDelayMs = IslandTheme.Timing.COLLAPSE_DELAY * 1000.0
                        }
                    }
                    .controlSize(.small)
                }
            } header: {
                Text("响应延迟与防误触时序")
            }
        }
        .formStyle(.grouped)
    }
    
    /// 本面板当前查看的屏幕：单前台活动源自适应绑定（严格跟随当前前台活动屏幕，解决跨屏配置割裂与待命空白）
    private var activeDisplayID: CGDirectDisplayID {
        screenManager.currentGeometry.displayID
    }
    
    private var appsTab: some View {
        VStack(spacing: 10) {
            // 0. 前台活动屏幕自适应指示条（单前台活动源独占：随鼠标焦点自适应流转，彻底消除非活动屏待命空白）
            let currentGeom = screenManager.currentGeometry
            HStack(spacing: 8) {
                Label("当前前台活动屏幕：\(currentGeom.displayName)", systemImage: "display")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("🟢 已激活光栅化")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.6)
            )
            
            HStack {
                Text("💡 焦点跟随：在任一显示器点击激活，此处将毫秒级同步呈现该屏幕的状态项。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 2)
            
            // 1. 顶部现代化搜索与统计栏
            HStack(spacing: 10) {
                HStack(spacing: 6) {
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
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.8)
                )
                
                // 状态统计徽章与快捷排序重置
                let allItems = filteredItems(revision: snapshotRevision)
                let overflowCount = allItems.filter { $0.isOverflowed }.count
                HStack(spacing: 6) {
                    Text("共 \(allItems.count) 项")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if overflowCount > 0 {
                        Text("\(overflowCount) 溢出")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    
                    if !PreferenceStore.shared.customItemOrder(for: activeDisplayID).isEmpty {
                        Button {
                            PreferenceStore.shared.resetCustomItemOrder(for: activeDisplayID)
                        } label: {
                            Text("恢复默认排序")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.8)
                )
            }
            
            // 手动扫描中呼吸微光条（仅在显式点击下方“重新扫描菜单栏”时呈现，严禁响应后台静默预热）
            if isManualScanning {
                HStack(spacing: 8) {
                    IslandSpinner()
                        .frame(width: 12, height: 12)
                    Text("正在同步菜单栏快照与高清图标...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.8)
                )
            }
            
            // 2. 应用列表卡片流
            let items = filteredItems(revision: snapshotRevision)
            if items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "menubar.dock.rectangle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(searchText.isEmpty ? "当前屏幕暂无活动状态栏应用" : "未找到匹配 \"\(searchText)\" 的应用")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.8)
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                            appRow(for: entry)
                            if index < items.count - 1 {
                                Divider()
                                    .padding(.leading, 42)
                            }
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.8)
                )
            }
            
            // 3. 底部简洁提示与手动刷新
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("自动识别被刘海遮挡或挤出屏幕的菜单栏图标，并实时镜像到灵动岛")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
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
        }
        .padding(.top, 2)
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
    
    /// 统一装配应用列表条目（严格只使用原生菜单栏真实截图）
    ///
    /// 取图走**实例**属性 `iconResolver`（而非 `IconResolver.shared`）：既让本行的图标
    /// 与 `@ObservedObject` 建立真实依赖，也让「本视图依赖图标状态」在代码上可见 ——
    /// 直接调单例会让依赖隐式化，正是图标不刷新那处回归得以潜伏的原因。
    private func resolveAppEntry(item: MenuBarItem, index: Int) -> AppListEntry {
        let bundleID = item.bundleIdentifier ?? "win.\(item.windowID)"
        let title = item.title ?? bundleID
        let key = item.preferenceKey
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
    
    /// 装配本面板所选屏幕的应用列表
    ///
    /// - Parameter revision: 快照刷新脉冲，仅用于建立 SwiftUI 依赖（值本身不参与计算）
    private func filteredItems(revision: Int) -> [AppListEntry] {
        let displayID = activeDisplayID
        let currentSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: displayID)
        let menuBarItems = currentSnapshot?.allItems ?? []
        var result: [AppListEntry] = []
        
        // 1. 从单一真实快照中装配当前活动屏幕菜单栏项
        for (index, item) in menuBarItems.enumerated() {
            let entry = resolveAppEntry(item: item, index: index)
            result.append(entry)
        }
        
        // 2. 搜索词模糊过滤
        if !searchText.isEmpty {
            result = result.filter {
                fuzzyMatch(query: searchText, in: $0.title) || fuzzyMatch(query: searchText, in: $0.bundleID)
            }
        }
        
        // 3. 排序策略：
        //   - 岛内溢出项置顶（若存在 customItemOrder 优先按用户自定义排布）
        //   - 菜单栏原生可见项倒序排布
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
    
    /// 字符跳跃式子序列模糊匹配
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
            // 图标容器：深色高对比度衬底（炭黑 + 细微亮边），专为白色/浅色菜单栏图标设计，在浅色与深色系统下均能清晰凸显
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
            
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Text(entry.bundleID)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 极简状态徽标
            if entry.isOverflowed {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                    Text("岛内承接 (溢出)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.8)
                )
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 5, height: 5)
                    Text("菜单栏可见")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(nsColor: .separatorColor).opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
    
    // MARK: - Tab 4: 运行诊断与关于 (Diagnostics & About)
    
    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 应用标志与版本（动态从 Bundle 读取）
                VStack(spacing: 6) {
                    if let iconImage = NSApp.applicationIconImage ?? NSImage(named: "AppIcon") {
                        Image(nsImage: iconImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                    } else {
                        Image(systemName: "menubar.dock.rectangle")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    
                    Text("NotchRail")
                        .font(.title3.weight(.bold))
                    
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.9"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "9"
                    Text("MacBook 物理刘海与状态栏沉浸式扩展 · v\(version) (\(build))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                
                // 权限健康诊断卡片
                VStack(alignment: .leading, spacing: 8) {
                    Text("核心运行权限诊断")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 2)
                    
                    permissionCard(
                        title: "辅助功能权限 (Accessibility)",
                        subtitle: "用于模拟点击并唤起被遮挡应用的原生菜单与弹窗",
                        isGranted: permissionManager.isAccessibilityGranted
                    ) {
                        permissionManager.openSystemSettings()
                    }
                    
                    permissionCard(
                        title: "屏幕录制权限 (Screen Recording)",
                        subtitle: "用于逐窗捕获菜单栏状态项的高清实时图标",
                        isGranted: permissionManager.isScreenCaptureGranted
                    ) {
                        permissionManager.openScreenCaptureSettings()
                    }
                }
                
                // 快捷操作按钮组
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
                        Label(isRefreshingPermissions ? "检测中..." : "重新检测权限与重扫", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    
                    Button("GitHub 源码仓库") {
                        if let url = URL(string: "https://github.com/AeroSheepZ/NotchRail") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                    
                    Button("彻底退出应用", role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    }
                    .controlSize(.small)
                    .tint(.red)
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 8)
        }
    }
    
    @ViewBuilder
    private func permissionStatusBadge(granted: Bool) -> some View {
        if granted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("已授权")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())
        } else {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("未授权")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
        }
    }
    
    @ViewBuilder
    private func permissionCard(
        title: String,
        subtitle: String,
        isGranted: Bool,
        onAction: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            permissionStatusBadge(granted: isGranted)
            Button("去授权", action: onAction)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
