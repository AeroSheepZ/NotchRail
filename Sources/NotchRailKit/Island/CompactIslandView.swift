import SwiftUI

/// 灵动岛 Compact 胶囊态紧凑视图
@available(*, deprecated, message: "已整合至 IslandRootView 单一流体底座架构")
public struct CompactIslandView: View {
    public let overflowCount: Int
    public var onSettingsTapped: () -> Void = {}
    
    public init(
        overflowCount: Int = 0,
        onSettingsTapped: @escaping () -> Void = {}
    ) {
        self.overflowCount = overflowCount
        self.onSettingsTapped = onSettingsTapped
    }
    
    public var body: some View {
        ZStack {
            // 背景底座：全屏幕统一刘海造型
            IslandBackground(cornerRadius: IslandTheme.CornerRadius.COMPACT_BOTTOM)
            
            // 内容区域：复用统一的 IslandTopBar
            IslandTopBar(
                overflowCount: overflowCount,
                onSettingsTapped: onSettingsTapped
            )
            .padding(.leading, 7)
            .padding(.trailing, 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
