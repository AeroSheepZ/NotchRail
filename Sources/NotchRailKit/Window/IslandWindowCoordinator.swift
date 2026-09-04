import Foundation
import AppKit
import SwiftUI
import Combine

/// 协调 IslandPanel 窗口的创建、布局锚定与显示隐藏及跨屏动态迁移
/// 落实视口借调流转架构（Viewport Leasing）与合盖模式（Clamshell）支持：
/// 1. 常态守护：若存在物理刘海屏，单例 Panel 的物理 Frame 始终锚定在 MacBook 物理刘海屏（primaryGeometry），维持物理刘海处小胶囊与黄色耳翼常驻显示；
/// 2. 展开借调：当外接平直屏产生展开意图（isExpanded == true 且目标屏为外接屏）时，Panel 物理 Frame 原子迁移至外接屏顶部中央，并平滑淡入展开；
/// 3. 收起归位：当外接屏展开面板收起（动画结束退回未展开隐形态）后，Panel 物理 Frame 立即无感重置归位回 MacBook 物理刘海屏（primaryGeometry），无缝恢复常驻小胶囊；
/// 4. 合盖模式：若全系统所有屏幕均无物理刘海，Panel 驻留主外接屏且平时透明（alpha = 0.0，ignoresMouseEvents = true），按需就地展开。
@MainActor
public final class IslandWindowCoordinator: ObservableObject {
    public static let shared = IslandWindowCoordinator()
    
    private var panel: IslandPanel?
    private var cancellables = Set<AnyCancellable>()
    private var lastActiveDisplayID: CGDirectDisplayID?
    
    /// 当前 Panel 实际锚定的屏幕几何（单一可信数据源，驱动 IslandHostingView 与 IslandRootView）
    @Published public private(set) var currentPanelGeometry: NotchGeometry
    /// 视口当前是否处于借调给外接平直屏展开状态
    public private(set) var isLeasedToExternal: Bool = false
    /// 外接屏收起后归位到物理刘海屏的延迟工作项
    private var returnToPrimaryWorkItem: DispatchWorkItem?
    
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
        
        let allGeoms = ScreenManager.shared.allGeometries
        let hasAnyPhysicalNotch = allGeoms.contains(where: { $0.hasPhysicalNotch })
        let prefs = PreferenceStore.shared.preferences
        let geometry = hasAnyPhysicalNotch ? ScreenManager.shared.primaryGeometry : ScreenManager.shared.effectiveGeometry(for: prefs.externalDisplayMode)
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
    
    /// 综合应用视口借调流转架构、多显示器策略与合盖模式
    public func applyDisplayAndVisibilityRules() {
        guard let panel = self.panel else { return }
        
        let prefs = PreferenceStore.shared.preferences
        let allGeoms = ScreenManager.shared.allGeometries
        let hasAnyPhysicalNotch = allGeoms.contains(where: { $0.hasPhysicalNotch })
        let primaryGeom = ScreenManager.shared.primaryGeometry
        let currentGeom = ScreenManager.shared.currentGeometry
        let isExpanded = IslandStateMachine.shared.currentState.isExpanded
        
        // =========================================================================
        // 分支 1: 合盖模式（Clamshell 无刘海屏场景）：全系统所有屏幕均无物理刘海
        // Panel 驻留主外接屏且平时透明（alpha = 0.0，ignoresMouseEvents = true），按需就地展开
        // =========================================================================
        if !hasAnyPhysicalNotch {
            returnToPrimaryWorkItem?.cancel()
            returnToPrimaryWorkItem = nil
            isLeasedToExternal = false
            
            if prefs.externalDisplayMode == .disabled {
                panel.ignoresMouseEvents = true
                panel.alphaValue = 0.0
                return
            }
            
            let targetGeom = ScreenManager.shared.effectiveGeometry(for: prefs.externalDisplayMode)
            let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: targetGeom.displayID)
            let overflowCount = targetSnapshot?.overflowCount ?? 0
            let hasNoOverflow = overflowCount == 0
            let shouldHideForNoOverflow = prefs.hideWhenNoOverflow && hasNoOverflow && !isExpanded
            let isFullScreenHidden = IslandStateMachine.shared.currentState.isFullScreenHidden ||
                                    (targetGeom.isFullScreenSpace && !MouseMonitor.shared.isAwakenedInFullScreen)
            let targetViewport = calculateViewportBounds(for: targetGeom)
            
            self.currentPanelGeometry = targetGeom
            self.lastActiveDisplayID = targetGeom.displayID
            
            if !isExpanded || isFullScreenHidden || shouldHideForNoOverflow {
                panel.ignoresMouseEvents = true
                updatePanelViewport(panel, targetViewport: targetViewport, targetAlpha: 0.0, duration: 0.20, immediate: false)
            } else {
                panel.ignoresMouseEvents = false
                panel.orderFrontRegardless()
                updatePanelViewport(panel, targetViewport: targetViewport, targetAlpha: 1.0, duration: 0.18, immediate: false)
            }
            return
        }
        
        // =========================================================================
        // 分支 2: 存在物理刘海屏（MacBook 打开状态，单屏或多屏）：视口借调流转架构
        // =========================================================================
        
        var shouldHideForExternal = false
        switch prefs.externalDisplayMode {
        case .followFocusedScreen:
            shouldHideForExternal = false
        case .mainScreenOnly:
            shouldHideForExternal = false
        case .disabled:
            shouldHideForExternal = !currentGeom.hasPhysicalNotch && !currentGeom.isBuiltIn
        }
        
        // A. 展开借调：当外接平直屏产生展开意图（isExpanded == true 且目标屏为外接屏且偏好允许）
        let canLeaseToExternal = (prefs.externalDisplayMode == .followFocusedScreen) && !currentGeom.hasPhysicalNotch && !shouldHideForExternal
        
        if isExpanded && canLeaseToExternal {
            // 取消正在等待的归位定时器
            returnToPrimaryWorkItem?.cancel()
            returnToPrimaryWorkItem = nil
            
            let isNewlyLeased = !isLeasedToExternal || (currentPanelGeometry.displayID != currentGeom.displayID)
            self.isLeasedToExternal = true
            self.currentPanelGeometry = currentGeom
            self.lastActiveDisplayID = currentGeom.displayID
            
            let targetViewport = calculateViewportBounds(for: currentGeom)
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            // 原子迁移至外接屏顶部中央，并平滑淡入展开
            updatePanelViewport(panel, targetViewport: targetViewport, targetAlpha: 1.0, duration: 0.18, immediate: false, preZeroAlpha: isNewlyLeased)
            return
        }
        
        // B. 收起归位：当外接屏展开面板收起（动画结束退回未展开隐形态）后，Panel 物理 Frame 立即无感重置归位回 MacBook 物理刘海屏
        if isLeasedToExternal && !isExpanded {
            // 外接平直屏面板先就地平滑淡出至完全隐形
            panel.ignoresMouseEvents = true
            let externalViewport = calculateViewportBounds(for: currentPanelGeometry)
            updatePanelViewport(panel, targetViewport: externalViewport, targetAlpha: 0.0, duration: 0.20, immediate: false)
            
            // 启动归位定时器，等待外接屏退回隐形态动画结束（0.22s），立即无感归位回 primaryGeometry
            if returnToPrimaryWorkItem == nil {
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, let panel = self.panel else { return }
                    self.returnToPrimaryWorkItem = nil
                    guard !IslandStateMachine.shared.currentState.isExpanded else { return }
                    self.isLeasedToExternal = false
                    
                    let primaryViewport = self.calculateViewportBounds(for: primaryGeom)
                    panel.alphaValue = 0.0
                    panel.setFrame(primaryViewport, display: true)
                    self.currentPanelGeometry = primaryGeom
                    self.lastActiveDisplayID = primaryGeom.displayID
                    
                    // 归位后恢复 MacBook 物理刘海常驻小胶囊
                    self.applyDisplayAndVisibilityRules()
                }
                self.returnToPrimaryWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
            }
            return
        }
        
        // C. 常态（未借调）：单例 Panel 的物理 Frame 始终锚定在 MacBook 物理刘海屏（primaryGeometry），维持常驻小胶囊
        returnToPrimaryWorkItem?.cancel()
        returnToPrimaryWorkItem = nil
        self.isLeasedToExternal = false
        
        let targetGeom = primaryGeom
        self.currentPanelGeometry = targetGeom
        
        let isScreenSwitching = (lastActiveDisplayID != nil && lastActiveDisplayID != targetGeom.displayID)
        self.lastActiveDisplayID = targetGeom.displayID
        
        // 检查刘海屏全屏与快照
        let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: targetGeom.displayID)
        let overflowCount = targetSnapshot?.overflowCount ?? 0
        let hasNoOverflow = overflowCount == 0
        
        // 切屏或处于未唤醒全屏空间时，原子重置展开态
        if isScreenSwitching || (targetGeom.isFullScreenSpace && !MouseMonitor.shared.isAwakenedInFullScreen) {
            if IslandStateMachine.shared.currentState.isExpanded {
                IslandStateMachine.shared.triggerCollapse()
            }
        }
        
        if !targetGeom.isFullScreenSpace && IslandStateMachine.shared.currentState.isFullScreenHidden {
            IslandStateMachine.shared.awakenFromFullScreen()
        }
        
        let shouldHideForNoOverflow = prefs.hideWhenNoOverflow && hasNoOverflow && !isExpanded
        let isFullScreenHidden = IslandStateMachine.shared.currentState.isFullScreenHidden ||
                                (targetGeom.isFullScreenSpace && !MouseMonitor.shared.isAwakenedInFullScreen)
        
        let targetViewport = calculateViewportBounds(for: targetGeom)
        
        if isFullScreenHidden || shouldHideForNoOverflow {
            panel.ignoresMouseEvents = true
            updatePanelViewport(panel, targetViewport: targetViewport, targetAlpha: 0.0, duration: 0.20, immediate: isScreenSwitching)
        } else {
            if isExpanded {
                panel.ignoresMouseEvents = false
            }
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
