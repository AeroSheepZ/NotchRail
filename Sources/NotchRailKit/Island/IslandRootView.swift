import SwiftUI
import AppKit

/// 灵动岛根视图容器：基于单一流体底座（Morphing Base）驱动 Apple 级弹簧变形与分层级联入场
public struct IslandRootView: View {
    public let displayID: CGDirectDisplayID
    @ObservedObject public var stateMachine: IslandStateMachine
    @ObservedObject var screenManager = ScreenManager.shared
    @ObservedObject var syncCoordinator = MenuBarSyncCoordinator.shared
    @ObservedObject var preferenceStore = PreferenceStore.shared
    @ObservedObject private var iconResolver = IconResolver.shared

    /// 构建指定屏幕的灵动岛根视图
    ///
    /// - Important: 两个参数**均为必填**。生产路径（`IslandWindowCoordinator.createPanel`）必须显式
    ///   绑定本屏 `displayID` 与本屏专属状态机。此处刻意**不提供默认值**：一旦留空就会静默回退到
    ///   主屏基准屏或 `IslandStateMachine.shared`，造成跨屏错渲染却无任何报错 —— 违反 AGENTS.md §2.1
    ///   「严禁回退到别的屏幕或某个单例」。去掉默认值后，「漏传」在编译期即暴露。
    public init(
        displayID: CGDirectDisplayID,
        stateMachine: IslandStateMachine
    ) {
        self.displayID = displayID
        self.stateMachine = stateMachine
    }
    
    public var body: some View {
        // 严格以当前物理 Panel 锚定的屏幕几何为单一真实来源，严禁跨屏借调兜底 (AGENTS.md 2.1)
        if let geometry = screenManager.geometry(for: displayID) {
            contentView(for: geometry)
        }
    }
    
    @ViewBuilder
    private func contentView(for geometry: NotchGeometry) -> some View {
        let targetSnapshot = syncCoordinator.effectiveSnapshot(for: geometry.displayID)
        let isSyncing = syncCoordinator.isPrewarming || (targetSnapshot == nil)
        let overflowItems = targetSnapshot?.overflowItems ?? []
        let isExpanded = stateMachine.currentState.isExpanded
        
        // 动态尺寸与耳翼计算
        let dynamicCompactBounds = geometry.dynamicCompactBounds(for: overflowItems.count, isSyncing: isSyncing)
        // 平直外接屏折叠态的仿真胶囊锚点宽度严格对齐原生刘海（179.0pt），彻底消除自 0 宽形变的僵硬撕裂感
        let compactWidth: CGFloat = geometry.hasPhysicalNotch
            ? dynamicCompactBounds.width
            : 179.0
        let compactHeight = geometry.statusBarHeight
        let dynamicWidth = geometry.dynamicExtendedBounds(for: max(1, overflowItems.count), isSyncing: isSyncing).width
        
        let currentWidth = isExpanded ? dynamicWidth : compactWidth
        let currentHeight = isExpanded ? IslandTheme.Dimension.EXTENDED_HEIGHT : compactHeight
        let currentCornerRadius: CGFloat = isExpanded
            ? IslandTheme.CornerRadius.EXTENDED_BOTTOM
            : IslandTheme.CornerRadius.COMPACT_BOTTOM
        
        // 计算紧凑态相对刘海中心的水平偏移（左耳翼向左延展，底座永不偏移摄像头）
        let leftWing = isExpanded ? 0.0 : (geometry.hasPhysicalNotch ? IslandWingMetrics.leftWingWidth(for: overflowItems.count, isSyncing: isSyncing) : 0.0)
        let horizontalOffset = -leftWing / 2.0
        
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // 1. 硬件级连续变形底座（纯黑吸光底座 + 顶部外展喇叭口）
                IslandBackground(
                    cornerRadius: currentCornerRadius,
                    hasPhysicalNotch: geometry.hasPhysicalNotch
                )
                .frame(width: currentWidth, height: currentHeight)
                
                // 2. 灵动岛内部内容层（分层级联渲染）
                VStack(spacing: 4) {
                    // 顶部栏：加载中左耳翼展示矢量 Spinner；就绪后展示黄色徽标；展开态展示设置齿轮
                    IslandTopBar(
                        overflowCount: overflowItems.count,
                        isSyncing: isSyncing,
                        showsSettingsButton: isExpanded,
                        onSettingsTapped: {
                            SettingsWindowCoordinator.shared.showSettings()
                        }
                    )
                    .padding(.horizontal, isExpanded ? 10 : 0)
                    .padding(.top, isExpanded ? 6 : 0)
                    .frame(height: isExpanded ? 28 : compactHeight)
                    
                    // 下层展开内容区：图标水平滚动列表或空状态提示
                    if isExpanded {
                        VStack(spacing: 4) {
                            Divider()
                                .background(Color.white.opacity(0.12))
                                .padding(.horizontal, 14)
                            
                            if overflowItems.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.green.opacity(0.85))
                                    Text("当前所有菜单栏图标均在原生屏幕中完整显示")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.bottom, 6)
                            } else {
                                ReorderableIconRow(
                                    items: overflowItems,
                                    iconResolver: iconResolver,
                                    onItemTap: handleItemTap,
                                    onItemSecondaryClick: handleItemSecondaryClick,
                                    onReorder: { reordered in
                                        let newOrder = reordered.map { $0.bundleIdentifier ?? $0.persistentKey }
                                        preferenceStore.setCustomItemOrder(newOrder)
                                    }
                                )
                            }
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                                removal: .opacity
                            )
                        )
                    }
                }
                .frame(width: currentWidth, height: currentHeight)
            }
            .offset(x: horizontalOffset)
            .animation(IslandTheme.Animation.FLUID_SPRING, value: currentWidth)
            .animation(IslandTheme.Animation.FLUID_SPRING, value: currentHeight)
            .animation(IslandTheme.Animation.FLUID_SPRING, value: currentCornerRadius)
            .animation(IslandTheme.Animation.FLUID_SPRING, value: horizontalOffset)
            .opacity(geometry.hasPhysicalNotch || isExpanded ? 1.0 : 0.0)
            .animation(
                geometry.hasPhysicalNotch ? nil : (isExpanded ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.28)),
                value: isExpanded
            )
            .contentShape(Rectangle())
            .onHover { isHovered in
                handleHover(isHovered, overflowCount: overflowItems.count, isSyncing: isSyncing)
            }
            // 必须用普通手势（`.onTapGesture`）而非 `simultaneousGesture`：
            // 后者会与子视图的 `Button`（图标 / 设置齿轮）**同时**触发，点图标会连带把岛收起；
            // 普通手势遵循 SwiftUI 的「子视图优先」仲裁 —— 命中图标时由 `Button` 消费，
            // 只有落在岛内空白处（底座、分隔线旁、空状态区）才归本手势，恰好就是「点胶囊」的语义。
            .onTapGesture {
                handleTap(overflowCount: overflowItems.count, isSyncing: isSyncing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - 交互触发分发 (Hover & Click 隔离及 HoverAndClick 复合支持)
    
    private func handleHover(_ isHovered: Bool, overflowCount: Int, isSyncing: Bool) {
        guard !isSyncing else { return }
        // 悬停门禁的唯一判据（三档语义定义见 `TriggerMode.respondsToHover`）
        guard preferenceStore.preferences.triggerMode.respondsToHover else { return }
        
        if isHovered {
            stateMachine.handleMouseEnter(overflowCount: overflowCount)
        } else {
            stateMachine.handleMouseLeave()
        }
    }
    
    /// 左键点击灵动岛本体（不含图标 / 设置齿轮，那两者由各自的 `Button` 消费）
    ///
    /// 语义与模式门禁**全部下沉到 `IslandStateMachine.handleCapsuleTap`**：
    /// 本视图不再自读 `triggerMode`，避免同一枚举出现第二处口径（ADR 0016）。
    private func handleTap(overflowCount: Int, isSyncing: Bool) {
        guard !isSyncing else { return }
        stateMachine.handleCapsuleTap(overflowCount: overflowCount)
    }
    
    /// 左键单击：当场派发，随后收起
    ///
    /// 全程**不引入任何双击判定窗口**：用户对菜单栏图标的诉求只有「单击触发」与
    /// 「辅助点击（触控板双指 / 鼠标右键）触发原生菜单」两种，不存在双击语义。
    /// 若为了等待双击而把收起延后一个双击间隔，或为第二击补发 `clickState = 2`，
    /// 都会把双击间隔内对同一图标的第二次单击吞掉，表现为「单击时灵时不灵」。
    private func handleItemTap(_ targetItem: MenuBarItem) async -> Bool {
        let clickResult = await MenuBarItemClicker.shared.performClick(for: targetItem, kind: .single)
        switch clickResult {
        case .success:
            collapseAfterDispatch()
            return true
        case .failure:
            return false
        }
    }

    /// 辅助点击（触控板双指点击 / 鼠标右键）：把右键透传给归属应用，由它弹出自己的原生菜单
    private func handleItemSecondaryClick(_ targetItem: MenuBarItem) async -> Bool {
        let clickResult = await MenuBarItemClicker.shared.performClick(for: targetItem, kind: .secondary)
        switch clickResult {
        case .success:
            collapseAfterDispatch()
            return true
        case .failure:
            return false
        }
    }

    /// 派发成功后立即原子收起（**恒定执行，不可由偏好关闭**，ADR 0015）
    ///
    /// 收起是**必需**的：灵动岛视口层级高于应用菜单窗口，若保持展开会遮挡刚弹出的原生菜单。
    /// 历史上这项收起曾是一个用户可关闭的偏好项，但关掉后既违反上述平台事实、也让用户误以为
    /// 「灵动岛保持展开」而实为「原生菜单被压住」。该偏好项已随 ADR 0015 删除。
    private func collapseAfterDispatch() {
        stateMachine.triggerCollapse()
    }
}
