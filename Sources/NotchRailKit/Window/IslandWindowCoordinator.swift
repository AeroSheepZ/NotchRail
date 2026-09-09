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
    
    /// 主屏常驻物理刘海面板（MacBook 物理刘海屏常驻 Compact 胶囊与黄色徽标，Issue #53）
    public private(set) var primaryPanel: IslandPanel?
    /// 外接平直显示器独立面板（折叠常态 100% 隐形透明且穿透，触碰原位展开，Issue #53）
    public private(set) var externalPanel: IslandPanel?
    
    /// 外接显示器独立状态机（与主屏状态机完全物理隔离，互不抢夺与干扰）
    public let externalStateMachine = IslandStateMachine()
    
    /// 主屏状态机（复用全局单例，保持兼容）
    public var primaryStateMachine: IslandStateMachine {
        IslandStateMachine.shared
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    /// 当前焦点屏幕几何（单一可信数据源，兼容旧观测）
    @Published public private(set) var currentPanelGeometry: NotchGeometry
    
    private init() {
        let initialGeom = ScreenManager.shared.primaryGeometry
        self.currentPanelGeometry = initialGeom
        
        // 监听当前屏幕几何变更（焦点切屏）
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
            
        // 监听主屏状态机展开/收起变化
        IslandStateMachine.shared.$currentState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)
            
        // 监听外接屏独立状态机展开/收起变化 (Issue #53)
        externalStateMachine.$currentState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)
    }
    
    /// 根据显示器 ID 获取对应的独立状态机 (Issue #53)
    public func stateMachine(for displayID: CGDirectDisplayID) -> IslandStateMachine {
        let allGeoms = ScreenManager.shared.allGeometries
        if let geom = allGeoms.first(where: { $0.displayID == displayID }) {
            return geom.hasPhysicalNotch ? primaryStateMachine : externalStateMachine
        }
        let primary = ScreenManager.shared.primaryGeometry
        return displayID == primary.displayID && primary.hasPhysicalNotch ? primaryStateMachine : externalStateMachine
    }
    
    /// 根据显示器 ID 获取对应的 IslandPanel 实例 (Issue #53)
    public func panel(for displayID: CGDirectDisplayID) -> IslandPanel? {
        let allGeoms = ScreenManager.shared.allGeometries
        if let geom = allGeoms.first(where: { $0.displayID == displayID }) {
            return geom.hasPhysicalNotch ? primaryPanel : externalPanel
        }
        let primary = ScreenManager.shared.primaryGeometry
        return displayID == primary.displayID && primary.hasPhysicalNotch ? primaryPanel : externalPanel
    }
    
    /// 创建并装载绑定指定显示器与状态机的 IslandPanel 实例 (Issue #53)
    private func createPanel(for geometry: NotchGeometry, stateMachine: IslandStateMachine) -> IslandPanel {
        let viewportBounds = calculateViewportBounds(for: geometry)
        let panel = IslandPanel(contentRect: viewportBounds)
        let rootView = IslandRootView(displayID: geometry.displayID, stateMachine: stateMachine)
        let hostingView = IslandHostingView(rootView: rootView)
        
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        
        panel.contentView = hostingView
        panel.setFrame(viewportBounds, display: true)
        return panel
    }
    
    /// 计算覆盖灵动岛全展开区域的稳定透明视口区域（吸顶居中常驻，展开/收起永不改变 Frame）
    public func calculateViewportBounds(for geometry: NotchGeometry) -> CGRect {
        let viewportWidth = min(geometry.screenFrame.width * 0.85, 800.0)
        let viewportHeight: CGFloat = IslandTheme.Dimension.EXTENDED_HEIGHT
        let viewportX = geometry.screenFrame.minX + (geometry.screenFrame.width - viewportWidth) / 2.0
        let viewportY = geometry.screenFrame.maxY - viewportHeight
        return CGRect(x: viewportX, y: viewportY, width: viewportWidth, height: viewportHeight)
    }
    
    /// 初始化并挂载多屏幕灵动岛面板，启动多屏追踪
    public func start() {
        applyDisplayAndVisibilityRules()
        MouseMonitor.shared.startMonitoring()
    }
    
    /// 动态设置指定物理窗口的鼠标事件穿透性 (Issue #53)
    public func setIgnoresMouseEvents(_ ignores: Bool, for displayID: CGDirectDisplayID? = nil) {
        if let did = displayID, let targetPanel = panel(for: did) {
            if targetPanel.ignoresMouseEvents != ignores {
                targetPanel.ignoresMouseEvents = ignores
            }
        } else {
            // 未指定则同步主副屏
            if let p = primaryPanel, p.ignoresMouseEvents != ignores {
                p.ignoresMouseEvents = ignores
            }
            if let e = externalPanel, e.ignoresMouseEvents != ignores {
                e.ignoresMouseEvents = ignores
            }
        }
    }
    
    /// 综合驱动主屏面板与外接屏面板的生命周期、几何锚定与独立可见性 (Issue #53)
    public func applyDisplayAndVisibilityRules() {
        let prefs = PreferenceStore.shared.preferences
        let allGeoms = ScreenManager.shared.allGeometries
        self.currentPanelGeometry = ScreenManager.shared.currentGeometry
        
        // -------------------------------------------------------------
        // 1. MacBook 物理刘海屏主面板生命周期管理 (Primary Panel)
        // -------------------------------------------------------------
        let physicalGeom = allGeoms.first(where: { $0.hasPhysicalNotch })
        if let geom = physicalGeom {
            // 开盖正常模式：确保主面板存在并常驻守护物理刘海屏
            let targetPanel: IslandPanel
            if let existing = primaryPanel {
                targetPanel = existing
            } else {
                let created = createPanel(for: geom, stateMachine: primaryStateMachine)
                self.primaryPanel = created
                targetPanel = created
            }
            
            let viewport = calculateViewportBounds(for: geom)
            let snapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)
            let overflowCount = snapshot?.overflowCount ?? 0
            let isExpanded = primaryStateMachine.currentState.isExpanded
            let shouldHideForNoOverflow = prefs.hideWhenNoOverflow && overflowCount == 0 && !isExpanded
            let isFullScreenHidden = primaryStateMachine.currentState.isFullScreenHidden ||
                                    (geom.isFullScreenSpace && !MouseMonitor.shared.isAwakenedInFullScreen)
            
            if isFullScreenHidden || shouldHideForNoOverflow {
                targetPanel.ignoresMouseEvents = true
                updatePanelViewport(targetPanel, targetViewport: viewport, targetAlpha: 0.0, duration: 0.20)
            } else {
                targetPanel.ignoresMouseEvents = false
                targetPanel.orderFrontRegardless()
                updatePanelViewport(targetPanel, targetViewport: viewport, targetAlpha: 1.0, duration: 0.18)
            }
        } else {
            // 合盖模式 (Clamshell Mode)：无物理刘海屏，彻底隐藏/注销主面板
            primaryPanel?.orderOut(nil)
            primaryPanel = nil
        }
        
        // -------------------------------------------------------------
        // 2. 外接平直显示器副面板生命周期管理 (External Panel)
        // -------------------------------------------------------------
        let externalGeom = allGeoms.first(where: { !$0.hasPhysicalNotch && !$0.isBuiltIn })
        let allowsExternal = (prefs.externalDisplayMode != .mainScreenOnly && prefs.externalDisplayMode != .disabled)
        
        if let geom = externalGeom, allowsExternal {
            // 连接了外接平直显示器且偏好允许：确保副面板独立存在
            let targetPanel: IslandPanel
            if let existing = externalPanel {
                targetPanel = existing
            } else {
                let created = createPanel(for: geom, stateMachine: externalStateMachine)
                self.externalPanel = created
                targetPanel = created
            }
            
            let viewport = calculateViewportBounds(for: geom)
            let isExpanded = externalStateMachine.currentState.isExpanded
            let snapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)
            let overflowCount = snapshot?.overflowCount ?? 0
            let shouldHideForNoOverflow = prefs.hideWhenNoOverflow && overflowCount == 0 && !isExpanded
            let isFullScreenHidden = externalStateMachine.currentState.isFullScreenHidden ||
                                    (geom.isFullScreenSpace && !MouseMonitor.shared.isAwakenedInFullScreen)
            
            // 外接平直屏规范：折叠常态 100% 隐形 (alpha = 0.0) 且鼠标 100% 物理直通底层窗口
            if isFullScreenHidden || shouldHideForNoOverflow || !isExpanded {
                targetPanel.ignoresMouseEvents = true
                updatePanelViewport(targetPanel, targetViewport: viewport, targetAlpha: 0.0, duration: 0.20)
            } else {
                targetPanel.ignoresMouseEvents = false
                targetPanel.orderFrontRegardless()
                updatePanelViewport(targetPanel, targetViewport: viewport, targetAlpha: 1.0, duration: 0.18)
            }
        } else {
            // 未连接外接平直屏或偏好禁用外接屏：彻底隐藏并清理副面板
            externalPanel?.orderOut(nil)
            externalPanel = nil
        }
    }
    
    /// 统一驱动视口坐标迁移与透明度平滑过渡
    private func updatePanelViewport(
        _ panel: IslandPanel,
        targetViewport: CGRect,
        targetAlpha: CGFloat,
        duration: TimeInterval
    ) {
        if panel.frame != targetViewport {
            panel.setFrame(targetViewport, display: true)
        }
        if panel.alphaValue != targetAlpha {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                panel.animator().alphaValue = targetAlpha
            }
        }
    }
    
    /// 检查点击位置是否落在当前灵动岛展开交互区域外部；若在外部且展开则收起对应屏幕面板 (Ticket #48 & #53)
    public func handleOutsideClickIfNeeded(at location: CGPoint) {
        let allGeoms = ScreenManager.shared.allGeometries
        guard let geom = allGeoms.first(where: { $0.screenFrame.insetBy(dx: -2.0, dy: -2.0).contains(location) }) else {
            return
        }
        let sm = stateMachine(for: geom.displayID)
        guard sm.currentState.isExpanded else { return }
        
        let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)
        let overflowCount = targetSnapshot?.overflowCount ?? sm.activeOverflowCount
        let screenRect = geom.interactiveScreenRect(isExpanded: true, overflowCount: overflowCount)
        let paddedRect = screenRect.insetBy(dx: -4, dy: -4)
        if !NSMouseInRect(location, paddedRect, false) {
            sm.triggerCollapse()
        }
    }
}
