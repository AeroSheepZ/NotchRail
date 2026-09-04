import SwiftUI
import AppKit

/// 灵动岛统一背景图形：物理刘海屏保留喇叭口与纯黑底座，平直外接屏消除喇叭口呈现规整吸顶平直悬浮浮轨与毛玻璃 HUD 质感
public struct IslandBackground: View {
    public let cornerRadius: CGFloat
    public let hasPhysicalNotch: Bool
    
    public init(
        cornerRadius: CGFloat = IslandTheme.CornerRadius.COMPACT_BOTTOM,
        hasPhysicalNotch: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.hasPhysicalNotch = hasPhysicalNotch
    }
    
    public init(
        cornerRadius: CGFloat = IslandTheme.CornerRadius.COMPACT_BOTTOM,
        geometry: NotchGeometry
    ) {
        self.cornerRadius = cornerRadius
        self.hasPhysicalNotch = geometry.hasPhysicalNotch
    }
    
    public var body: some View {
        let topEar: CGFloat = hasPhysicalNotch ? IslandTheme.CornerRadius.TOP_EAR : 0.0
        
        ZStack {
            if hasPhysicalNotch {
                // 1. 物理刘海屏：统一纯黑吸光底座（闭合填充，与硬件刘海完全融合）
                NotchShape(bottomCornerRadius: cornerRadius, topEarRadius: topEar)
                    .fill(IslandTheme.ColorPalette.BACKGROUND)
                
                // 硬件级微光渐变边缘线（侧边与底部包边发光，顶部平直开口贴屏，绝无顶边白线）
                NotchBorderShape(bottomCornerRadius: cornerRadius, topEarRadius: topEar)
                    .stroke(
                        IslandTheme.Stroke.GRADIENT,
                        style: StrokeStyle(
                            lineWidth: IslandTheme.Stroke.LINE_WIDTH,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            } else {
                // 2. 平直外接屏：macOS 原生 HUD 质感（.ultraThinMaterial / white.opacity(0.15) 纯净描边 - SPEC Decision 6）
                NotchShape(bottomCornerRadius: cornerRadius, topEarRadius: 0.0)
                    .fill(.ultraThinMaterial)
                
                NotchBorderShape(bottomCornerRadius: cornerRadius, topEarRadius: 0.0)
                    .stroke(
                        Color.white.opacity(0.15),
                        style: StrokeStyle(
                            lineWidth: IslandTheme.Stroke.LINE_WIDTH,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
        }
        .shadow(
            color: hasPhysicalNotch ? .clear : IslandTheme.Shadow.COLOR,
            radius: hasPhysicalNotch ? 0 : IslandTheme.Shadow.RADIUS,
            x: hasPhysicalNotch ? 0 : IslandTheme.Shadow.X,
            y: hasPhysicalNotch ? 0 : IslandTheme.Shadow.Y
        )
    }
}

/// 物理级真实刘海闭合形状：用于纯黑吸光底座填充
public struct NotchShape: Shape {
    public var bottomCornerRadius: CGFloat
    public var topEarRadius: CGFloat
    
    public var animatableData: CGFloat {
        get { bottomCornerRadius }
        set { bottomCornerRadius = newValue }
    }
    
    public init(
        bottomCornerRadius: CGFloat = IslandTheme.CornerRadius.COMPACT_BOTTOM,
        topEarRadius: CGFloat = IslandTheme.CornerRadius.TOP_EAR
    ) {
        self.bottomCornerRadius = bottomCornerRadius
        self.topEarRadius = topEarRadius
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let clampedBottomRadius = max(0, min(bottomCornerRadius, rect.height / 2))
        let clampedTopEarRadius = max(0, min(topEarRadius, 6.0))
        
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        
        // 1. 从左上喇叭口最外缘起笔
        path.move(to: CGPoint(x: minX, y: minY))
        
        // 2. 左上喇叭口内凹平滑过渡
        if clampedTopEarRadius > 0 {
            path.addCurve(
                to: CGPoint(x: minX + clampedTopEarRadius, y: minY + clampedTopEarRadius),
                control1: CGPoint(x: minX + clampedTopEarRadius * 0.55, y: minY),
                control2: CGPoint(x: minX + clampedTopEarRadius, y: minY + clampedTopEarRadius * 0.45)
            )
        }
        
        // 3. 左侧主边缘
        path.addLine(to: CGPoint(x: minX + clampedTopEarRadius, y: maxY - clampedBottomRadius))
        
        // 4. 左下连续曲率平滑圆角
        if clampedBottomRadius > 0 {
            path.addCurve(
                to: CGPoint(x: minX + clampedTopEarRadius + clampedBottomRadius, y: maxY),
                control1: CGPoint(x: minX + clampedTopEarRadius, y: maxY - clampedBottomRadius * 0.45),
                control2: CGPoint(x: minX + clampedTopEarRadius + clampedBottomRadius * 0.45, y: maxY)
            )
        }
        
        // 5. 底部主边缘
        path.addLine(to: CGPoint(x: maxX - clampedTopEarRadius - clampedBottomRadius, y: maxY))
        
        // 6. 右下连续曲率平滑圆角
        if clampedBottomRadius > 0 {
            path.addCurve(
                to: CGPoint(x: maxX - clampedTopEarRadius, y: maxY - clampedBottomRadius),
                control1: CGPoint(x: maxX - clampedTopEarRadius - clampedBottomRadius * 0.45, y: maxY),
                control2: CGPoint(x: maxX - clampedTopEarRadius, y: maxY - clampedBottomRadius * 0.45)
            )
        }
        
        // 7. 右侧主边缘
        path.addLine(to: CGPoint(x: maxX - clampedTopEarRadius, y: minY + clampedTopEarRadius))
        
        // 8. 右上喇叭口向外平滑外展
        if clampedTopEarRadius > 0 {
            path.addCurve(
                to: CGPoint(x: maxX, y: minY),
                control1: CGPoint(x: maxX - clampedTopEarRadius, y: minY + clampedTopEarRadius * 0.45),
                control2: CGPoint(x: maxX - clampedTopEarRadius * 0.55, y: minY)
            )
        }
        
        // 9. 顶部闭合填充
        path.addLine(to: CGPoint(x: minX, y: minY))
        path.closeSubpath()
        
        return path
    }
}

/// 物理刘海微光高光边框轮廓（顶部开口，仅对左右侧边、喇叭口与底部圆角进行立体发光勾勒）
public struct NotchBorderShape: Shape {
    public var bottomCornerRadius: CGFloat
    public var topEarRadius: CGFloat
    
    public var animatableData: CGFloat {
        get { bottomCornerRadius }
        set { bottomCornerRadius = newValue }
    }
    
    public init(
        bottomCornerRadius: CGFloat = IslandTheme.CornerRadius.COMPACT_BOTTOM,
        topEarRadius: CGFloat = IslandTheme.CornerRadius.TOP_EAR
    ) {
        self.bottomCornerRadius = bottomCornerRadius
        self.topEarRadius = topEarRadius
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let clampedBottomRadius = max(0, min(bottomCornerRadius, rect.height / 2))
        let clampedTopEarRadius = max(0, min(topEarRadius, 6.0))
        
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        
        // 1. 从左上喇叭口最外边缘起笔
        path.move(to: CGPoint(x: minX, y: minY))
        
        // 2. 左上喇叭口内凹平滑过渡
        if clampedTopEarRadius > 0 {
            path.addCurve(
                to: CGPoint(x: minX + clampedTopEarRadius, y: minY + clampedTopEarRadius),
                control1: CGPoint(x: minX + clampedTopEarRadius * 0.55, y: minY),
                control2: CGPoint(x: minX + clampedTopEarRadius, y: minY + clampedTopEarRadius * 0.45)
            )
        }
        
        // 3. 左侧主边缘
        path.addLine(to: CGPoint(x: minX + clampedTopEarRadius, y: maxY - clampedBottomRadius))
        
        // 4. 左下连续曲率平滑圆角
        if clampedBottomRadius > 0 {
            path.addCurve(
                to: CGPoint(x: minX + clampedTopEarRadius + clampedBottomRadius, y: maxY),
                control1: CGPoint(x: minX + clampedTopEarRadius, y: maxY - clampedBottomRadius * 0.45),
                control2: CGPoint(x: minX + clampedTopEarRadius + clampedBottomRadius * 0.45, y: maxY)
            )
        }
        
        // 5. 底部主边缘
        path.addLine(to: CGPoint(x: maxX - clampedTopEarRadius - clampedBottomRadius, y: maxY))
        
        // 6. 右下连续曲率平滑圆角
        if clampedBottomRadius > 0 {
            path.addCurve(
                to: CGPoint(x: maxX - clampedTopEarRadius, y: maxY - clampedBottomRadius),
                control1: CGPoint(x: maxX - clampedTopEarRadius - clampedBottomRadius * 0.45, y: maxY),
                control2: CGPoint(x: maxX - clampedTopEarRadius, y: maxY - clampedBottomRadius * 0.45)
            )
        }
        
        // 7. 右侧主边缘
        path.addLine(to: CGPoint(x: maxX - clampedTopEarRadius, y: minY + clampedTopEarRadius))
        
        // 8. 右上喇叭口向外平滑外展（绘制到右上边缘即止，顶部不闭合！）
        if clampedTopEarRadius > 0 {
            path.addCurve(
                to: CGPoint(x: maxX, y: minY),
                control1: CGPoint(x: maxX - clampedTopEarRadius, y: minY + clampedTopEarRadius * 0.45),
                control2: CGPoint(x: maxX - clampedTopEarRadius * 0.55, y: minY)
            )
        }
        
        return path
    }
}
