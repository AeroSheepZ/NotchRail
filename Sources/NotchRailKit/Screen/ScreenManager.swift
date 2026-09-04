import Foundation
import AppKit
import CoreGraphics
import Combine

extension Notification.Name {
    public static let notchGeometryChanged = Notification.Name("NotchRail.NotchGeometryChanged")
    public static let activeDisplayChanged = Notification.Name("NotchRail.ActiveDisplayChanged")
}

/// 管理多显示器枚举、物理刘海/虚拟锚点测量与活动屏幕追踪
@MainActor
public final class ScreenManager: ObservableObject {
    public static let shared = ScreenManager()
    
    @Published public private(set) var currentGeometry: NotchGeometry
    @Published public private(set) var allGeometries: [NotchGeometry] = []
    
    /// 获取主显示器几何（优先物理刘海屏或内置 Retina，回退主屏）
    public var primaryGeometry: NotchGeometry {
        return allGeometries.first(where: { $0.hasPhysicalNotch || $0.isBuiltIn })
            ?? allGeometries.first
            ?? currentGeometry
    }

    /// 根据多显示器偏好策略计算当前应生效的目标屏幕几何配置
    public func effectiveGeometry(for mode: ExternalDisplayMode) -> NotchGeometry {
        switch mode {
        case .followFocusedScreen, .disabled:
            return currentGeometry
        case .mainScreenOnly:
            return primaryGeometry
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let fallbackScreen = NSScreen.main ?? NSScreen.screens.first
        let initialGeom: NotchGeometry
        if let screen = fallbackScreen {
            initialGeom = ScreenManager.calculateGeometry(for: screen)
        } else {
            initialGeom = ScreenManager.calculateGeometry(for: NSScreen())
        }
        self.currentGeometry = initialGeom
        self.refreshAllScreens()
        self.updateAppMenuBoundariesAsync()
        
        // 监听屏幕参数变化（如显示器插拔、分辨率或旋转变更）
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.handleScreenParametersChanged()
            }
            .store(in: &cancellables)

        // 监听活动 Space 切换（进入/退出全屏空间、桌面滑动）
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleSpaceOrActiveAppChanged()
            }
            .store(in: &cancellables)

        // 监听前台应用切换（全屏应用与普通应用前后台切换，排除自身获焦）
        let ownPID = ProcessInfo.processInfo.processIdentifier
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notif in
                if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier == ownPID {
                    return
                }
                self?.handleSpaceOrActiveAppChanged()
            }
            .store(in: &cancellables)
    }
    
    private var currentFocusedScreen: NSScreen?
    
    /// 刷新所有已连接显示器的几何数据
    public func refreshAllScreens() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        self.allGeometries = screens.map { ScreenManager.calculateGeometry(for: $0, appMenuRightEdge: self.appMenuRightEdgeCache[$0.displayID]) }
        
        // 重新同步当前屏幕几何
        let activeScreen = self.activeScreen()
        let updatedGeom = ScreenManager.calculateGeometry(for: activeScreen, appMenuRightEdge: self.appMenuRightEdgeCache[activeScreen.displayID])
        
        if updatedGeom != self.currentGeometry {
            self.currentGeometry = updatedGeom
            NotificationCenter.default.post(name: .notchGeometryChanged, object: updatedGeom)
        }
    }
    
    /// 获取当前获得焦点或最后激活点击的活动屏幕
    public func activeScreen() -> NSScreen {
        if let focused = currentFocusedScreen, NSScreen.screens.contains(focused) {
            return focused
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }
    
    /// 由前台焦点变化或用户点击触发主动切换至目标屏幕
    @discardableResult
    public func updateActiveFocusScreen(to screen: NSScreen) -> Bool {
        self.currentFocusedScreen = screen
        let geom = resolveGeometry(for: screen)
        
        if geom.displayID != currentGeometry.displayID {
            self.currentGeometry = geom
            NotificationCenter.default.post(name: .activeDisplayChanged, object: geom)
            return true
        }
        return false
    }
    
    /// 检查并切换屏幕（兼容接口）
    @discardableResult
    public func updateActiveDisplayIfNeeded() -> Bool {
        let screen = activeScreen()
        return updateActiveFocusScreen(to: screen)
    }
    
    /// 解析特定屏幕的刘海几何数据
    public func resolveGeometry(for screen: NSScreen? = nil) -> NotchGeometry {
        let targetScreen = screen ?? activeScreen()
        return ScreenManager.calculateGeometry(for: targetScreen, appMenuRightEdge: appMenuRightEdgeCache[targetScreen.displayID])
    }
    
    /// 根据 displayID 查询几何数据
    public func geometry(for displayID: CGDirectDisplayID) -> NotchGeometry? {
        return allGeometries.first { $0.displayID == displayID }
    }
    
    private func handleScreenParametersChanged() {
        refreshAllScreens()
        updateAppMenuBoundariesAsync()
    }
    
    private var spaceTransitionWorkItem: DispatchWorkItem?
    private var menuBoundaryTask: Task<Void, Never>?
    
    /// 响应活动 Space 或前台 App 切换：仅更新全屏判定与视口穿透，不广播物理几何变更
    private func handleSpaceOrActiveAppChanged() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        self.allGeometries = screens.map { ScreenManager.calculateGeometry(for: $0, appMenuRightEdge: self.appMenuRightEdgeCache[$0.displayID]) }
        let active = self.activeScreen()
        let updatedGeom = ScreenManager.calculateGeometry(for: active, appMenuRightEdge: self.appMenuRightEdgeCache[active.displayID])
        self.currentGeometry = updatedGeom
        
        spaceTransitionWorkItem?.cancel()
        
        if updatedGeom.isFullScreenSpace {
            // 1. 进入全屏空间：第 0 帧立即隐退，绝不在放大过程中的全屏窗口上漂浮残留
            IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
        } else {
            // 2. 退出全屏至普通桌面：等待 250ms macOS Space 平移动画平稳落定，再优雅淡入
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                let finalScreens = NSScreen.screens
                if !finalScreens.isEmpty {
                    self.allGeometries = finalScreens.map { ScreenManager.calculateGeometry(for: $0, appMenuRightEdge: self.appMenuRightEdgeCache[$0.displayID]) }
                    let currentActive = self.activeScreen()
                    self.currentGeometry = ScreenManager.calculateGeometry(for: currentActive, appMenuRightEdge: self.appMenuRightEdgeCache[currentActive.displayID])
                }
                IslandWindowCoordinator.shared.applyDisplayAndVisibilityRules()
                self.updateAppMenuBoundariesAsync()
            }
            self.spaceTransitionWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }

        updateAppMenuBoundariesAsync()
    }
    
    /// 异步探测所有非物理刘海屏幕的前台 App 菜单栏右边界并更新内存缓存
    public func updateAppMenuBoundariesAsync() {
        menuBoundaryTask?.cancel()
        menuBoundaryTask = Task { [weak self] in
            let screens = NSScreen.screens
            for screen in screens {
                if Task.isCancelled { return }
                let insets = screen.safeAreaInsets
                let hasNotch = insets.top > 0
                
                // 仅针对非物理刘海屏幕探测前台 App 菜单右边界 (AGENTS.md 3.1)
                guard !hasNotch else { continue }
                
                let displayID = screen.displayID
                let screenBounds = screen.frame
                
                let maxX = await MenuBarAXResolver.shared.fetchFrontmostAppMenuMaxX(for: screenBounds)
                if Task.isCancelled { return }
                
                self?.updateAppMenuRightEdge(maxX, for: displayID)
            }
        }
    }
    
    private var appMenuRightEdgeCache: [CGDirectDisplayID: CGFloat] = [:]
    
    /// 更新指定显示器的前台 App 菜单右边缘物理坐标缓存（仅平直屏参与碰撞）
    public func updateAppMenuRightEdge(_ edge: CGFloat?, for displayID: CGDirectDisplayID) {
        if let edge = edge {
            appMenuRightEdgeCache[displayID] = edge
        } else {
            appMenuRightEdgeCache.removeValue(forKey: displayID)
        }
        
        let screens = NSScreen.screens
        self.allGeometries = screens.map { ScreenManager.calculateGeometry(for: $0, appMenuRightEdge: self.appMenuRightEdgeCache[$0.displayID]) }
        
        if currentGeometry.displayID == displayID,
           let updated = self.allGeometries.first(where: { $0.displayID == displayID }) {
            if updated != currentGeometry {
                currentGeometry = updated
                NotificationCenter.default.post(name: .notchGeometryChanged, object: updated)
            }
        }
    }
    
    /// 静态核心算法：计算单一屏幕的 NotchGeometry
    public static func calculateGeometry(for screen: NSScreen, appMenuRightEdge: CGFloat? = nil) -> NotchGeometry {
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        let displayName = screen.localizedName
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let scaleFactor = screen.backingScaleFactor
        let insets = screen.safeAreaInsets
        
        // 判定物理刘海（macOS 12+ auxiliaryTopLeftArea / safeAreaInsets.top > 0）
        let safeAreaTop = insets.top
        let hasNotch = safeAreaTop > 0
        let statusBarHeight: CGFloat = hasNotch ? safeAreaTop : (screenFrame.maxY - visibleFrame.maxY > 0 ? screenFrame.maxY - visibleFrame.maxY : 24.0)
        
        let notchRect: CGRect
        if hasNotch {
            // 计算两端辅助区域中间夹着的刘海宽度
            let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
            let notchWidth = max(screenFrame.width - leftWidth - rightWidth, 160.0)
            let notchHeight = safeAreaTop
            let notchX = screenFrame.minX + (screenFrame.width - notchWidth) / 2.0
            let notchY = screenFrame.maxY - notchHeight
            notchRect = CGRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
        } else {
            // 平直显示器（无物理刘海）：严格设为 .zero，坚决杜绝假想刘海
            notchRect = .zero
        }
        
        // 基准 Compact 胶囊尺寸（物理刘海屏 1:1 对齐物理刘海，高度对齐状态栏高度；平直屏常态 0 尺寸完全隐形）
        let compactBounds: CGRect
        if hasNotch {
            let compactWidth: CGFloat = notchRect.width
            let compactHeight: CGFloat = statusBarHeight
            let compactX: CGFloat = notchRect.minX
            let compactY: CGFloat = screenFrame.maxY - compactHeight
            compactBounds = CGRect(
                x: compactX,
                y: compactY,
                width: compactWidth,
                height: compactHeight
            )
        } else {
            compactBounds = .zero
        }
        
        // 统一展开区域计算（默认按 6 项标准基准）
        let baseExtendedWidth: CGFloat = 140.0 + 6.0 * 36.0
        let minWidth: CGFloat = hasNotch ? notchRect.width : 356.0
        let extendedWidth: CGFloat = max(minWidth, min(screenFrame.width * 0.75, min(baseExtendedWidth, 760.0)))
        let extendedHeight: CGFloat = 84.0
        let extendedBounds = CGRect(
            x: screenFrame.minX + (screenFrame.width - extendedWidth) / 2.0,
            y: screenFrame.maxY - extendedHeight,
            width: extendedWidth,
            height: extendedHeight
        )
        
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        let isFullScreen = FullScreenDetector.isFullScreen(on: screen)
        
        return NotchGeometry(
            displayID: displayID,
            displayName: displayName,
            isBuiltIn: isBuiltIn,
            hasPhysicalNotch: hasNotch,
            scaleFactor: scaleFactor,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            safeAreaInsets: insets,
            physicalNotchRect: notchRect,
            compactBounds: compactBounds,
            extendedBounds: extendedBounds,
            statusBarHeight: statusBarHeight,
            isFullScreenSpace: isFullScreen,
            appMenuRightEdge: appMenuRightEdge
        )
    }
}

extension NSScreen {
    /// 获取当前 NSScreen 对应的 CGDirectDisplayID
    public var displayID: CGDirectDisplayID {
        return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
