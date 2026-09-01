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
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let initialScreen = NSScreen.main ?? NSScreen.screens.first!
        let initialGeom = ScreenManager.calculateGeometry(for: initialScreen)
        self.currentGeometry = initialGeom
        self.refreshAllScreens()
        
        // 监听屏幕参数变化（如显示器插拔、分辨率或旋转变更）
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.handleScreenParametersChanged()
            }
            .store(in: &cancellables)
    }
    
    private var currentFocusedScreen: NSScreen?
    
    /// 刷新所有已连接显示器的几何数据
    public func refreshAllScreens() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        self.allGeometries = screens.map { ScreenManager.calculateGeometry(for: $0) }
        
        // 重新同步当前屏幕几何
        let activeScreen = self.activeScreen()
        let updatedGeom = ScreenManager.calculateGeometry(for: activeScreen)
        
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
        return NSScreen.main ?? NSScreen.screens.first!
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
    public func resolveGeometry(for screen: NSScreen = NSScreen.main ?? NSScreen.screens.first!) -> NotchGeometry {
        return ScreenManager.calculateGeometry(for: screen)
    }
    
    /// 根据 displayID 查询几何数据
    public func geometry(for displayID: CGDirectDisplayID) -> NotchGeometry? {
        return allGeometries.first { $0.displayID == displayID }
    }
    
    private func handleScreenParametersChanged() {
        refreshAllScreens()
    }
    
    /// 静态核心算法：计算单一屏幕的 NotchGeometry
    public static func calculateGeometry(for screen: NSScreen) -> NotchGeometry {
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
            // 无物理刘海机型或外接显示器：使用顶部居中虚拟锚点 (约 160x34 pt)
            let virtualWidth: CGFloat = 160.0
            let virtualHeight: CGFloat = 34.0
            let virtualX = screenFrame.minX + (screenFrame.width - virtualWidth) / 2.0
            let virtualY = screenFrame.maxY - virtualHeight
            notchRect = CGRect(x: virtualX, y: virtualY, width: virtualWidth, height: virtualHeight)
        }
        
        // 基准 Compact 胶囊尺寸（无溢出时严格 1:1 对齐物理刘海，高度精准对齐状态栏高度）
        let compactWidth: CGFloat = notchRect.width
        let compactHeight: CGFloat = statusBarHeight
        let compactX: CGFloat = notchRect.minX
        let compactY: CGFloat = screenFrame.maxY - compactHeight
        let compactBounds = CGRect(
            x: compactX,
            y: compactY,
            width: compactWidth,
            height: compactHeight
        )
        
        // 统一展开区域计算（默认按 6 项标准基准）
        let baseExtendedWidth: CGFloat = 140.0 + 6.0 * 36.0
        let extendedWidth: CGFloat = max(compactWidth, min(screenFrame.width * 0.75, min(baseExtendedWidth, 760.0)))
        let extendedHeight: CGFloat = 84.0
        let extendedBounds = CGRect(
            x: screenFrame.minX + (screenFrame.width - extendedWidth) / 2.0,
            y: screenFrame.maxY - extendedHeight,
            width: extendedWidth,
            height: extendedHeight
        )
        
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        
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
            statusBarHeight: statusBarHeight
        )
    }
}

extension NSScreen {
    /// 获取当前 NSScreen 对应的 CGDirectDisplayID
    public var displayID: CGDirectDisplayID {
        return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
