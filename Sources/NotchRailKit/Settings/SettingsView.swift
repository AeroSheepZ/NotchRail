import SwiftUI
import AppKit

/// 偏好设置主视图
public struct SettingsView: View {
    @ObservedObject var preferenceStore = PreferenceStore.shared
    @ObservedObject var permissionManager = PermissionManager.shared
    @ObservedObject var syncCoordinator = MenuBarSyncCoordinator.shared
    @ObservedObject private var iconResolver = IconResolver.shared
    
    @State private var selectedTab: Int = 0
    @State private var searchText: String = ""
    @State private var showResetAlert: Bool = false
    @State private var isRefreshingPermissions: Bool = false
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 常规设置
            generalTab
                .tabItem {
                    Label("常规", systemImage: "gearshape")
                }
                .tag(0)
            
            // Tab 2: 悬停与动效
            timingTab
                .tabItem {
                    Label("悬停与动效", systemImage: "timer")
                }
                .tag(1)
            
            // Tab 3: 应用管理
            appsTab
                .tabItem {
                    Label("应用管理", systemImage: "app.badge.checkmark")
                }
                .tag(2)
            
            // Tab 4: 关于与诊断
            aboutTab
                .tabItem {
                    Label("关于与诊断", systemImage: "info.circle")
                }
                .tag(3)
        }
        .padding(16)
        .frame(width: 560, height: 460)
        .alert("确定要恢复所有出厂设置吗？", isPresented: $showResetAlert) {
            Button("取消", role: .cancel) {}
            Button("恢复默认", role: .destructive) {
                preferenceStore.resetToDefaults()
            }
        } message: {
            Text("所有触发模式、动画时延与显示策略都将被重置为出厂推荐配置。")
        }
        .onAppear {
            let actualLaunchAtLogin = LaunchAtLoginManager.isEnabled
            if preferenceStore.preferences.launchAtLogin != actualLaunchAtLogin {
                preferenceStore.update { $0.launchAtLogin = actualLaunchAtLogin }
            }
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
                    Text("鼠标停留在顶部刘海区域时自动触发展开。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .click:
                    Text("鼠标划过或悬停不展开，仅在显式点击顶部胶囊时展开/收起。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .hoverAndClick:
                    Text("既支持鼠标悬停自动展开，也可随时点击胶囊立即切换。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("触发控制")
            }
            
            Section {
                Toggle("点击图标后自动收起灵动岛", isOn: Binding(
                    get: { preferenceStore.preferences.autoCollapseOnClick },
                    set: { val in preferenceStore.update { $0.autoCollapseOnClick = val } }
                ))
                
                Toggle("交互触觉震动反馈", isOn: Binding(
                    get: { preferenceStore.preferences.enableHapticFeedback },
                    set: { val in preferenceStore.update { $0.enableHapticFeedback = val } }
                ))
                
                Toggle("无遮挡图标时自动隐藏灵动岛胶囊", isOn: Binding(
                    get: { preferenceStore.preferences.hideWhenNoOverflow },
                    set: { val in preferenceStore.update { $0.hideWhenNoOverflow = val } }
                ))
            } header: {
                Text("交互与视觉")
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
                    Text("点击屏幕或切换前台窗口使屏幕获得焦点时，灵动岛自动跟随迁移至该屏幕。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .mainScreenOnly:
                    Text("灵动岛始终固定在内置刘海屏或主显示器顶部，不在外接屏幕显示。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .disabled:
                    Text("仅在内置刘海屏启用灵动岛，连接外接屏幕时在外接屏完全隐藏。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("多显示器支持")
            }
            
            Section {
                Toggle("在 macOS 顶部菜单栏显示常驻托盘图标", isOn: Binding(
                    get: { preferenceStore.preferences.showMenuBarIcon },
                    set: { val in preferenceStore.update { $0.showMenuBarIcon = val } }
                ))
                
                Toggle("登录时自动启动 NotchRail", isOn: Binding(
                    get: { preferenceStore.preferences.launchAtLogin },
                    set: { val in
                        preferenceStore.update { $0.launchAtLogin = val }
                        LaunchAtLoginManager.setEnabled(val)
                    }
                ))
            } header: {
                Text("系统与托盘")
            }
            
            Section {
                HStack {
                    Text("彻底退出 NotchRail 应用程序")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("退出 NotchRail", role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } header: {
                Text("应用控制")
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 2: 悬停与动效 (Timing)
    
    private var timingTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("展开悬停防抖延迟")
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
                    
                    Text("鼠标进入刘海区域后停留超过此时间才触发展开，防止快速划过误触。推荐 120ms。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("移出收起宽限延迟")
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
                    
                    Text("光标离开灵动岛后保留的宽限时间，期间重新移入可无缝中断收起。推荐 300ms。")
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
                    
                    Button("恢复出厂推荐时延") {
                        preferenceStore.update {
                            $0.hoverExpandDelayMs = IslandTheme.Timing.HOVER_EXPAND_DELAY * 1000.0
                            $0.collapseDelayMs = IslandTheme.Timing.COLLAPSE_DELAY * 1000.0
                        }
                    }
                    .controlSize(.small)
                }
            } header: {
                Text("时序控制")
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 3: 应用管理 (Apps)
    
    private var appsTab: some View {
        VStack(spacing: 14) {
            // 1. 顶部现代化搜索与统计栏
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                    
                    TextField("搜索应用名称或 Bundle ID...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.95))
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                
                // 状态统计徽章
                let allItems = filteredItems()
                let overflowCount = allItems.filter { $0.isOverflowed }.count
                HStack(spacing: 6) {
                    Text("共 \(allItems.count) 项")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                    
                    if overflowCount > 0 {
                        Text("\(overflowCount) 溢出")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }
            
            // 同步中呼吸微光条
            if syncCoordinator.isPrewarming {
                HStack(spacing: 8) {
                    IslandSpinner()
                        .frame(width: 12, height: 12)
                    Text("正在同步菜单栏快照与高清图标...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.70))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.40))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            
            // 2. 应用列表卡片流
            let items = filteredItems()
            if items.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "menubar.dock.rectangle")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.white.opacity(0.25))
                    Text(searchText.isEmpty ? "当前屏幕暂无活动状态栏应用" : "未找到匹配 \"\(searchText)\" 的应用")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.50))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { entry in
                            appRow(for: entry)
                        }
                    }
                    .padding(6)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            
            // 3. 底部简洁提示与手动刷新
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundColor(.orange.opacity(0.8))
                    Text("NotchRail 自动识别被刘海遮挡或挤出屏幕的菜单栏图标并实时镜像到灵动岛")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                }
                
                Spacer()
                
                Button {
                    syncCoordinator.scheduleSync(immediate: true, showProgress: true)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("立即重扫")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.top, 4)
    }
    
    private struct AppListEntry: Identifiable {
        var id: String { uniqueKey }
        let uniqueKey: String
        let originalIndex: Int
        let title: String
        let bundleID: String
        let isOverflowed: Bool
        let statusIcon: NSImage?
    }
    
    /// 统一装配应用列表条目（严格只使用原生菜单栏真实截图）
    private func resolveAppEntry(item: MenuBarItem, index: Int) -> AppListEntry {
        let bundleID = item.bundleIdentifier ?? "win.\(item.windowID)"
        let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let title = item.title ?? runningApp?.localizedName ?? bundleID
        
        // 从 IconResolver 获取当前窗口捕获的真实菜单栏状态图标
        let statusImage: NSImage? = {
            if case .loaded(let img) = IconResolver.shared.iconStates[item.iconCacheKey] {
                return img
            }
            return nil
        }()
        
        return AppListEntry(
            uniqueKey: "\(bundleID)_\(item.windowID)",
            originalIndex: index,
            title: title,
            bundleID: bundleID,
            isOverflowed: item.displayMode == .overflowed,
            statusIcon: statusImage
        )
    }
    
    private func filteredItems() -> [AppListEntry] {
        let prefs = preferenceStore.preferences
        let geom = ScreenManager.shared.effectiveGeometry(for: prefs.externalDisplayMode)
        let currentSnapshot = syncCoordinator.snapshot(for: geom.displayID) ?? syncCoordinator.latestSnapshot
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
        //   - 第 1 梯队：溢出项（isOverflowed == true，岛内展示），置顶（按扫描物理顺序 originalIndex 升序）
        //   - 第 2 梯队：原生可见项（!isOverflowed，顶栏可见），倒序排布（originalIndex 降序）
        result.sort { lhs, rhs in
            if lhs.isOverflowed != rhs.isOverflowed {
                return lhs.isOverflowed && !rhs.isOverflowed
            }
            if lhs.isOverflowed && rhs.isOverflowed {
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
                return max(28.0, min(80.0, iconHeight * ratio + 10))
            }
            return 28.0
        }()
        
        HStack(spacing: 12) {
            // 图标容器：深色高对比度衬底，自适应长方形/正方形图标宽度，清晰呈现真实单栏图标
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
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
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(width: containerWidth, height: 26)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                Text(entry.bundleID)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }
            
            Spacer()
            
            // 极简状态徽标
            if entry.isOverflowed {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                    Text("岛内展示 (溢出)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.14))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.orange.opacity(0.30), lineWidth: 0.8)
                )
                .clipShape(Capsule())
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green.opacity(0.9))
                        .frame(width: 5, height: 5)
                    Text("原生可见")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green.opacity(0.90))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.green.opacity(0.25), lineWidth: 0.8)
                )
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(entry.isOverflowed ? 0.10 : 0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Tab 4: 关于与诊断 (About & Health)
    
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
                    
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.5"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "5"
                    Text("Extended Menu Bar for MacBook Notch · v\(version) (\(build))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                
                // 权限健康卡片
                VStack(spacing: 8) {
                    permissionCard(
                        title: "辅助功能权限 (Accessibility)",
                        subtitle: "用于派发原生菜单栏点击事件",
                        isGranted: permissionManager.isAccessibilityGranted
                    ) {
                        permissionManager.openSystemSettings()
                    }
                    
                    permissionCard(
                        title: "屏幕录制权限 (Screen Recording)",
                        subtitle: "用于按 windowID 截取高清实时图标",
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
                        syncCoordinator.scheduleSync(immediate: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isRefreshingPermissions = false
                        }
                    } label: {
                        Label(isRefreshingPermissions ? "检测中..." : "刷新状态与重扫", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    
                    Button("GitHub 仓库") {
                        if let url = URL(string: "https://github.com/AeroSheepZ/NotchRail") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                    
                    Button("退出应用", role: .destructive) {
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
