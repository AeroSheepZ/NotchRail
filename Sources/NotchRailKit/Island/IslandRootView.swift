import SwiftUI
import AppKit

/// 灵动岛根视图容器：基于单一流体底座（Morphing Base）驱动 Apple 级弹簧变形与分层级联入场
public struct IslandRootView: View {
    @ObservedObject var screenManager = ScreenManager.shared
    @ObservedObject var stateMachine = IslandStateMachine.shared
    @ObservedObject var syncCoordinator = MenuBarSyncCoordinator.shared
    @ObservedObject var preferenceStore = PreferenceStore.shared
    @ObservedObject private var iconResolver = IconResolver.shared
    
    public init() {}
    
    public var body: some View {
        let prefs = preferenceStore.preferences
        let geometry = (prefs.externalDisplayMode == .mainScreenOnly)
            ? screenManager.primaryGeometry
            : screenManager.currentGeometry
        
        let targetSnapshot = syncCoordinator.snapshot(for: geometry.displayID)
        let isSyncing = syncCoordinator.isPrewarming || (targetSnapshot == nil)
        let overflowItems = targetSnapshot?.overflowItems ?? []
        let isExpanded = stateMachine.currentState.isExpanded
        
        // 动态尺寸与耳翼计算
        let dynamicCompactBounds = geometry.dynamicCompactBounds(for: overflowItems.count, isSyncing: isSyncing)
        let compactWidth = dynamicCompactBounds.width
        let compactHeight = geometry.statusBarHeight
        let dynamicWidth = geometry.dynamicExtendedBounds(for: max(1, overflowItems.count), isSyncing: isSyncing).width
        
        let currentWidth = isExpanded ? dynamicWidth : compactWidth
        let currentHeight = isExpanded ? IslandTheme.Dimension.EXTENDED_HEIGHT : compactHeight
        let currentCornerRadius = isExpanded ? IslandTheme.CornerRadius.EXTENDED_BOTTOM : IslandTheme.CornerRadius.COMPACT_BOTTOM
        
        // 计算紧凑态相对刘海中心的水平偏移（左耳翼向左延展，底座永不偏移摄像头）
        let leftWing = isExpanded ? 0.0 : IslandWingMetrics.leftWingWidth(for: overflowItems.count, isSyncing: isSyncing)
        let horizontalOffset = -leftWing / 2.0
        
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // 1. 硬件级连续变形刘海底座（纯黑吸光底座 + 顶部开口微光描边）
                IslandBackground(cornerRadius: currentCornerRadius)
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
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(overflowItems) { item in
                                            IslandIconCell(
                                                item: item,
                                                state: iconResolver.iconStates[item.iconCacheKey] ?? .pending,
                                                onTap: handleItemTap
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 2)
                                }
                                .frame(height: 36)
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
            .animation(IslandTheme.Animation.FLUID_SPRING, value: horizontalOffset)
            .contentShape(Rectangle())
            .onHover { isHovered in
                handleHover(isHovered, overflowCount: overflowItems.count, isSyncing: isSyncing)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    handleTap(overflowCount: overflowItems.count, isSyncing: isSyncing)
                }
            )
            .id(geometry.displayID)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - 交互触发分发 (Hover & Click 隔离及 HoverAndClick 复合支持)
    
    private func handleHover(_ isHovered: Bool, overflowCount: Int, isSyncing: Bool) {
        guard !isSyncing else { return }
        let prefs = preferenceStore.preferences
        // 允许 hover 与 hoverAndClick 模式触发悬停防抖
        guard prefs.triggerMode == .hover || prefs.triggerMode == .hoverAndClick else { return }
        
        if isHovered {
            IslandStateMachine.shared.handleMouseEnter(overflowCount: overflowCount)
        } else {
            IslandStateMachine.shared.handleMouseLeave()
        }
    }
    
    private func handleTap(overflowCount: Int, isSyncing: Bool) {
        guard !isSyncing else { return }
        let prefs = preferenceStore.preferences
        // 允许 click 与 hoverAndClick 模式触发点击即时展开/收起
        guard prefs.triggerMode == .click || prefs.triggerMode == .hoverAndClick else { return }
        
        if IslandStateMachine.shared.currentState.isExpanded {
            IslandStateMachine.shared.triggerCollapse()
        } else {
            IslandStateMachine.shared.triggerExpand(overflowCount: overflowCount)
        }
    }
    
    private func handleItemTap(_ targetItem: MenuBarItem) async -> Bool {
        let clickResult = await MenuBarItemClicker.shared.performClick(for: targetItem)
        switch clickResult {
        case .success:
            if preferenceStore.preferences.autoCollapseOnClick {
                IslandStateMachine.shared.triggerCollapse()
            }
            return true
        case .failure:
            return false
        }
    }
}
