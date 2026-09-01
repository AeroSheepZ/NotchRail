import SwiftUI

/// 灵动岛统一设计系统（Design System Tokens）
/// 单一可信数据源：全局尺寸、圆角、动画物理阻尼、描边与布局间距集中定义于此
public enum IslandTheme {
    
    // MARK: - 圆角与曲率 (Corner Radii)
    public enum CornerRadius {
        /// 物理刘海底部小圆角（MacBook 真实硬件曲率）
        public static let COMPACT_BOTTOM: CGFloat = 11.0
        /// 展开态大卡片底部圆角
        public static let EXTENDED_BOTTOM: CGFloat = 14.0
        /// 顶部与屏幕边框连接的外展平滑倒角（喇叭口）
        public static let TOP_EAR: CGFloat = 5.0
        /// 图标与小组件药丸圆角
        public static let CELL: CGFloat = 8.0
        public static let BADGE: CGFloat = 6.0
    }
    
    // MARK: - 基础几何尺寸 (Dimensions)
    public enum Dimension {
        public static let COMPACT_HEIGHT: CGFloat = 34.0
        public static let EXTENDED_HEIGHT: CGFloat = 84.0
        public static let TOP_BAR_HEIGHT: CGFloat = 32.0
    }
    
    // MARK: - 动画动力学 (Apple Spring Physics)
    public enum Animation {
        /// 展开/收起的主弹簧动画（对齐 boring.notch 与 Apple 原生流体弹簧曲线）
        public static let FLUID_SPRING = SwiftUI.Animation.spring(response: 0.38, dampingFraction: 0.78, blendDuration: 0)
        /// 图标按压快速响应弹簧
        public static let PRESS_SPRING = SwiftUI.Animation.spring(response: 0.20, dampingFraction: 0.70)
        /// 悬停微动效平滑弹簧
        public static let HOVER_SPRING = SwiftUI.Animation.spring(response: 0.22, dampingFraction: 0.72)
    }
    
    // MARK: - 交互节奏与防抖 (Interaction Timing)
    public enum Timing {
        /// 移入悬停意图防抖（120ms 稳健防误触）
        public static let HOVER_EXPAND_DELAY: TimeInterval = 0.12
        /// 移出离开宽限期（300ms 舒适从容）
        public static let COLLAPSE_DELAY: TimeInterval = 0.30
        /// 扩展热区向下延伸高度
        public static let HIT_TEST_BOTTOM_EXTENSION: CGFloat = 4.0
    }
    
    // MARK: - 微光高光边框 (Lighting & Stroke)
    public enum Stroke {
        public static let LINE_WIDTH: CGFloat = 0.75
        public static let GRADIENT = LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.18), location: 0.0),
                .init(color: Color.white.opacity(0.28), location: 0.4),
                .init(color: Color.white.opacity(0.10), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - 颜色与材质 (Palette & Materials)
    public enum ColorPalette {
        public static let BACKGROUND = Color.black
        public static let CAPSULE_BACKGROUND = Color.white.opacity(0.12)
        public static let CELL_HOVER = Color.white.opacity(0.16)
        public static let CELL_REST = Color.white.opacity(0.04)
        public static let TRAY_YELLOW = Color.yellow.opacity(0.95)
    }
}
