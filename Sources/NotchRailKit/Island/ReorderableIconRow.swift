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
    @State private var dragTranslation: CGFloat = 0
    @State private var targetDropIndex: Int? = nil
    @State private var itemWidths: [UUID: CGFloat] = [:]
    @State private var isDragging: Bool = false
    
    private let itemSpacing: CGFloat = 8.0
    
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
        let sourceIndex = draggingItemID.flatMap { id in localItems.firstIndex(where: { $0.id == id }) }
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: itemSpacing) {
                ForEach(Array(localItems.enumerated()), id: \.element.id) { index, item in
                    let isCurrentDragging = draggingItemID == item.id
                    let itemOffset = offsetForItem(at: index, sourceIndex: sourceIndex, targetIndex: targetDropIndex)
                    
                    IslandIconCell(
                        item: item,
                        state: iconResolver.iconStates[item.iconCacheKey] ?? .pending,
                        onTap: { itm in
                            guard !isDragging else { return false }
                            return await onItemTap(itm)
                        }
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ItemWidthPreferenceKey.self,
                                value: [item.id: proxy.size.width]
                            )
                        }
                    )
                    .scaleEffect(isCurrentDragging ? 1.12 : 1.0)
                    .shadow(color: isCurrentDragging ? Color.black.opacity(0.40) : Color.clear, radius: 5, x: 0, y: 2)
                    .offset(x: itemOffset)
                    .zIndex(isCurrentDragging ? 100 : 0)
                    .animation(isCurrentDragging ? nil : IslandTheme.Animation.FLUID_SPRING, value: itemOffset)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { gesture in
                                if draggingItemID == nil {
                                    draggingItemID = item.id
                                    isDragging = true
                                }
                                dragTranslation = gesture.translation.width
                                
                                if let src = localItems.firstIndex(where: { $0.id == item.id }) {
                                    let centers = computeSlotCenters()
                                    let newTarget = computeTargetIndex(sourceIndex: src, currentTarget: targetDropIndex, centers: centers)
                                    if newTarget != targetDropIndex {
                                        targetDropIndex = newTarget
                                        if PreferenceStore.shared.preferences.enableHapticFeedback {
                                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                        }
                                    }
                                }
                            }
                            .onEnded { _ in
                                guard let src = localItems.firstIndex(where: { $0.id == item.id }) else {
                                    resetDragState()
                                    return
                                }
                                let tgt = targetDropIndex ?? src
                                if src != tgt {
                                    var newItems = localItems
                                    let moved = newItems.remove(at: src)
                                    newItems.insert(moved, at: tgt)
                                    localItems = newItems
                                    onReorder(newItems)
                                    if PreferenceStore.shared.preferences.enableHapticFeedback {
                                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                    }
                                }
                                withAnimation(IslandTheme.Animation.FLUID_SPRING) {
                                    resetDragState()
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    isDragging = false
                                }
                            }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .onPreferenceChange(ItemWidthPreferenceKey.self) { widths in
                self.itemWidths = widths
            }
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
    
    // MARK: - 几何与拖拽位移计算
    
    private func resetDragState() {
        draggingItemID = nil
        dragTranslation = 0
        targetDropIndex = nil
    }
    
    private func computeSlotCenters() -> [CGFloat] {
        var centers: [CGFloat] = []
        var currentX: CGFloat = 0
        for item in localItems {
            let w = itemWidths[item.id] ?? 28.0
            centers.append(currentX + w / 2.0)
            currentX += w + itemSpacing
        }
        return centers
    }
    
    private func computeTargetIndex(sourceIndex: Int, currentTarget: Int?, centers: [CGFloat]) -> Int {
        guard !centers.isEmpty else { return sourceIndex }
        let currentCenter = centers[sourceIndex] + dragTranslation
        let activeTarget = currentTarget ?? sourceIndex
        
        var bestIndex = activeTarget
        var minDiff = abs(centers[activeTarget] - currentCenter)
        let hysteresis: CGFloat = 12.0 // 防抖死区（Hysteresis），必须越过中线 12pt 才触发槽位重排，彻底消除临界抽搐抖动
        
        for (idx, center) in centers.enumerated() {
            let diff = abs(center - currentCenter)
            if diff + hysteresis < minDiff {
                minDiff = diff
                bestIndex = idx
            }
        }
        return bestIndex
    }
    
    private func offsetForItem(at index: Int, sourceIndex: Int?, targetIndex: Int?) -> CGFloat {
        guard let src = sourceIndex else { return 0 }
        
        // 正在被拖拽的项直接跟随手指位移
        if index == src {
            return dragTranslation
        }
        
        guard let tgt = targetIndex, src != tgt else { return 0 }
        let draggedWidth = (itemWidths[localItems[src].id] ?? 28.0) + itemSpacing
        
        // 向右拖拽：源项之后的项向左让位
        if src < tgt {
            if index > src && index <= tgt {
                return -draggedWidth
            }
        }
        // 向左拖拽：源项之前的项向右让位
        else if src > tgt {
            if index >= tgt && index < src {
                return draggedWidth
            }
        }
        return 0
    }
}

private struct ItemWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
