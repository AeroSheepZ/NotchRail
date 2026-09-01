import SwiftUI
import AppKit

/// 灵动岛内展示的单个菜单栏图标单元格
///
/// 尺寸策略（对齐原生菜单栏图标观感的关键）：
/// - **高度对齐**：图标高度固定为 menu bar 图标高度，宽度按截图真实宽高比自适应，
///   带文字的宽图标（电池 / 输入法 / Dropbox）不会被压进正方形框里缩成一小点
/// - **占位零跳动**：pending / failed 时按菜单栏窗口真实宽高比预留位置，
///   图标到达后布局完全不变
/// - **占位图标**：优先显示归属 App 的真实图标（bundleID 反查），回退 SF Symbol
public struct IslandIconCell: View {
    public let item: MenuBarItem
    public let state: IconState
    public var onTap: (MenuBarItem) async -> Bool

    @State private var isHovered: Bool = false
    @State private var shakeCount: CGFloat = 0
    /// 占位脉动相位（pending 态呼吸动画）
    @State private var pulseOn: Bool = false

    // MARK: - 尺寸常量

    /// 图标显示高度（对齐原生菜单栏图标高度）
    private static let ICON_HEIGHT: CGFloat = 22
    /// 单元格总高度（保持既有触控目标）
    private static let CELL_HEIGHT: CGFloat = 32
    /// 单元格最小宽度（窄图标也保证可点）
    private static let MIN_CELL_WIDTH: CGFloat = 32
    /// 图标两侧的水平内边距（药丸内）
    private static let PILL_H_INSET: CGFloat = 5

    public init(
        item: MenuBarItem,
        state: IconState = .pending,
        onTap: @escaping (MenuBarItem) async -> Bool = { _ in true }
    ) {
        self.item = item
        self.state = state
        self.onTap = onTap
    }

    // MARK: - 派生尺寸

    private var loadedImage: NSImage? {
        if case .loaded(let image) = state { return image }
        return nil
    }

    /// 占位态是否弱化显示（failed 比 pending 更弱，暗示该项不可用）
    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// 是否处于首次捕获进行中（脉动动画的触发条件）
    private var isPending: Bool {
        if case .pending = state { return true }
        return false
    }

    /// 图标显示尺寸：高度对齐、宽度按真实比例自适应
    private var displaySize: CGSize {
        let height = Self.ICON_HEIGHT
        if let image = loadedImage, image.size.height > 0 {
            let ratio = image.size.width / image.size.height
            return CGSize(width: max(1, height * ratio), height: height)
        }
        // 占位：按菜单栏窗口真实宽高比预留（clamp 防御异常 frame），图标到达后零跳动
        let aspect: CGFloat = item.nativeFrame.height > 0
            ? item.nativeFrame.width / item.nativeFrame.height
            : 1
        return CGSize(width: max(1, height * aspect.clamped(to: 0.6...6.0)), height: height)
    }

    /// 单元格宽度（自适应内容，窄图标保底）
    private var cellWidth: CGFloat {
        max(Self.MIN_CELL_WIDTH, displaySize.width + Self.PILL_H_INSET * 2)
    }

    // MARK: - 视图

    public var body: some View {
        Button {
            triggerAction()
        } label: {
            ZStack {
                // 悬停高亮胶囊背景（宽度随内容自适应）
                RoundedRectangle(cornerRadius: IslandTheme.CornerRadius.CELL)
                    .fill(isHovered ? IslandTheme.ColorPalette.CELL_HOVER : IslandTheme.ColorPalette.CELL_REST)
                    .overlay(
                        RoundedRectangle(cornerRadius: IslandTheme.CornerRadius.CELL)
                            .strokeBorder(isHovered ? Color.white.opacity(0.22) : Color.clear, lineWidth: IslandTheme.Stroke.LINE_WIDTH)
                    )

                contentView
                    .shadow(color: isHovered ? Color.white.opacity(0.2) : Color.clear, radius: 2, x: 0, y: 0)
            }
            .frame(width: cellWidth, height: Self.CELL_HEIGHT)
            .contentShape(Rectangle())
            .modifier(ShakeEffect(shakes: shakeCount))
        }
        .buttonStyle(SpringIconButtonStyle())
        .onHover { hovered in
            withAnimation(IslandTheme.Animation.HOVER_SPRING) {
                isHovered = hovered
            }
        }
        .help(item.title ?? item.bundleIdentifier ?? "Menu Item")
        .animation(IslandTheme.Animation.HOVER_SPRING, value: cellWidth)
    }

    @ViewBuilder
    private var contentView: some View {
        if let image = loadedImage {
            // 真实窗口截图：高质量插值 + 抗锯齿（还原原生渲染质感）
            Image(nsImage: image)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .frame(width: displaySize.width, height: displaySize.height)
        } else {
            placeholderView
        }
    }

    /// 占位视图：pending 时中性胶囊呼吸脉动（明确的"加载中"信号），failed 时静态弱化
    ///
    /// 刻意不显示 App 主图标：菜单栏图标是单色剪影，与彩色 App 图标长相完全
    /// 不同，"占位彩色图标 → 真实单色图标"的切换本身就是一次视觉突变。中性
    /// 胶囊与任何最终态都无冲突，加载完成后直接原位替换，视觉连续。
    @ViewBuilder
    private var placeholderView: some View {
        ZStack {
            // 中性占位胶囊：按窗口宽高比预留位置（淡填充 + 淡描边）
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(isFailed ? 0.05 : 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(isFailed ? 0.07 : 0.13), lineWidth: 1)
                )

            // pending 时中心一个细小的脉动圆点（低调的"正在加载"信号）
            if isPending {
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        // pending：0.35 ↔ 0.8 呼吸脉动；failed：静态 0.45
        .opacity(isFailed ? 0.45 : (pulseOn ? 0.35 : 0.8))
        .onAppear {
            guard isPending, !pulseOn else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseOn = true
            }
        }
    }

    // MARK: - 交互

    private func triggerAction() {
        Task {
            let success = await onTap(item)
            if !success {
                // 失败时触发轻量横向 Shake 抖动
                withAnimation(.linear(duration: 0.25)) {
                    shakeCount += 1.0
                }
            }
        }
    }
}

/// 具备弹性按下缩放反馈的图标按钮样式 (0.90x Press Down)
struct SpringIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(IslandTheme.Animation.PRESS_SPRING, value: configuration.isPressed)
    }
}

// MARK: - 数值工具

extension Comparable {
    /// 将值限制在闭区间内
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
