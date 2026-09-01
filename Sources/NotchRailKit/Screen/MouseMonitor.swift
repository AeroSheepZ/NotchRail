import Foundation
import AppKit
import CoreGraphics
import Combine

/// 全局前台焦点与点击跨屏监听器
/// 基于真实点击与应用前台激活驱动跨屏迁移，杜绝随鼠标划过乱跳
@MainActor
public final class MouseMonitor {
    public static let shared = MouseMonitor()
    
    private var globalMouseDownMonitor: Any?
    private var localMouseDownMonitor: Any?
    private var isMonitoring: Bool = false
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    /// 启动全局多屏焦点与点击追踪
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp]
        
        // 1. 全局鼠标点击与释放监听（捕获用户在任意屏幕上的激活点击）
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            Task { @MainActor in
                self?.handleClick(at: NSEvent.mouseLocation)
            }
        }
        
        // 2. 局部鼠标点击与释放监听（用户在自身灵动岛或窗口内点击）
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor in
                self?.handleClick(at: NSEvent.mouseLocation)
            }
            return event
        }
        
        // 3. 监听前台活动应用程序切换通知（Key Window 屏幕变化）
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in
                self?.syncActiveScreen()
            }
            .store(in: &cancellables)
        
        // 4. 监听活动空间/桌面切换通知（多屏 Space 切换第一响应通知）
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
        
        if let gm = globalMouseDownMonitor {
            NSEvent.removeMonitor(gm)
            globalMouseDownMonitor = nil
        }
        if let lm = localMouseDownMonitor {
            NSEvent.removeMonitor(lm)
            localMouseDownMonitor = nil
        }
        cancellables.removeAll()
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
        if let mainScreen = NSScreen.main {
            let currentDisplayID = ScreenManager.shared.currentGeometry.displayID
            if mainScreen.displayID != currentDisplayID {
                ScreenManager.shared.updateActiveFocusScreen(to: mainScreen)
            }
        }
    }
}
