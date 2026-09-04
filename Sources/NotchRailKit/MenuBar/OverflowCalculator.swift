import Foundation
import CoreGraphics

/// 负责根据屏幕几何与刘海位置判定菜单栏溢出项的纯函数计算器
public enum OverflowCalculator {
    /// 刘海右侧圆角过渡区安全容差（pt，适配 MacBook 物理刘海圆角与系统内衬安全边界）
    public static let NOTCH_CORNER_SAFETY_MARGIN: CGFloat = 24.0
    /// 屏幕边缘溢出容差（pt）
    public static let SCREEN_EDGE_TOLERANCE: CGFloat = 5.0
    
    /// 计算并标记所有菜单项的展示模式 (nativeVisible / overflowed / ignored)
    public static func resolve(
        items: [MenuBarItem],
        geometry: NotchGeometry,
        ignoredBundleIDs: Set<String> = []
    ) -> MenuBarSnapshot {
        let notchRightEdge = geometry.physicalNotchRect.maxX
        let screenMinX = geometry.screenFrame.minX
        let screenMaxX = geometry.screenFrame.maxX
        
        let resolvedItems = items.map { item -> MenuBarItem in
            var updated = item
            
            // 1. 用户忽略黑名单判定
            if let bundleID = item.bundleIdentifier, ignoredBundleIDs.contains(bundleID) {
                updated.displayMode = .ignored
                return updated
            }
            
            let frame = item.nativeFrame
            
            // 2. 纯几何物理溢出判定：
            // - 左边界侵入刘海右边缘圆角过渡区 (frame.minX < notchRightEdge + NOTCH_CORNER_SAFETY_MARGIN)
            // - 超出屏幕右边界 (frame.maxX > screenMaxX + SCREEN_EDGE_TOLERANCE)
            // - 超出屏幕左边界 (frame.maxX < screenMinX)
            // 严禁依赖 !item.isOnScreen：全屏或 Space 切换折叠菜单栏时 WindowServer 会将所有菜单项标记为未上屏，依赖该状态会导致整个菜单栏被误判为全部溢出！
            let isOverflown = frame.minX < (notchRightEdge + NOTCH_CORNER_SAFETY_MARGIN) ||
                              frame.maxX > (screenMaxX + SCREEN_EDGE_TOLERANCE) ||
                              frame.maxX < screenMinX
            
            if isOverflown {
                updated.displayMode = .overflowed
            } else {
                updated.displayMode = .nativeVisible
            }
            
            return updated
        }
        
        return MenuBarSnapshot(
            displayID: geometry.displayID,
            allItems: resolvedItems,
            screenFrame: geometry.screenFrame,
            notchRect: geometry.physicalNotchRect
        )
    }
}
