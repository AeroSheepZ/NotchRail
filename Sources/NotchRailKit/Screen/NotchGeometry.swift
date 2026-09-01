import Foundation
import CoreGraphics
import AppKit

/// 灵动岛耳翼动态物理度量计算器（内容驱动：图标 + 间距 + 数字 + 内外边距）
public enum IslandWingMetrics {
    /// 计算左侧耳翼所需的动态物理宽度（足额预算外边距、灰色胶囊完整背景与刘海呼吸间距）
    public static func leftWingWidth(for overflowCount: Int, isSyncing: Bool = false) -> CGFloat {
        guard overflowCount > 0 || isSyncing else { return 0.0 }
        
        let outerLeadingMargin: CGFloat = 6.0
        let capsuleInternalPadding: CGFloat = 12.0 // 左右各 6pt
        let iconWidth: CGFloat = 13.0             // SF Symbol tray.full.fill 真实渲染宽度
        let itemSpacing: CGFloat = 4.0
        
        let digitCount = max(1, String(overflowCount).count)
        let digitWidth: CGFloat = CGFloat(digitCount) * 7.5 + 2.5 // 等宽数字区宽度 (1位数 10pt, 2位数 17.5pt)
        
        let notchTransitionMargin: CGFloat = 10.0 // 与物理刘海左侧喇叭口间的安全过渡距离
        
        let pillTotalWidth = capsuleInternalPadding + iconWidth + itemSpacing + digitWidth
        let totalWingWidth = outerLeadingMargin + pillTotalWidth + notchTransitionMargin
        return ceil(totalWingWidth)
    }
    
    /// 计算右侧耳翼所需的动态物理宽度（未来若有小组件/状态可动态扩展）
    public static func rightWingWidth() -> CGFloat {
        return 0.0
    }
}

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

    /// 根据当前溢出数量动态计算紧凑态几何边界
    /// 0 溢出时严格 1:1 贴合刘海物理尺寸；有溢出时左侧动态长出耳翼完全避开摄像头黑胶
    public func dynamicCompactBounds(for overflowCount: Int, isSyncing: Bool = false) -> CGRect {
        let leftWing = IslandWingMetrics.leftWingWidth(for: overflowCount, isSyncing: isSyncing)
        let rightWing = IslandWingMetrics.rightWingWidth()
        
        let compactWidth = physicalNotchRect.width + leftWing + rightWing
        let compactHeight = statusBarHeight
        let compactX = physicalNotchRect.minX - leftWing
        let compactY = screenFrame.maxY - compactHeight
        
        return CGRect(
            x: compactX,
            y: compactY,
            width: compactWidth,
            height: compactHeight
        )
    }

    /// 根据当前溢出的图标数量动态计算展开区域
    public func dynamicExtendedBounds(for overflowCount: Int, isSyncing: Bool = false) -> CGRect {
        let leftWing = IslandWingMetrics.leftWingWidth(for: max(1, overflowCount), isSyncing: isSyncing)
        // 保证展开态两侧宽度至少包含紧凑态耳翼并向外预留呼吸空间，彻底消除徽标与齿轮被物理刘海遮挡
        let minExtendedWidth: CGFloat = max(356.0, physicalNotchRect.width + 2.0 * leftWing + 32.0)
        
        // 基础组件宽度（左右边距 28 + 齿轮按钮 28 + 数量徽章 40 + 容错间距 = 140）
        let baseWidth: CGFloat = 140.0
        let itemWidth: CGFloat = 36.0
        
        let contentWidth: CGFloat
        if overflowCount > 0 {
            contentWidth = baseWidth + CGFloat(overflowCount) * itemWidth
        } else {
            // 0 溢出项时展开展示舒展的空状态信息
            contentWidth = 360.0
        }
        
        // 展开宽度下限为 minExtendedWidth，上限为当前屏幕宽度的 85% 或 760pt
        let maxWidth = min(screenFrame.width * 0.85, 760.0)
        let dynamicWidth = max(minExtendedWidth, min(contentWidth, maxWidth))
        let dynamicHeight: CGFloat = IslandTheme.Dimension.EXTENDED_HEIGHT
        
        return CGRect(
            x: screenFrame.minX + (screenFrame.width - dynamicWidth) / 2.0,
            y: screenFrame.maxY - dynamicHeight,
            width: dynamicWidth,
            height: dynamicHeight
        )
    }

    /// 计算在本地视图坐标系（以左下角为原点）内用于 Hit-Test 判定的活跃灵动岛矩形
    public func interactiveBounds(
        in viewBounds: NSRect,
        isExpanded: Bool,
        overflowCount: Int,
        isSyncing: Bool = false
    ) -> NSRect {
        let compactBounds = dynamicCompactBounds(for: overflowCount, isSyncing: isSyncing)
        let compactWidth = compactBounds.width
        let compactHeight = statusBarHeight
        let dynamicWidth = dynamicExtendedBounds(for: max(1, overflowCount)).width
        
        let currentWidth = isExpanded ? dynamicWidth : compactWidth
        let currentHeight = isExpanded ? IslandTheme.Dimension.EXTENDED_HEIGHT : compactHeight
        
        // 计算耳翼相对刘海中心偏移量
        let leftWing = isExpanded ? 0.0 : IslandWingMetrics.leftWingWidth(for: overflowCount, isSyncing: isSyncing)
        let horizontalOffset = -leftWing / 2.0
        
        let x = (viewBounds.width - currentWidth) / 2.0 + horizontalOffset
        let y = viewBounds.height - currentHeight
        return NSRect(x: max(0, x), y: max(0, y), width: currentWidth, height: currentHeight)
    }
}
