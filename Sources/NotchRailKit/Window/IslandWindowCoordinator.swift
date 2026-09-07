import Foundation
import AppKit
import SwiftUI
import Combine

/// 协调 IslandPanel 窗口的创建、布局锚定与显示隐藏及多屏动态迁移
/// 采用黄金吸顶视口架构 + 聚焦跟随体系：
/// 1. 视口层：窗口在当前目标屏幕顶部保持稳固常驻（高度为 EXTENDED_HEIGHT 84pt），展开/收起绝不改变原生窗口 Frame；
/// 2. 聚焦跟随：窗口严格根据用户激活的焦点屏幕迁移，单例 Panel 在各屏之间自然流转；
/// 3. 平直屏规范：外接平直显示器在折叠常态下 100% 隐形透明（alpha = 0.0）且鼠标 100% 物理直通，展开时原位呈现纯黑仿真灵动岛。
@MainActor
public final class IslandWindowCoordinator: ObservableObject {
    public static let shared = IslandWindowCoordinator()
    
    private var panel: IslandPanel?
    private var cancellables = Set<AnyCancellable>()
    private var lastActiveDisplayID: CGDirectDisplayID?
    
    /// 当前 Panel 实际锚定的屏幕几何（单一可信数据源，驱动 IslandHostingView 与 IslandRootView）
    @Published public private(set) var currentPanelGeometry: NotchGeometry
    
    private init() {
        let initialGeom = ScreenManager.shared.primaryGeometry
        self.currentPanelGeometry = initialGeom
        
        // 监听当前屏幕几何变更（含多屏切换），平滑迁移视口锚点
        ScreenManager.shared.$currentGeometry
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)
            
        // 监听屏幕拓扑变动（插拔显示器、合盖/开盖）
        ScreenManager.shared.$allGeometries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)
            
        // 监听偏好变动（多屏模式、空状态隐藏等）
        NotificationCenter.default.publisher(for: .preferencesChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)
            
        // 监听菜单栏快照刷新（检查溢出项数量）
        NotificationCenter.default.publisher(for: .menuBarSnapshotUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)
            
        // 监听状态机展开/收起变化
        IslandStateMachine.shared.$currentState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)
    }
    
    /// 初始化并挂载灵动岛窗口，启动多屏追踪
    public func start() {
        if panel != nil { return }
        
        let prefs = PreferenceStore.shared.preferences
        let geometry = ScreenManager.shared.effectiveGeometry(for: prefs.externalDisplayMode)
        self.currentPanelGeometry = geometry
        let viewportBounds = calculateViewportBounds(for: geometry)
        
        let panel = IslandPanel(contentRect: viewportBounds)
        let rootView = IslandRootView()
        let hostingView = IslandHostingView(rootView: rootView)
        
        // 强制图层背景完全透明，防止 macOS 渲染默认灰色直角背景
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        
        panel.contentView = hostingView
        panel.setFrame(viewportBounds, display: true)
        
        self.panel = panel
        self.lastActiveDisplayID = geometry.displayID
        
        // 启动全局鼠标跨屏焦点追踪与透明区域硬件级事件穿透
        MouseMonitor.shared.startMonitoring()
        
        applyDisplayAndVisibilityRules()
    }
    
    /// 动态设置物理窗口的鼠标事件穿透性（硬件级无缝穿透底层 Chrome / Safari）
    public func setIgnoresMouseEvents(_ ignores: Bool) {
        guard let panel = self.panel else { return }
        if panel.ignoresMouseEvents != ignores {
            panel.ignoresMouseEvents = ignores
        }
    }
    
    /// 计算覆盖灵动岛全展开区域的稳定透明视口区域（吸顶居中常驻，展开/收起永不改变 Frame）
    private func calculateViewportBounds(for geometry: NotchGeometry) -> CGRect {
        let viewportWidth = min(geometry.screenFrame.width * 0.85, 800.0)
        let viewportHeight: CGFloat = IslandTheme.Dimension.EXTENDED_HEIGHT
        let viewportX = geometry.screenFrame.minX + (geometry.screenFrame.width - viewportWidth) / 2.0
        let viewportY = geometry.screenFrame.maxY - viewportHeight
        return CGRect(x: viewportX, y: viewportY, width: viewportWidth, height: viewportHeight)
    }
    
    /// 综合应用多显示器聚焦跟随策略、0 溢出自动隐藏与平直外接屏常态隐形规则
    public func applyDisplayAndVisibilityRules() {
        guard let panel = self.panel else { return }
        
        let prefs = PreferenceStore.shared.preferences
        let currentGeom = ScreenManager.shared.currentGeometry
        let mainGeom = ScreenManager.shared.primaryGeometry
        
        // 1. 判断多显示器策略
        let effectiveGeom: NotchGeometry
        var shouldHideForExternal = false
        
        switch prefs.externalDisplayMode {
        case .followFocusedScreen:
            effectiveGeom = currentGeom
        case .mainScreenOnly:
            effectiveGeom = mainGeom
        case .disabled:
            if !currentGeom.hasPhysicalNotch && !currentGeom.isBuiltIn {
                shouldHideForExternal = true
            }
            effectiveGeom = currentGeom
        }
        
        if shouldHideForExternal {
            panel.orderOut(nil)
            return
        }
        
        self.currentPanelGeometry = effectiveGeom
        
        // 2. 检查目标屏幕多屏预热快照
        let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: effectiveGeom.displayID)
        let overflowCount = targetSnapshot?.overflowCount ?? 0
        let hasNoOverflow = overflowCount == 0
        let isScreenSwitching = (lastActiveDisplayID != nil && lastActiveDisplayID != effectiveGeom.displayID)
        self.lastActiveDisplayID = effectiveGeom.displayID
        
        // 3. 切屏或处于未唤醒全屏空间时，原子重置展开态，确保到达新屏幕或全屏时处于纯净初始态
        if isScreenSwitching || (effectiveGeom.isFullScreenSpace && !MouseMonitor.shared.isAwakenedInFullScreen) {
            if IslandStateMachine.shared.currentState.isExpanded {
                IslandStateMachine.shared.triggerCollapse()
            }
        }
        
        // 4. 普通桌面空间且状态机处于 fullScreenHidden 时，主动闭环唤醒恢复 compact
        if !effectiveGeom.isFullScreenSpace && IslandStateMachine.shared.currentState.isFullScreenHidden {
            IslandStateMachine.shared.awakenFromFullScreen()
        }
        
        let isExpanded = IslandStateMachine.shared.currentState.isExpanded
        let shouldHideForNoOverflow = prefs.hideWhenNoOverflow && hasNoOverflow && !isExpanded
        let isFullScreenHidden = IslandStateMachine.shared.currentState.isFullScreenHidden ||
                                (effectiveGeom.isFullScreenSpace && !MouseMonitor.shared.isAwakenedInFullScreen)
        
        // 【v0.0.8 核心规范】：平直外接屏在折叠常态下不显示紧凑态灵动岛（100% 隐形、100% 物理穿透，消除虚拟假刘海）
        let shouldHideForFlatExternal = !effectiveGeom.hasPhysicalNotch && !isExpanded
        
        let targetViewport = calculateViewportBounds(for: effectiveGeom)
        
        if isFullScreenHidden || shouldHideForNoOverflow || shouldHideForFlatExternal {
            panel.ignoresMouseEvents = true
            updatePanelViewport(panel, targetViewport: targetViewport, targetAlpha: 0.0, duration: 0.20, immediate: isScreenSwitching)
        } else {
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            updatePanelViewport(panel, targetViewport: targetViewport, targetAlpha: 1.0, duration: 0.18, immediate: false, preZeroAlpha: isScreenSwitching)
        }
    }
    
    /// 统一驱动视口坐标迁移与透明度平滑过渡（消除重复代码）
    private func updatePanelViewport(
        _ panel: IslandPanel,
        targetViewport: CGRect,
        targetAlpha: CGFloat,
        duration: TimeInterval,
        immediate: Bool,
        preZeroAlpha: Bool = false
    ) {
        if preZeroAlpha {
            panel.alphaValue = 0.0
        }
        if panel.frame != targetViewport {
            panel.setFrame(targetViewport, display: true)
        }
        if immediate {
            panel.alphaValue = targetAlpha
        } else if panel.alphaValue != targetAlpha {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                panel.animator().alphaValue = targetAlpha
            }
        }
    }
    
    /// 检查点击位置是否落在当前灵动岛/浮轨展开交互区域外部；若在外部且当前处于展开态，则立即驱动收起 (Ticket #48)
    public func handleOutsideClickIfNeeded(at location: CGPoint) {
        guard IslandStateMachine.shared.currentState.isExpanded else { return }
        let geom = currentPanelGeometry
        let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)
        let overflowCount = targetSnapshot?.overflowCount ?? IslandStateMachine.shared.activeOverflowCount
        let screenRect = geom.interactiveScreenRect(isExpanded: true, overflowCount: overflowCount)
        let paddedRect = screenRect.insetBy(dx: -4, dy: -4)
        if !NSMouseInRect(location, paddedRect, false) {
            IslandStateMachine.shared.triggerCollapse()
        }
    }
}
