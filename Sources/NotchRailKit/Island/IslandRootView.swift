import SwiftUI

/// 灵动岛根视图容器：基于单一流体底座（Morphing Base）驱动 Apple 级弹簧变形与分层级联入场
public struct IslandRootView: View {
    @ObservedObject var screenManager = ScreenManager.shared
    @ObservedObject var stateMachine = IslandStateMachine.shared
    @ObservedObject var syncCoordinator = MenuBarSyncCoordinator.shared
    @ObservedObject private var iconResolver = IconResolver.shared
    
    public init() {}
    
    public var body: some View {
        let geometry = screenManager.currentGeometry
        let snapshot = syncCoordinator.latestSnapshot
        let snapshotIsCurrent = (snapshot?.displayID == geometry.displayID)
        let overflowItems = snapshotIsCurrent ? (snapshot?.overflowItems ?? []) : []
        let isExpanded = stateMachine.currentState.isExpanded
        
        // 动态尺寸计算（紧凑与展开态宽度、高度、圆角）
        let compactWidth = geometry.compactBounds.width
        let dynamicWidth = geometry.dynamicExtendedBounds(for: max(1, overflowItems.count)).width
        let currentWidth = isExpanded ? dynamicWidth : compactWidth
        let currentHeight = isExpanded ? IslandTheme.Dimension.EXTENDED_HEIGHT : IslandTheme.Dimension.COMPACT_HEIGHT
        let currentCornerRadius = isExpanded ? IslandTheme.CornerRadius.EXTENDED_BOTTOM : IslandTheme.CornerRadius.COMPACT_BOTTOM
        
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // 1. 硬件级连续变形刘海底座（纯黑吸光底座 + 顶部开口微光描边）
                IslandBackground(cornerRadius: currentCornerRadius)
                    .frame(width: currentWidth, height: currentHeight)
                
                // 2. 灵动岛内部内容层（分层级联渲染）
                VStack(spacing: 6) {
                    // 顶部栏：徽章常驻；设置齿轮仅展开态显示（极简态胶囊右侧与刘海平齐不遮挡原生图标）
                    IslandTopBar(
                        overflowCount: overflowItems.count,
                        isSyncing: !snapshotIsCurrent,
                        showsSettingsButton: isExpanded,
                        onSettingsTapped: {
                            SettingsWindowCoordinator.shared.showSettings()
                        }
                    )
                    .padding(.horizontal, isExpanded ? 14 : 7)
                    .padding(.top, isExpanded ? 8 : 0)
                    .frame(height: IslandTheme.Dimension.COMPACT_HEIGHT)
                    
                    // 下层展开内容区：图标水平滚动列表或空状态提示
                    if isExpanded {
                        VStack(spacing: 6) {
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
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(overflowItems) { item in
                                            IslandIconCell(
                                                item: item,
                                                state: iconResolver.iconStates[item.iconCacheKey] ?? .pending,
                                                onTap: { itm in
                                                    await handleItemTap(itm)
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.bottom, 6)
                            }
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -8)),
                                removal: .opacity.combined(with: .offset(y: -6))
                            )
                        )
                    }
                }
                .frame(width: currentWidth, height: currentHeight, alignment: .top)
            }
            .contentShape(NotchShape(bottomCornerRadius: currentCornerRadius))
            .onHover { isHovered in
                if isHovered {
                    stateMachine.handleMouseEnter(overflowCount: overflowItems.count)
                } else {
                    stateMachine.handleMouseLeave()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(IslandTheme.Animation.FLUID_SPRING, value: isExpanded)
        .animation(IslandTheme.Animation.FLUID_SPRING, value: currentWidth)
        // 图标捕获仅在展开期间运行（gating：无可见消费者时不产生截图开销）
        // 收起 → id 变 nil → 任务自动取消
        // id 用 windowID（跨扫描周期稳定），避免每次快照刷新（UUID 变化）重启循环
        .task(id: isExpanded ? overflowItems.map(\.windowID) : nil) {
            guard isExpanded, !overflowItems.isEmpty else { return }

            // 首轮立即解析（首见项先出占位，截图落地后只更新变化项）
            await IconResolver.shared.resolveIcons(for: overflowItems)

            // 展开期间周期性刷新（时钟 / 电池等动态图标保持鲜活）
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                await IconResolver.shared.resolveIcons(for: overflowItems)
            }
        }
    }
    
    /// 处理图标点击交互并返回执行结果
    private func handleItemTap(_ item: MenuBarItem) async -> Bool {
        let result = await MenuBarItemClicker.shared.performClick(for: item)
        switch result {
        case .success:
            Task { @MainActor in
                stateMachine.triggerCollapse()
            }
            return true
        case .failure:
            return false
        }
    }
}
