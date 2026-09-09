import SwiftUI
import AppKit

/// 灵动岛展开态下支持流体拖拽重排的图标横向排列视图
public struct ReorderableIconRow: View {
    public let items: [MenuBarItem]
    @ObservedObject public var iconResolver: IconResolver
    public var onItemTap: (MenuBarItem) async -> Bool
    public var onReorder: ([MenuBarItem]) -> Void
    
    @State private var localItems: [MenuBarItem] = []
    @State private var draggingItemID: UUID? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    public init(
        items: [MenuBarItem],
        iconResolver: IconResolver,
        onItemTap: @escaping (MenuBarItem) async -> Bool,
        onReorder: @escaping ([MenuBarItem]) -> Void
    ) {
        self.items = items
        self.iconResolver = iconResolver
        self.onItemTap = onItemTap
        self.onReorder = onReorder
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(localItems) { item in
                    let isCurrentDragging = draggingItemID == item.id
                    IslandIconCell(
                        item: item,
                        state: iconResolver.iconStates[item.iconCacheKey] ?? .pending,
                        onTap: { itm in
                            guard !isDragging else { return false }
                            return await onItemTap(itm)
                        }
                    )
                    .scaleEffect(isCurrentDragging ? 1.12 : 1.0)
                    .shadow(color: isCurrentDragging ? Color.black.opacity(0.35) : Color.clear, radius: 4, x: 0, y: 2)
                    .offset(x: isCurrentDragging ? dragOffset : 0)
                    .zIndex(isCurrentDragging ? 10 : 0)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { gesture in
                                if draggingItemID == nil {
                                    draggingItemID = item.id
                                    isDragging = true
                                }
                                dragOffset = gesture.translation.width
                                
                                guard let currentIndex = localItems.firstIndex(where: { $0.id == item.id }) else { return }
                                let stepThreshold: CGFloat = 24.0
                                
                                if dragOffset > stepThreshold && currentIndex < localItems.count - 1 {
                                    withAnimation(IslandTheme.Animation.FLUID_SPRING) {
                                        localItems.swapAt(currentIndex, currentIndex + 1)
                                        dragOffset -= stepThreshold
                                    }
                                    if PreferenceStore.shared.preferences.enableHapticFeedback {
                                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                    }
                                } else if dragOffset < -stepThreshold && currentIndex > 0 {
                                    withAnimation(IslandTheme.Animation.FLUID_SPRING) {
                                        localItems.swapAt(currentIndex, currentIndex - 1)
                                        dragOffset += stepThreshold
                                    }
                                    if PreferenceStore.shared.preferences.enableHapticFeedback {
                                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                    }
                                }
                            }
                            .onEnded { _ in
                                withAnimation(IslandTheme.Animation.FLUID_SPRING) {
                                    dragOffset = 0
                                    draggingItemID = nil
                                }
                                onReorder(localItems)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    isDragging = false
                                }
                            }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .frame(height: 36)
        .onAppear {
            localItems = items
        }
        .onChange(of: items) { _, newItems in
            if draggingItemID == nil {
                localItems = newItems
            }
        }
    }
}
