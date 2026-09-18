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
    
    /// 在全屏空间中显式标记唤醒态
    public func awakenInFullScreen() {
        self.isAwakenedInFullScreen = true
    }
    
    /// 重置全屏唤醒状态与计时器（供快捷键收起时复原全屏隐退）
    public func resetFullScreenAwakening() {
        self.isAwakenedInFullScreen = false
        self.fullScreenGraceTimer?.invalidate()
        self.fullScreenGraceTimer = nil
    }
    
    private var globalMouseDownMonitor: Any?
    private var localMouseDownMonitor: Any?
    private var globalMouseMovedMonitor: Any?
    private var isMonitoring: Bool = false
    private var fullScreenGraceTimer: Timer?
    private var externalDwellTimer: Timer?
    private var lastMouseLocation: CGPoint?
    private var lastMouseTimestamp: TimeInterval?
    private var cancellables = Set<AnyCancellable>()
    
    /// 鼠标移动节流间隔（防抖高刷鼠标事件，消除无节制 Task 堆分配，Issue #51）
    private static let MOVE_THROTTLE_SECONDS: TimeInterval = 0.016
    /// 向下高速穿透判定速度阈值（pt/s）：仅向下高速穿越时才取消外接屏停留定时器，杜绝自上向下跨屏误触 (SPEC Decision 4)
    private static let DOWNWARD_CROSS_SPEED_THRESHOLD: CGFloat = 300.0
    
    /// 鼠标移动节流时间戳（防抖高刷鼠标事件，消除无节制 Task 堆分配，Issue #51）
    private nonisolated(unsafe) static var lastGlobalMoveUptime: TimeInterval = 0
    private var lastLocalMoveUptime: TimeInterval = 0
    
    private init() {}
    
    /// 取消外接屏 120ms 停留意图防抖定时器
    private func cancelExternalDwellTimer() {
        externalDwellTimer?.invalidate()
        externalDwellTimer = nil
    }
    
    /// 判定光标是否位于外接平直屏的展开触发区（普通桌面中央受限热区 / 全屏空间菜单栏协同区）
    private func isPointInExternalTriggerZone(_ point: CGPoint, geometry: NotchGeometry) -> Bool {
        if geometry.isFullScreenSpace {
            // 全屏空间协同唤醒：优先让位原生全屏菜单栏，仅在菜单栏中央受限区产生悬停意图才触发 (Ticket #45)
            return geometry.isPointInExternalFullScreenCenterBar(point)
        } else {
            // 普通桌面空间：中央受限碰顶热区 (Ticket #44)
            // 水平跨度与垂直阈值均不显式传入，统一由 NotchGeometry 默认契约治理，杜绝测试与生产语义漂移
            return geometry.isPointInExternalCenterHotZone(point)
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
        
        // 2. 局部鼠标点击与移动监听（主线程 RunLoop 同步直调，MOVE_THROTTLE_SECONDS 节流，消除 Task 堆分配）
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .mouseMoved]) { [weak self] event in
            guard let self = self else { return event }
            if event.type == .mouseMoved {
                let now = ProcessInfo.processInfo.systemUptime
                if now - self.lastLocalMoveUptime >= Self.MOVE_THROTTLE_SECONDS {
                    self.lastLocalMoveUptime = now
                    self.handleMouseMove(at: NSEvent.mouseLocation)
                }
            } else {
                self.handleClick(at: NSEvent.mouseLocation)
            }
            return event
        }
        
        // 3. 全局鼠标移动监听（16ms 节流限制，超频事件在闭包层直接丢弃，彻底消除微任务堆分配）
        globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            let now = ProcessInfo.processInfo.systemUptime
            if now - Self.lastGlobalMoveUptime < Self.MOVE_THROTTLE_SECONDS {
                return
            }
            Self.lastGlobalMoveUptime = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handleMouseMove(at: location)
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
        Self.lastGlobalMoveUptime = 0
        lastLocalMoveUptime = 0
        cancellables.removeAll()
    }
    
    /// 处理鼠标移动：全屏顶边缘唤醒 + 外接平直屏中央 240pt 热区 120ms 防抖 + 硬件级穿透判定
    func handleMouseMove(at location: CGPoint) {
        let prefs = PreferenceStore.shared.preferences
        // 动态解析光标当前所在的物理显示器几何（带 2pt 屏幕外沿容差，确保碰顶热区光标不被丢弃，AGENTS.md 2.1）
        let screenMatch = ScreenManager.shared.allGeometries.first(where: {
            $0.screenFrame.insetBy(dx: -2.0, dy: -2.0).contains(location)
        })
        guard let geom = screenMatch ?? ScreenManager.shared.geometry(for: ScreenManager.shared.effectiveGeometry(for: prefs.externalDisplayMode).displayID) else {
            cancelExternalDwellTimer()
            return
        }
        
        let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)
        let overflowCount = targetSnapshot?.overflowCount ?? 0
        guard let sm = IslandWindowCoordinator.shared.stateMachine(for: geom.displayID) else {
            cancelExternalDwellTimer()
            return
        }
        let isExpanded = sm.currentState.isExpanded
        
        // 单前台活动屏独占门禁：非活动屏处于待命锁定，绝不响应悬停或碰顶触发展开 (ADR 0017)
        let activeDisplayID = ScreenManager.shared.currentGeometry.displayID
        let isActiveScreen = (geom.displayID == activeDisplayID)
        if !isActiveScreen && !isExpanded {
            cancelExternalDwellTimer()
            return
        }
        
        // 快速熔断与触顶预热调度 (Issue #51)
        if !isExpanded && !isAwakenedInFullScreen {
            let topZoneThreshold = geom.screenFrame.maxY - (geom.statusBarHeight + 60.0)
            if location.y < topZoneThreshold {
                // 光标处于屏幕中下部工作区，直接熔断退出，撤销预热警戒态，避免后续碰撞与几何运算
                cancelExternalDwellTimer()
                MenuBarSyncCoordinator.shared.disarmPrewarm()
                return
            }
            
            // 光标自下而上接近状态栏/刘海顶部热区，唤醒单次增量预热
            MenuBarSyncCoordinator.shared.armPrewarm()
        }
        
        // -------------------------------------------------------------
        // 分流 A: 内建物理刘海屏 (geom.hasPhysicalNotch == true)
        // -------------------------------------------------------------
        if geom.hasPhysicalNotch {
            cancelExternalDwellTimer()
            
            // 1. 全屏沉浸协同：检测当前屏幕是否处于全屏空间
            if geom.isFullScreenSpace {
                // 0 溢出防护：若用户启用了「无溢出时自动隐藏」且当前屏 0 溢出，全屏碰顶绝不误唤醒空胶囊 (Spec L37)
                let shouldSuppressAwakening = prefs.hideWhenNoOverflow && overflowCount == 0
                let isTouchingTopEdge = !shouldSuppressAwakening && geom.isPointInTopEdgeHotZone(location)
                
                if isTouchingTopEdge {
                    fullScreenGraceTimer?.invalidate()
                    fullScreenGraceTimer = nil
                    if !isAwakenedInFullScreen {
                        isAwakenedInFullScreen = true
                        sm.awakenFromFullScreen()
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
                                sm.enterFullScreenHidden()
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
                    if sm.currentState.isFullScreenHidden {
                        sm.triggerCollapse()
                    }
                }
            }
            
            // 2. 已展开态：根据光标是否在展开区域内控制穿透与离开收起
            if isExpanded {
                let screenRect = geom.dynamicExtendedBounds(for: overflowCount)
                let interactiveRect = CGRect(
                    x: screenRect.minX - 12.0,
                    y: screenRect.minY - 12.0,
                    width: screenRect.width + 24.0,
                    height: screenRect.height + 17.0
                )
                let isInside = NSMouseInRect(location, interactiveRect, false)
                
                if isInside {
                    IslandWindowCoordinator.shared.setIgnoresMouseEvents(false, for: geom.displayID)
                    fullScreenGraceTimer?.invalidate()
                    fullScreenGraceTimer = nil
                } else {
                    if geom.isFullScreenSpace {
                        if fullScreenGraceTimer == nil {
                            let delay = max(0.1, prefs.collapseDelayMs / 1000.0)
                            fullScreenGraceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                                Task { @MainActor in
                                    guard let self = self else { return }
                                    self.isAwakenedInFullScreen = false
                                    self.fullScreenGraceTimer = nil
                                    sm.triggerCollapse()
                                    sm.enterFullScreenHidden()
                                    IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
                                    IslandWindowCoordinator.shared.setIgnoresMouseEvents(true, for: geom.displayID)
                                }
                            }
                        }
                    } else {
                        // 模式门禁不在本处判定：`.click` 下「移出不自动收起」由
                        // `IslandStateMachine.handleMouseLeave` 自行早退（唯一裁决入口，
                        // 避免同一枚举在多处各写一遍口径，ADR 0016）
                        sm.handleMouseLeave()
                    }
                }
                return
            }
            
            let hasNoOverflow = overflowCount == 0
            if (prefs.hideWhenNoOverflow && hasNoOverflow) || (geom.isFullScreenSpace && !isAwakenedInFullScreen) {
                IslandWindowCoordinator.shared.setIgnoresMouseEvents(true, for: geom.displayID)
                return
            }
            
            let screenRect = geom.interactiveScreenRect(isExpanded: false, overflowCount: overflowCount)
            // 允许外扩 4pt 交互过渡冗余
            let paddedRect = screenRect.insetBy(dx: -4, dy: -4)
            let isInside = NSMouseInRect(location, paddedRect, false)
            
            IslandWindowCoordinator.shared.setIgnoresMouseEvents(!isInside, for: geom.displayID)
            return
        }
        
        // -------------------------------------------------------------
        // 分流 B: 外接平直显示器 (!geom.hasPhysicalNotch)
        // -------------------------------------------------------------
        
        // 1. 无溢出隐藏判定：仅当用户开启「无溢出时自动隐藏」且 overflowCount == 0 时，中央碰顶热区才完全静默 (对齐用户偏好)
        if prefs.hideWhenNoOverflow && overflowCount == 0 {
            cancelExternalDwellTimer()
            if isAwakenedInFullScreen {
                isAwakenedInFullScreen = false
                fullScreenGraceTimer?.invalidate()
                fullScreenGraceTimer = nil
            }
            if isExpanded {
                sm.triggerCollapse()
            }
            IslandWindowCoordinator.shared.setIgnoresMouseEvents(true, for: geom.displayID)
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
                IslandWindowCoordinator.shared.setIgnoresMouseEvents(false, for: geom.displayID)
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
                                sm.triggerCollapse()
                                sm.enterFullScreenHidden()
                                IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
                                IslandWindowCoordinator.shared.setIgnoresMouseEvents(true, for: geom.displayID)
                            }
                        }
                    }
                } else {
                    // 同分流 A：模式门禁唯一归属 `IslandStateMachine.handleMouseLeave`
                    sm.handleMouseLeave()
                }
            }
            return
        }
        
        // 3. 平直屏常态未展开时，鼠标事件严格穿透底层窗口 (Ticket #44 第 2 点 & #53)
        IslandWindowCoordinator.shared.setIgnoresMouseEvents(true, for: geom.displayID)
        
        // 4. 判定当前光标是否处于外接屏目标中央热区（复用统一判定函数）
        let isInTargetHotZone = isPointInExternalTriggerZone(location, geometry: geom)
        
        // 显式校验高速纵向穿越速度 (SPEC Decision 4: 仅向下高速穿透超过 DOWNWARD_CROSS_SPEED_THRESHOLD 时取消定时器，杜绝自上向下跨屏误触)
        let now = Date().timeIntervalSinceReferenceDate
        var isHighVelocityPass = false
        if let lastLoc = lastMouseLocation, let lastTime = lastMouseTimestamp {
            let dt = now - lastTime
            if dt > 0.001 && dt < 0.25 {
                let isDownward = (location.y - lastLoc.y) < -5.0
                let speedY = abs(location.y - lastLoc.y) / CGFloat(dt)
                if isDownward && speedY > Self.DOWNWARD_CROSS_SPEED_THRESHOLD {
                    isHighVelocityPass = true
                }
            }
        }
        self.lastMouseLocation = location
        self.lastMouseTimestamp = now
        
        // 5. 停留意图防抖门禁（对齐 triggerMode 与 hoverExpandDuration）
        // 悬停门禁唯一判据，详见 `TriggerMode.respondsToHover`；「仅点击」档留给 handleClick
        let allowsHoverTrigger = prefs.triggerMode.respondsToHover
        let dwellDuration = max(0.08, prefs.hoverExpandDuration)
        
        if isInTargetHotZone && !isHighVelocityPass && allowsHoverTrigger {
            if externalDwellTimer == nil {
                externalDwellTimer = Timer.scheduledTimer(withTimeInterval: dwellDuration, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.externalDwellTimer = nil
                        
                        let currentGeom = ScreenManager.shared.geometry(for: geom.displayID) ?? geom
                        guard let targetSM = IslandWindowCoordinator.shared.stateMachine(for: currentGeom.displayID),
                              !currentGeom.hasPhysicalNotch,
                              !targetSM.currentState.isExpanded else { return }
                        
                        let currentSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: currentGeom.displayID)
                        let currentOverflow = currentSnapshot?.overflowCount ?? 0
                        if prefs.hideWhenNoOverflow && currentOverflow == 0 { return }
                        
                        let mousePos = NSEvent.mouseLocation
                        let stillInZone = self.isPointInExternalTriggerZone(mousePos, geometry: currentGeom)
                        guard stillInZone else { return }
                        
                        // 停留意图确立：驱动外接屏独立状态机展开并刷新视口
                        if currentGeom.isFullScreenSpace {
                            self.isAwakenedInFullScreen = true
                        }
                        targetSM.triggerExpand(overflowCount: currentOverflow)
                        IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
                        IslandWindowCoordinator.shared.setIgnoresMouseEvents(false, for: currentGeom.displayID)
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
        // 1. 若当前灵动岛处于展开态，委托视口管理器判定并驱动收起外部点击 (Ticket #48 & #53)
        IslandWindowCoordinator.shared.handleOutsideClickIfNeeded(at: location)
        
        // 2. 落在外接平直屏顶部中央热区：统一委托状态机唯一入口 handleCapsuleTap 处理（ADR 0016 契约）
        let screenMatch = ScreenManager.shared.allGeometries.first(where: {
            $0.screenFrame.insetBy(dx: -2.0, dy: -2.0).contains(location)
        })
        if let geom = screenMatch {
            if !geom.hasPhysicalNotch {
                guard let extSM = IslandWindowCoordinator.shared.stateMachine(for: geom.displayID) else { return }
                if isPointInExternalTriggerZone(location, geometry: geom) {
                    let count = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)?.overflowCount ?? 0
                    FocusHandoff.shared.handoffFocus(to: geom.displayID)
                    if geom.isFullScreenSpace {
                        self.isAwakenedInFullScreen = true
                    }
                    extSM.handleCapsuleTap(overflowCount: count)
                    IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
                    IslandWindowCoordinator.shared.setIgnoresMouseEvents(false, for: geom.displayID)
                    return
                }
            } else if geom.isFullScreenSpace {
                let isTouchingTopEdge = geom.isPointInTopEdgeHotZone(location)
                if isTouchingTopEdge {
                    guard let sm = IslandWindowCoordinator.shared.stateMachine(for: geom.displayID) else { return }
                    FocusHandoff.shared.handoffFocus(to: geom.displayID)
                    if !isAwakenedInFullScreen {
                        isAwakenedInFullScreen = true
                        sm.awakenFromFullScreen()
                        IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
                    }
                }
            }
        }
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        let currentDisplayID = ScreenManager.shared.currentGeometry.displayID
        
        for screen in screens {
            if NSMouseInRect(location, screen.frame, false) {
                if screen.displayID != currentDisplayID {
                    FocusHandoff.shared.handoffFocus(to: screen.displayID)
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
