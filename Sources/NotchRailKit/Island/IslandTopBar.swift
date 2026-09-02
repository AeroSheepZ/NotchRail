import SwiftUI

/// 灵动岛顶部左右通用的控制与状态栏（DRY：托盘黄色计数徽标 + 设置齿轮按钮）
public struct IslandTopBar: View {
    public let overflowCount: Int
    /// 跨屏同步中（快照与新屏不一致）：数字区显示脉动占位，不展示不可信的旧值
    public var isSyncing: Bool = false
    /// 是否显示右侧设置齿轮（极简态隐藏：胶囊右侧与刘海平齐不遮挡原生图标，设置入口在展开态）
    public var showsSettingsButton: Bool = true
    public var onSettingsTapped: () -> Void = {}

    @State private var pulseOn: Bool = false

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
            // 左侧常态指示：黄色图标与溢出数量徽标（紧凑态下精准置于动态左耳翼可视发光区域）
            if overflowCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(IslandTheme.ColorPalette.TRAY_YELLOW)

                    countArea
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(IslandTheme.ColorPalette.CAPSULE_BACKGROUND)
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // 右侧常态指示：设置齿轮按钮（极简态隐藏，展开时淡入）
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
        .animation(.easeOut(duration: 0.2), value: overflowCount > 0)
    }

    /// 数量展示区：同步中 → 脉动占位；可信 → 数字（变化时平滑滚动）
    @ViewBuilder
    private var countArea: some View {
        ZStack {
            if isSyncing {
                // 脉动圆点（与图标加载占位同语言）；宽度对齐数字避免胶囊跳动
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .opacity(pulseOn ? 0.3 : 0.9)
                    .frame(width: digitAreaWidth, alignment: .leading)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            pulseOn = true
                        }
                    }
                    .transition(.opacity)
            } else {
                Text("\(overflowCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(minWidth: digitAreaWidth, alignment: .leading)
                    // id 变化触发 identity 重建 → 与 .transition(.opacity) 配合实现数字交叉溶解
                    .id(overflowCount)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isSyncing)
        .animation(.easeOut(duration: 0.3), value: overflowCount)
    }

    /// 数字区宽度（按实际数字位数动态分配等宽宽度）
    private var digitAreaWidth: CGFloat {
        let countString = "\(overflowCount)"
        return CGFloat(max(1, countString.count)) * 7.5 + 2.5
    }
}
