import SwiftUI
import AppKit

/// 偏好设置主视图
public struct SettingsView: View {
    @ObservedObject var preferenceStore = PreferenceStore.shared
    @ObservedObject var permissionManager = PermissionManager.shared
    @ObservedObject var syncCoordinator = MenuBarSyncCoordinator.shared
    
    @State private var selectedTab: Int = 0
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 常规设置
            generalTab
                .tabItem {
                    Label("常规", systemImage: "gearshape")
                }
                .tag(0)
            
            // Tab 2: 灵敏度与动效
            sensitivityTab
                .tabItem {
                    Label("悬停灵敏度", systemImage: "timer")
                }
                .tag(1)
            
            // Tab 3: 应用管理
            appsTab
                .tabItem {
                    Label("应用管理", systemImage: "app.badge.checkmark")
                }
                .tag(2)
            
            // Tab 4: 关于
            aboutTab
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
                .tag(3)
        }
        .padding(20)
        .frame(width: 500, height: 400)
    }
    
    // MARK: - Subviews
    
    private var generalTab: some View {
        Form {
            Section {
                Toggle("登录时自动启动 NotchRail", isOn: Binding(
                    get: { preferenceStore.preferences.launchAtLogin },
                    set: { newValue in
                        preferenceStore.update { $0.launchAtLogin = newValue }
                        LaunchAtLoginManager.setEnabled(newValue)
                    }
                ))
            } header: {
                Text("系统启动")
            }
            
            Section {
                // 辅助功能权限（必需）
                HStack {
                    Text("辅助功能权限")
                    Spacer()
                    permissionStatusView(granted: permissionManager.isAccessibilityGranted)
                }
                Button("打开系统辅助功能设置...") {
                    permissionManager.openSystemSettings()
                }

                // 屏幕录制权限（推荐，用于图标真实画面预览）
                HStack {
                    Text("屏幕录制权限")
                    Spacer()
                    permissionStatusView(granted: permissionManager.isScreenCaptureGranted)
                }
                Button("打开屏幕录制设置...") {
                    permissionManager.openScreenCaptureSettings()
                }
            } header: {
                Text("权限与安全")
            } footer: {
                Text("辅助功能用于检测并点击被遮挡的菜单栏图标（必需）；屏幕录制用于在岛内预览图标的真实画面（未授权时显示权限提示）。")
            }
        }
        .formStyle(.grouped)
    }
    
    /// 权限状态视图（已授权 / 未授权）
    @ViewBuilder
    private func permissionStatusView(granted: Bool) -> some View {
        if granted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("已授权")
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("未授权")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var sensitivityTab: some View {
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
                    
                    Text("鼠标进入刘海区域后停留超过此时间才触发展开，防止快速划过误触。")
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
                        step: 25
                    )
                    
                    Text("光标离开灵动岛后保留的宽限时间，期间重新移入可无缝中断收起。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("悬停时序控制")
            }
        }
        .formStyle(.grouped)
    }
    
    private var appsTab: some View {
        Form {
            Section {
                let allItems = syncCoordinator.latestSnapshot?.allItems ?? []
                if allItems.isEmpty {
                    Text("未发现活动的菜单栏应用（请确保已授权辅助功能权限并扫描）")
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(allItems, id: \.id) { item in
                                appRowView(for: item)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            } header: {
                Text("菜单栏应用过滤 (被隐藏的应用不会在灵动岛内展示)")
            }
        }
        .formStyle(.grouped)
    }
    
    @ViewBuilder
    private func appRowView(for item: MenuBarItem) -> some View {
        let bundleID = item.bundleIdentifier ?? "unknown.bundle"
        let isIgnored = preferenceStore.preferences.ignoredBundleIDs.contains(bundleID)

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? bundleID)
                    .font(.subheadline.weight(.medium))
                Text(bundleID)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 当前展示状态标记
            modeBadge(for: item.displayMode)

            if isIgnored {
                Button("取消隐藏") {
                    preferenceStore.toggleIgnored(bundleID: bundleID)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            } else {
                Button("在岛内隐藏") {
                    preferenceStore.toggleIgnored(bundleID: bundleID)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)

        Divider()
    }

    /// 展示状态徽标：岛内显示（溢出）/ 原生可见 / 已隐藏（忽略）
    @ViewBuilder
    private func modeBadge(for mode: MenuBarItem.DisplayMode) -> some View {
        let style = badgeStyle(for: mode)
        Text(style.label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(style.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(style.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func badgeStyle(for mode: MenuBarItem.DisplayMode) -> (label: String, color: Color) {
        switch mode {
        case .overflowed:
            return ("岛内显示", .orange)
        case .nativeVisible:
            return ("原生可见", .secondary)
        case .ignored:
            return ("已隐藏", .red)
        }
    }
    
    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()
            
            if let iconImage = NSApp.applicationIconImage ?? NSImage(named: "AppIcon") {
                Image(nsImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: "menubar.dock.rectangle")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            
            VStack(spacing: 4) {
                Text("NotchRail")
                    .font(.title2.weight(.bold))
                
                Text("Extended Menu Bar for MacBook Notch")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                Text("版本 \(version) (Build \(build))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            
            Text("把被刘海挤走的菜单栏，延伸到灵动岛。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            HStack(spacing: 16) {
                Button("GitHub 仓库") {
                    if let url = URL(string: "https://github.com/AeroSheepZ/NotchRail") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
                
                Button("重新扫描菜单栏") {
                    syncCoordinator.scheduleSync(immediate: true)
                }
                .controlSize(.small)
            }
            .padding(.bottom, 8)
        }
    }
}
