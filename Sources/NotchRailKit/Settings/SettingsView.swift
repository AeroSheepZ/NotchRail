import SwiftUI
import AppKit

/// 偏好设置主视图
public struct SettingsView: View {
    @ObservedObject var preferenceStore = PreferenceStore.shared
    @ObservedObject var permissionManager = PermissionManager.shared
    @ObservedObject var syncCoordinator = MenuBarSyncCoordinator.shared
    
    @State private var selectedTab: Int = 0
    @State private var searchText: String = ""
    @State private var manualBundleID: String = ""
    @State private var showResetAlert: Bool = false
    @State private var showClearBlacklistAlert: Bool = false
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
            Text("所有触发模式、时延与黑名单规则都将被重置为出厂推荐配置。")
        }
        .alert("确定要清空所有黑名单规则吗？", isPresented: $showClearBlacklistAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                preferenceStore.clearAllIgnored()
            }
        } message: {
            Text("已在灵动岛内隐藏的应用将全部恢复正常展示。")
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
        VStack(spacing: 12) {
            // 搜索过滤与手动添加
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索应用名称或 Bundle ID...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                
                HStack(spacing: 4) {
                    TextField("手动输入 Bundle ID", text: $manualBundleID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                    
                    Button("添加") {
                        preferenceStore.addIgnored(bundleID: manualBundleID)
                        manualBundleID = ""
                    }
                    .disabled(manualBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            // 应用列表
            let items = filteredItems()
            if items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "未发现活动的菜单栏应用" : "未找到匹配 \"\(searchText)\" 的应用")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                List(items, id: \.uniqueKey) { entry in
                    appRow(for: entry)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .cornerRadius(8)
            }
            
            // 底部操作栏
            HStack {
                Text("已隐藏应用: \(preferenceStore.preferences.ignoredBundleIDs.count) 个")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                if !preferenceStore.preferences.ignoredBundleIDs.isEmpty {
                    Button("清空所有黑名单规则") {
                        showClearBlacklistAlert = true
                    }
                    .controlSize(.small)
                    .foregroundColor(.red)
                }
            }
        }
        .padding(.top, 4)
    }
    
    private struct AppListEntry: Identifiable {
        var id: String { uniqueKey }
        let uniqueKey: String
        let title: String
        let bundleID: String
        let isOverflowed: Bool
        let isNativeVisible: Bool
        let isIgnored: Bool
        let appIcon: NSImage?
    }
    
    /// 统一装配应用列表条目（消除重复代码）
    private func resolveAppEntry(
        bundleID: String,
        titleFallback: String?,
        isOverflowed: Bool,
        isNativeVisible: Bool,
        isIgnored: Bool
    ) -> AppListEntry {
        let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let icon = runningApp?.icon ?? NSWorkspace.shared.icon(forFile: runningApp?.bundleURL?.path ?? "")
        let title = titleFallback ?? runningApp?.localizedName ?? bundleID
        
        return AppListEntry(
            uniqueKey: bundleID,
            title: title,
            bundleID: bundleID,
            isOverflowed: isOverflowed,
            isNativeVisible: isNativeVisible,
            isIgnored: isIgnored,
            appIcon: icon
        )
    }
    
    private func filteredItems() -> [AppListEntry] {
        let prefs = preferenceStore.preferences
        let geom = (prefs.externalDisplayMode == .mainScreenOnly)
            ? ScreenManager.shared.primaryGeometry
            : ScreenManager.shared.currentGeometry
        let currentSnapshot = syncCoordinator.snapshot(for: geom.displayID) ?? syncCoordinator.latestSnapshot
        let menuBarItems = currentSnapshot?.allItems ?? []
        var seenBundleIDs = Set<String>()
        var result: [AppListEntry] = []
        
        let notchRightEdge = geom.physicalNotchRect.maxX
        let screenMinX = geom.screenFrame.minX
        let screenMaxX = geom.screenFrame.maxX
        
        // 1. 当前活动屏幕菜单栏中真实存在的应用
        for item in menuBarItems {
            let bundleID = item.bundleIdentifier ?? "unknown.\(item.windowID)"
            if seenBundleIDs.contains(bundleID) { continue }
            seenBundleIDs.insert(bundleID)
            
            let isIgnored = preferenceStore.preferences.ignoredBundleIDs.contains(bundleID)
            let frame = item.nativeFrame
            let isGeometricallyOverflowed = (frame.minX < notchRightEdge || frame.maxX > (screenMaxX + 5) || frame.maxX < screenMinX)
            
            let entry = resolveAppEntry(
                bundleID: bundleID,
                titleFallback: item.title,
                isOverflowed: isGeometricallyOverflowed,
                isNativeVisible: !isGeometricallyOverflowed,
                isIgnored: isIgnored
            )
            result.append(entry)
        }
        
        // 2. 搜索词模糊过滤
        if !searchText.isEmpty {
            result = result.filter {
                fuzzyMatch(query: searchText, in: $0.title) || fuzzyMatch(query: searchText, in: $0.bundleID)
            }
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
        HStack(spacing: 10) {
            if let icon = entry.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                Text(entry.bundleID)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 状态徽标
            if entry.isIgnored {
                Text("已在岛内隐藏")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
            } else if entry.isOverflowed {
                Text("岛内展示 (溢出)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                Text("原生可见")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            // 操作按钮
            if entry.isIgnored {
                Button("取消隐藏") {
                    preferenceStore.toggleIgnored(bundleID: entry.bundleID)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            } else {
                Button("在岛内隐藏") {
                    preferenceStore.toggleIgnored(bundleID: entry.bundleID)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
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
                    
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.4"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
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
