import SwiftUI

/// 纯 SwiftUI 矢量平滑旋转加载微光环（零 AppKit 宿主图层抖动，高清锐利）
public struct IslandSpinner: View {
    @State private var isRotating: Bool = false
    
    public init() {}
    
    public var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(
                Color.white.opacity(0.85),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    isRotating = true
                }
            }
    }
}

/// 灵动岛顶部左右通用的控制与状态栏（DRY：托盘黄色计数徽标 + 设置齿轮按钮）
public struct IslandTopBar: View {
    public let overflowCount: Int
    /// 跨屏同步/加载中：左耳翼展示旋转加载环；完成后平滑切换为数字徽标
    public var isSyncing: Bool = false
    /// 是否显示右侧设置齿轮（极简态隐藏：胶囊右侧与刘海平齐不遮挡原生图标，设置入口在展开态）
    public var showsSettingsButton: Bool = true
    public var onSettingsTapped: () -> Void = {}

    public init(
        overflowCount: Int = 0,
        isSyncing: Bool = false,
        showsSettingsButton: Bool = true,
        onSettingsTapped: @escaping () -> Void = {}
    ) {
        self.overflowCount = overflowCount
        self.isSyncing = isSyncing
        self.showsSettingsButton = showsSettingsButton
        self.onSettingsTapped = onSettingsTapped
    }

    public var body: some View {
        HStack {
            // 左侧状态指示：加载中显示 IslandSpinner；加载完成后若有溢出显示黄色徽标
            if isSyncing || overflowCount > 0 {
                HStack(spacing: 4) {
                    if isSyncing {
                        IslandSpinner()
                            .padding(.horizontal, 2)
                    } else {
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(IslandTheme.ColorPalette.TRAY_YELLOW)

                        countArea
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(IslandTheme.ColorPalette.CAPSULE_BACKGROUND)
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // 右侧指示：展开态展示设置齿轮（紧凑态保持 0 延展平齐，不遮挡原生图标）
            if showsSettingsButton {
                Button {
                    onSettingsTapped()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(4)
                        .background(IslandTheme.ColorPalette.CAPSULE_BACKGROUND)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("偏好设置")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .animation(.easeOut(duration: 0.2), value: showsSettingsButton)
        .animation(.easeOut(duration: 0.25), value: isSyncing)
        .animation(.easeOut(duration: 0.25), value: overflowCount > 0)
    }

    /// 数量展示区：数字展示（变化时平滑交叉溶解）
    @ViewBuilder
    private var countArea: some View {
        Text("\(overflowCount)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.9))
            .frame(minWidth: digitAreaWidth, alignment: .leading)
            .id(overflowCount)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.3), value: overflowCount)
    }

    /// 数字区宽度（复用统一度量计算器）
    private var digitAreaWidth: CGFloat {
        IslandWingMetrics.digitAreaWidth(for: overflowCount)
    }
}
