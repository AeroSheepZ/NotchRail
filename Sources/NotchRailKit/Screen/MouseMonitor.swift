import Foundation
import AppKit
import CoreGraphics
import Combine

/// 全局前台焦点与点击跨屏监听器
/// 基于真实点击与应用前台激活驱动跨屏迁移，杜绝随鼠标划过乱跳
@MainActor
public final class MouseMonitor: ObservableObject {
    public static let shared = MouseMonitor()
    
    @Published public private(set) var isAwakenedInFullScreen: Bool = false
    
    private var globalMouseDownMonitor: Any?
    private var localMouseDownMonitor: Any?
    private var globalMouseMovedMonitor: Any?
    private var isMonitoring: Bool = false
    private var fullScreenGraceTimer: Timer?
    private var externalDwellTimer: Timer?
    private var lastMouseLocation: CGPoint?
    private var lastMouseTimestamp: TimeInterval?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    /// 取消外接屏 120ms 停留意图防抖定时器
    private func cancelExternalDwellTimer() {
        externalDwellTimer?.invalidate()
        externalDwellTimer = nil
    }
    
    /// 判定光标是否位于外接平直屏的目标中央热区（消除重复代码）
    private func isPointInExternalTopZone(_ point: CGPoint, geometry: NotchGeometry) -> Bool {
        if geometry.isFullScreenSpace {
            // 全屏空间协同唤醒：优先让位原生全屏菜单栏，仅在菜单栏中央 240pt 区域产生悬停意图才触发 (Ticket #45)
            return geometry.isPointInExternalFullScreenCenterBar(point, horizontalSpan: 240.0)
        } else {
            // 普通桌面空间：中央 240pt 受限碰顶热区 (midX \pm 120pt, maxY - 4 ... maxY) (Ticket #44)
            return geometry.isPointInExternalCenterHotZone(point, horizontalSpan: 240.0, verticalThreshold: 4.0)
        }
    }
    
    /// 启动全局多屏焦点与点击追踪及透明区域动态穿透
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp]
        
        // 1. 全局鼠标点击与释放监听（捕获用户在任意屏幕上的激活点击）
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] _ in
            Task { @MainActor in
                self?.handleClick(at: NSEvent.mouseLocation)
            }
        }
        
        // 2. 局部鼠标点击与移动监听（用户在自身灵动岛或窗口内点击/移动）
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .mouseMoved]) { [weak self] event in
            Task { @MainActor in
                if event.type == .mouseMoved {
                    self?.handleMouseMove(at: NSEvent.mouseLocation)
                } else {
                    self?.handleClick(at: NSEvent.mouseLocation)
                }
            }
            return event
        }
        
        // 3. 全局鼠标移动监听（驱动非灵动岛透明区域 100% 硬件穿透，绝不遮挡底层应用）
        globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMove(at: NSEvent.mouseLocation)
            }
        }
        
        // 4. 监听前台活动应用程序切换通知（Key Window 屏幕变化，排除自身获焦）
        let ownPID = ProcessInfo.processInfo.processIdentifier
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notif in
                if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier == ownPID {
                    return
                }
                self?.syncActiveScreen()
            }
            .store(in: &cancellables)
        
        // 5. 监听活动空间/桌面切换通知（多屏 Space 切换第一响应通知）
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.syncActiveScreen()
            }
            .store(in: &cancellables)
    }
    
    /// 停止监听
    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        
        fullScreenGraceTimer?.invalidate()
        fullScreenGraceTimer = nil
        cancelExternalDwellTimer()
        
        if let globalClick = globalMouseDownMonitor {
            NSEvent.removeMonitor(globalClick)
            globalMouseDownMonitor = nil
        }
        if let localClick = localMouseDownMonitor {
            NSEvent.removeMonitor(localClick)
            localMouseDownMonitor = nil
        }
        if let globalMoved = globalMouseMovedMonitor {
            NSEvent.removeMonitor(globalMoved)
            globalMouseMovedMonitor = nil
        }
        cancellables.removeAll()
    }
    
    /// 处理鼠标移动：全屏顶边缘唤醒 + 外接平直屏中央 240pt 热区 120ms 防抖 + 硬件级穿透判定
    func handleMouseMove(at location: CGPoint) {
        let prefs = PreferenceStore.shared.preferences
        let geom = ScreenManager.shared.effectiveGeometry(for: prefs.externalDisplayMode)
        
        // 仅当鼠标位于当前灵动岛所在的屏幕物理区域时进行判定，绝不随鼠标移动乱切屏
        guard NSMouseInRect(location, geom.screenFrame, false) else {
            cancelExternalDwellTimer()
            return
        }
        
        let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)
        let overflowCount = targetSnapshot?.overflowCount ?? 0
        let isExpanded = IslandStateMachine.shared.currentState.isExpanded
        
        // -------------------------------------------------------------
        // 分流 A: 内建物理刘海屏 (geom.hasPhysicalNotch == true)
        // -------------------------------------------------------------
        if geom.hasPhysicalNotch {
            cancelExternalDwellTimer()
            
            // 1. 全屏沉浸协同：检测当前屏幕是否处于全屏空间
            if geom.isFullScreenSpace {
                // 0 溢出防护：若用户启用了「无溢出时自动隐藏」且当前屏 0 溢出，全屏碰顶绝不误唤醒空胶囊 (Spec L37)
                let shouldSuppressAwakening = prefs.hideWhenNoOverflow && overflowCount == 0
                let isTouchingTopEdge = !shouldSuppressAwakening && geom.isPointInTopEdgeHotZone(location, threshold: 2.0)
                
                if isTouchingTopEdge {
                    fullScreenGraceTimer?.invalidate()
                    fullScreenGraceTimer = nil
                    if !isAwakenedInFullScreen {
                        isAwakenedInFullScreen = true
                        IslandStateMachine.shared.awakenFromFullScreen()
                        IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
                    }
                } else if isAwakenedInFullScreen {
                    let screenRect = geom.interactiveScreenRect(isExpanded: isExpanded, overflowCount: overflowCount)
                    
                    // 宽限判定：在灵动岛交互区（外扩 16pt）或紧贴灵动岛正上方顶边缘 10pt 内 (Spec L23)
                    let islandTopZone = CGRect(
                        x: screenRect.minX - 16.0,
                        y: geom.screenFrame.maxY - 10.0,
                        width: screenRect.width + 32.0,
                        height: 10.0
                    )
                    let isWithinInteractiveZone = NSMouseInRect(location, screenRect.insetBy(dx: -16, dy: -16), false) ||
                                                  NSMouseInRect(location, islandTopZone, false)
                    
                    if isWithinInteractiveZone {
                        fullScreenGraceTimer?.invalidate()
                        fullScreenGraceTimer = nil
                    } else if fullScreenGraceTimer == nil {
                        let delay = max(0.1, prefs.collapseDelayMs / 1000.0)
                        fullScreenGraceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                            Task { @MainActor in
                                guard let self = self else { return }
                                self.isAwakenedInFullScreen = false
                                self.fullScreenGraceTimer = nil
                                IslandStateMachine.shared.enterFullScreenHidden()
                                IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
                            }
                        }
                    }
                }
            } else {
                // 普通桌面空间，清理全屏唤醒态与计时器
                if isAwakenedInFullScreen {
                    isAwakenedInFullScreen = false
                    fullScreenGraceTimer?.invalidate()
                    fullScreenGraceTimer = nil
                    if IslandStateMachine.shared.currentState.isFullScreenHidden {
                        IslandStateMachine.shared.triggerCollapse()
                    }
                }
            }
            
            if isExpanded {
                IslandWindowCoordinator.shared.setIgnoresMouseEvents(false)
                return
            }
            
            let hasNoOverflow = overflowCount == 0
            if (prefs.hideWhenNoOverflow && hasNoOverflow) || (geom.isFullScreenSpace && !isAwakenedInFullScreen) {
                IslandWindowCoordinator.shared.setIgnoresMouseEvents(true)
                return
            }
            
            let screenRect = geom.interactiveScreenRect(isExpanded: false, overflowCount: overflowCount)
            // 允许外扩 4pt 交互过渡冗余
            let paddedRect = screenRect.insetBy(dx: -4, dy: -4)
            let isInside = NSMouseInRect(location, paddedRect, false)
            
            IslandWindowCoordinator.shared.setIgnoresMouseEvents(!isInside)
            return
        }
        
        // -------------------------------------------------------------
        // 分流 B: 外接平直显示器 (!geom.hasPhysicalNotch)
        // -------------------------------------------------------------
        
        // 1. 0 溢出硬门禁：当 overflowCount == 0 时，中央碰顶热区完全静默，100% 物理直通底层应用 (Ticket #44)
        if overflowCount == 0 {
            cancelExternalDwellTimer()
            if isAwakenedInFullScreen {
                isAwakenedInFullScreen = false
                fullScreenGraceTimer?.invalidate()
                fullScreenGraceTimer = nil
            }
            if isExpanded {
                IslandStateMachine.shared.triggerCollapse()
            }
            IslandWindowCoordinator.shared.setIgnoresMouseEvents(true)
            return
        }
        
        // 2. 已展开态：根据光标是否在展开托轨内控制穿透与收起
        if isExpanded {
            cancelExternalDwellTimer()
            
            let screenRect = geom.dynamicExtendedBounds(for: overflowCount)
            let interactiveRect = CGRect(
                x: screenRect.minX - 12.0,
                y: screenRect.minY - 12.0,
                width: screenRect.width + 24.0,
                height: screenRect.height + 17.0
            )
            let isInside = NSMouseInRect(location, interactiveRect, false)
            
            if isInside {
                IslandWindowCoordinator.shared.setIgnoresMouseEvents(false)
                fullScreenGraceTimer?.invalidate()
                fullScreenGraceTimer = nil
            } else {
                // 移出展开区域
                if geom.isFullScreenSpace {
                    if fullScreenGraceTimer == nil {
                        let delay = max(0.1, prefs.collapseDelayMs / 1000.0)
                        fullScreenGraceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                            Task { @MainActor in
                                guard let self = self else { return }
                                self.isAwakenedInFullScreen = false
                                self.fullScreenGraceTimer = nil
                                IslandStateMachine.shared.triggerCollapse()
                                IslandStateMachine.shared.enterFullScreenHidden()
                                IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
                                IslandWindowCoordinator.shared.setIgnoresMouseEvents(true)
                            }
                        }
                    }
                } else {
                    if prefs.triggerMode != .click {
                        IslandStateMachine.shared.handleMouseLeave()
                    }
                }
            }
            return
        }
        
        // 3. 平直屏常态未展开时，鼠标事件严格穿透底层窗口 (Ticket #44 第 2 点)
        IslandWindowCoordinator.shared.setIgnoresMouseEvents(true)
        
        // 4. 判定当前光标是否处于外接屏目标中央热区（复用统一判定函数）
        let isInTargetHotZone = isPointInExternalTopZone(location, geometry: geom)
        
        // 显式校验高速纵向穿越速度 (SPEC Decision 4: > 300pt/s 纵向穿透时取消定时器，杜绝误触)
        let now = Date().timeIntervalSinceReferenceDate
        var isHighVelocityPass = false
        if let lastLoc = lastMouseLocation, let lastTime = lastMouseTimestamp {
            let dt = now - lastTime
            if dt > 0.001 && dt < 0.25 {
                let dy = abs(location.y - lastLoc.y)
                let speedY = dy / CGFloat(dt)
                if speedY > 300.0 {
                    isHighVelocityPass = true
                }
            }
        }
        self.lastMouseLocation = location
        self.lastMouseTimestamp = now
        
        // 5. 120ms 停留意图防抖门禁
        if isInTargetHotZone && !isHighVelocityPass {
            if externalDwellTimer == nil {
                externalDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.externalDwellTimer = nil
                        
                        let currentGeom = ScreenManager.shared.effectiveGeometry(for: PreferenceStore.shared.preferences.externalDisplayMode)
                        guard currentGeom.displayID == geom.displayID,
                              !currentGeom.hasPhysicalNotch,
                              !IslandStateMachine.shared.currentState.isExpanded else { return }
                        
                        let currentSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: currentGeom.displayID)
                        let currentOverflow = currentSnapshot?.overflowCount ?? 0
                        guard currentOverflow > 0 else { return }
                        
                        let mousePos = NSEvent.mouseLocation
                        let stillInZone = self.isPointInExternalTopZone(mousePos, geometry: currentGeom)
                        guard stillInZone else { return }
                        
                        // 停留意图确立：驱动状态机触发展开并更新窗口穿透
                        if currentGeom.isFullScreenSpace {
                            self.isAwakenedInFullScreen = true
                        }
                        IslandStateMachine.shared.triggerExpand(overflowCount: currentOverflow)
                        IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
                        IslandWindowCoordinator.shared.setIgnoresMouseEvents(false)
                    }
                }
            }
        } else {
            // 光标移出热区或高速穿透（> 300pt/s），立即取消定时器，杜绝误触 (Ticket #44 & SPEC Decision 4)
            cancelExternalDwellTimer()
        }
    }
    
    /// 处理用户在特定屏幕上的点击激活（与 ScreenManager 单一可信源直连，零缓存阻断）
    func handleClick(at location: CGPoint) {
        // 1. 若当前灵动岛处于展开态，委托视口管理器判定并驱动收起外部点击 (Ticket #48, 消除 Feature Envy)
        IslandWindowCoordinator.shared.handleOutsideClickIfNeeded(at: location)
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        let currentDisplayID = ScreenManager.shared.currentGeometry.displayID
        
        for screen in screens {
            if NSMouseInRect(location, screen.frame, false) {
                if screen.displayID != currentDisplayID {
                    ScreenManager.shared.updateActiveFocusScreen(to: screen)
                }
                break
            }
        }
    }
    
    /// 同步前台活动屏幕（响应应用激活或 Space 切换）
    private func syncActiveScreen() {
        fullScreenGraceTimer?.invalidate()
        fullScreenGraceTimer = nil
        cancelExternalDwellTimer()
        isAwakenedInFullScreen = false
        
        if let mainScreen = NSScreen.main {
            let currentDisplayID = ScreenManager.shared.currentGeometry.displayID
            if mainScreen.displayID != currentDisplayID {
                ScreenManager.shared.updateActiveFocusScreen(to: mainScreen)
            }
        }
        IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
    }
    
    /// 测试与诊断辅助：模拟鼠标移动判定
    public func simulateMouseMove(at location: CGPoint) {
        handleMouseMove(at: location)
    }
    
    /// 测试与诊断辅助：模拟鼠标点击判定 (Ticket #48)
    public func simulateClick(at location: CGPoint) {
        handleClick(at: location)
    }
    
    /// 测试与诊断辅助：检查外接屏 120ms 防抖定时器是否正在运行
    public var isExternalDwellTimerActive: Bool {
        return externalDwellTimer != nil
    }
}
