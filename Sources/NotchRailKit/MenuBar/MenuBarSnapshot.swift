import Foundation
import CoreGraphics

/// 表示特定显示器上的菜单栏全量快照
public struct MenuBarSnapshot: Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let displayID: CGDirectDisplayID
    public let allItems: [MenuBarItem]
    public let screenFrame: CGRect
    public let notchRect: CGRect
    public let customItemOrder: [String]
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        displayID: CGDirectDisplayID,
        allItems: [MenuBarItem],
        screenFrame: CGRect,
        notchRect: CGRect,
        customItemOrder: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.displayID = displayID
        self.allItems = allItems
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.customItemOrder = customItemOrder
    }
    
    /// 仅展示在灵动岛内的溢出项（优先遵循 customItemOrder 定义的先后顺序，未排序项按物理空间依序排布）
    public var overflowItems: [MenuBarItem] {
        let overflowed = allItems.filter { $0.displayMode == .overflowed }
        guard !customItemOrder.isEmpty else { return overflowed }
        return overflowed.sorted(by: MenuBarItem.comparator(for: customItemOrder))
    }
    
    /// 溢出项总数
    public var overflowCount: Int {
        overflowItems.count
    }
    
    /// 原生仍可见的项
    public var visibleItems: [MenuBarItem] {
        allItems.filter { $0.displayMode == .nativeVisible }
    }
}
