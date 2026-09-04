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
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
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
    
    /// 处理鼠标移动：全屏顶边缘唤醒 + 硬件级穿透判定
    private func handleMouseMove(at location: CGPoint) {
        let prefs = PreferenceStore.shared.preferences
        let geom = ScreenManager.shared.effectiveGeometry(for: prefs.externalDisplayMode)
        
        // 仅当鼠标位于当前灵动岛所在的屏幕物理区域时进行判定，绝不随鼠标移动乱切屏
        guard NSMouseInRect(location, geom.screenFrame, false) else { return }
        
        // 1. 全屏沉浸协同：检测当前屏幕是否处于全屏空间
        if geom.isFullScreenSpace {
            let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)
            let overflowCount = targetSnapshot?.overflowCount ?? 0
            
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
                let isExpanded = IslandStateMachine.shared.currentState.isExpanded
                let screenRect = geom.interactiveScreenRect(isExpanded: isExpanded, overflowCount: overflowCount)
                
                // 宽限判定：在灵动岛交互区（外扩 16pt）或紧贴灵动岛正上方顶边缘 10pt 内（Spec L23，收敛整屏宽避免破坏沉浸）
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
                    // 鼠标移出灵动岛交互区，读取用户偏好设置的时延启动宽限平滑淡退 (Spec L23)
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
        
        let isExpanded = IslandStateMachine.shared.currentState.isExpanded
        if isExpanded {
            IslandWindowCoordinator.shared.setIgnoresMouseEvents(false)
            return
        }
        
        let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)
        let overflowCount = targetSnapshot?.overflowCount ?? 0
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
    }
    
    /// 处理用户在特定屏幕上的点击激活（与 ScreenManager 单一可信源直连，零缓存阻断）
    private func handleClick(at location: CGPoint) {
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
        isAwakenedInFullScreen = false
        
        if let mainScreen = NSScreen.main {
            let currentDisplayID = ScreenManager.shared.currentGeometry.displayID
            if mainScreen.displayID != currentDisplayID {
                ScreenManager.shared.updateActiveFocusScreen(to: mainScreen)
            }
        }
        IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
    }
}
