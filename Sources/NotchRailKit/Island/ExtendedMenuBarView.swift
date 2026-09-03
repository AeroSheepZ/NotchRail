import SwiftUI
import AppKit

/// 展开态扩展菜单栏视图
@available(*, deprecated, message: "已整合至 IslandRootView 单一流体底座架构")
public struct ExtendedMenuBarView: View {
    public let overflowItems: [MenuBarItem]
    public let scaleFactor: CGFloat
    public var onItemTap: (MenuBarItem) async -> Bool
    public var onSettingsTapped: () -> Void = {}

    /// 批量解析后的图标（按 item.id 索引）
    @State private var icons: [UUID: NSImage] = [:]

    public init(
        overflowItems: [MenuBarItem] = [],
        scaleFactor: CGFloat = 2.0,
        onItemTap: @escaping (MenuBarItem) async -> Bool = { _ in true },
        onSettingsTapped: @escaping () -> Void = {}
    ) {
        self.overflowItems = overflowItems
        self.scaleFactor = scaleFactor
        self.onItemTap = onItemTap
        self.onSettingsTapped = onSettingsTapped
    }

    public var body: some View {
        ZStack {
            // 背景底座：全屏幕统一刘海展开造型
            IslandBackground(cornerRadius: IslandTheme.CornerRadius.EXTENDED_BOTTOM)

            VStack(spacing: 8) {
                // 顶部状态与功能栏：复用统一的 IslandTopBar
                IslandTopBar(
                    overflowCount: overflowItems.count,
                    onSettingsTapped: onSettingsTapped
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)

                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 14)

                // 图标展示区
                if overflowItems.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green.opacity(0.8))
                        Text("当前所有菜单栏图标均在原生屏幕中完整显示")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(overflowItems) { item in
                                IslandIconCell(
                                    item: item,
                                    state: icons[item.id].map { IconState.loaded($0) } ?? .pending,
                                    onTap: { itm in
                                        await onItemTap(itm)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: overflowItems.map(\.id)) {
            // 批量解析图标：一次合成截图解析全部（兼容旧视图，走快照式 API）
            let resolved = await IconResolver.shared.resolveIconsSnapshot(for: overflowItems)
            icons = resolved.compactMapValues { $0.image }
        }
    }
}
