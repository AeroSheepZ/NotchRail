import Foundation
import CoreGraphics
import AppKit

/// 表示屏幕与刘海几何测量数据
public struct NotchGeometry: Equatable, Sendable, Identifiable {
    public var id: CGDirectDisplayID { displayID }
    
    public let displayID: CGDirectDisplayID
    public let displayName: String
    public let isBuiltIn: Bool
    public let hasPhysicalNotch: Bool
    public let scaleFactor: CGFloat
    public let screenFrame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaInsets: NSEdgeInsets
    public let physicalNotchRect: CGRect
    public let compactBounds: CGRect
    public let extendedBounds: CGRect
    public let statusBarHeight: CGFloat
    
    public init(
        displayID: CGDirectDisplayID,
        displayName: String = "Display",
        isBuiltIn: Bool,
        hasPhysicalNotch: Bool,
        scaleFactor: CGFloat = 2.0,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaInsets: NSEdgeInsets = NSEdgeInsets(),
        physicalNotchRect: CGRect,
        compactBounds: CGRect,
        extendedBounds: CGRect,
        statusBarHeight: CGFloat = 24.0
    ) {
        self.displayID = displayID
        self.displayName = displayName
        self.isBuiltIn = isBuiltIn
        self.hasPhysicalNotch = hasPhysicalNotch
        self.scaleFactor = scaleFactor
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.safeAreaInsets = safeAreaInsets
        self.physicalNotchRect = physicalNotchRect
        self.compactBounds = compactBounds
        self.extendedBounds = extendedBounds
        self.statusBarHeight = statusBarHeight
    }
    
    public static func == (lhs: NotchGeometry, rhs: NotchGeometry) -> Bool {
        return lhs.displayID == rhs.displayID &&
               lhs.displayName == rhs.displayName &&
               lhs.isBuiltIn == rhs.isBuiltIn &&
               lhs.hasPhysicalNotch == rhs.hasPhysicalNotch &&
               lhs.scaleFactor == rhs.scaleFactor &&
               lhs.screenFrame == rhs.screenFrame &&
               lhs.visibleFrame == rhs.visibleFrame &&
               lhs.physicalNotchRect == rhs.physicalNotchRect &&
               lhs.compactBounds == rhs.compactBounds &&
               lhs.extendedBounds == rhs.extendedBounds &&
               lhs.statusBarHeight == rhs.statusBarHeight &&
               lhs.safeAreaInsets.top == rhs.safeAreaInsets.top &&
               lhs.safeAreaInsets.bottom == rhs.safeAreaInsets.bottom &&
               lhs.safeAreaInsets.left == rhs.safeAreaInsets.left &&
               lhs.safeAreaInsets.right == rhs.safeAreaInsets.right
    }

    /// 根据当前溢出的图标数量动态计算展开区域
    public func dynamicExtendedBounds(for overflowCount: Int) -> CGRect {
        // 基础组件宽度（左右边距 28 + 齿轮按钮 28 + 数量徽章 40 + 容错间距 = 140）
        let baseWidth: CGFloat = 140.0
        // 每个溢出图标占用宽度（Cell 宽 28 + spacing 8 = 36）
        let itemWidth: CGFloat = 36.0
        
        let contentWidth: CGFloat
        if overflowCount > 0 {
            contentWidth = baseWidth + CGFloat(overflowCount) * itemWidth
        } else {
            // 0 溢出项时展开展示舒展的空状态信息
            contentWidth = 360.0
        }
        
        // 展开宽度下限为 compactBounds.width，上限为当前屏幕宽度的 75% 或 760pt
        let maxWidth = min(screenFrame.width * 0.75, 760.0)
        let dynamicWidth = max(compactBounds.width, min(contentWidth, maxWidth))
        let dynamicHeight: CGFloat = IslandTheme.Dimension.EXTENDED_HEIGHT
        
        return CGRect(
            x: screenFrame.minX + (screenFrame.width - dynamicWidth) / 2.0,
            y: screenFrame.maxY - dynamicHeight,
            width: dynamicWidth,
            height: dynamicHeight
        )
    }
}
