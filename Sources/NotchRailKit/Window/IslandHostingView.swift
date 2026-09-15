import Foundation
import AppKit
import SwiftUI

/// 专为灵动岛定制的高精度 Hit-Test 宿主视图
///
/// 仅在鼠标落入真实可见的灵动岛异形几何胶囊内时认领事件，
/// 胶囊外的所有透明空白区域一律返回 nil，100% 物理穿透到底层应用（如 Chrome、Safari 等）。
///
/// **多屏契约**：每个视口持有自己锚定的 `displayID`，命中区一律以**本屏几何与本屏状态机**计算，
/// 绝不读取全局焦点屏或某个共享状态机 —— 否则外接屏展开时命中区会按内建屏几何错位。
public final class IslandHostingView<Content: View>: NSHostingView<Content> {

    /// 本视口锚定的屏幕 displayID（严格本屏自闭环）
    private let displayID: CGDirectDisplayID

    /// 本次辅助点击是否已被本视口认领（认领后同一次手势的抬起事件一并吞掉）
    private var claimsSecondaryClick = false

    public init(rootView: Content, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        super.init(rootView: rootView)
    }

    /// 满足 `NSHostingView` 的 required 构造要求；本视口必须显式绑定屏幕，故不可经此路径构建
    required init(rootView: Content) {
        fatalError("IslandHostingView 必须经 init(rootView:displayID:) 显式绑定屏幕")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("IslandHostingView 仅支持代码构建，不支持归档解码")
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let islandBounds = currentIslandBounds
        guard !islandBounds.isEmpty else {
            return nil
        }

        // 允许额外 2pt 的交互微调容错
        let interactiveRect = islandBounds.insetBy(dx: -2, dy: -2)
        guard interactiveRect.contains(point) else {
            return nil
        }

        // 辅助点击由本视口自行裁决，**直接认领给宿主视图自身**，不交给 SwiftUI 内部视图：
        // SwiftUI 没有右键手势原语，若其内部视图吞掉该事件，辅助点击就没有第二处捕获点。
        // `hitTest` 只在窗口派发鼠标事件的过程中被调用，此处 `NSApp.currentEvent` 恒为该事件本身。
        if NSApp.currentEvent?.type == .rightMouseDown {
            return self
        }

        return super.hitTest(point)
    }

    // MARK: - 辅助点击（触控板双指 / 鼠标右键）裁决

    /// 辅助点击的**唯一捕获点**（`rightMouseDown` / `rightMouseUp`）
    ///
    /// 本视图是左键点击已经证明可达的那一环（SwiftUI 的 `Button` 就在它的内容层里），
    /// 因此把辅助点击挂在这里，与左键共用同一条窗口事件投递路径，不依赖 App 级监听器。
    ///
    /// 命中图标锚点即派发并**吞掉事件**（不再上抛 `super`）：既不落 SwiftUI 手势，
    /// 也不会触发「点击外部即收起」判定。
    public override func rightMouseDown(with event: NSEvent) {
        if IslandSecondaryClickRouter.route(
            windowPoint: event.locationInWindow,
            in: self
        ) {
            claimsSecondaryClick = true
            return
        }
        super.rightMouseDown(with: event)
    }

    /// 抬起事件跟随同一次手势的裁决结果：认领过就一并吞掉，未认领一律照常上抛
    public override func rightMouseUp(with event: NSEvent) {
        guard claimsSecondaryClick else {
            super.rightMouseUp(with: event)
            return
        }
        claimsSecondaryClick = false
    }

    /// 计算当前在本地视图坐标系（以左下角为原点）内的有效灵动岛胶囊区域
    private var currentIslandBounds: NSRect {
        let prefs = PreferenceStore.shared.preferences
        // 严格以本视口锚定的屏幕几何与状态机为单一真实来源 (Ticket #46 & #47)
        guard let geom = ScreenManager.shared.geometry(for: displayID),
              let machine = IslandWindowCoordinator.shared.stateMachine(for: displayID) else {
            return .zero
        }
        let isExpanded = machine.currentState.isExpanded

        // 1. 平直屏未展开常态下，矩形严格归零，hitTest 绝对返回 nil，底层窗口 100% 物理直通 (Ticket #47)
        if !geom.hasPhysicalNotch && !isExpanded {
            return .zero
        }

        let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: displayID)
        let overflowCount = targetSnapshot?.overflowCount ?? 0
        let hasNoOverflow = overflowCount == 0

        // 2. 0 溢出且开启自动隐藏（且非主动展开态）时，完全不响应任何鼠标
        if prefs.hideWhenNoOverflow && hasNoOverflow && !isExpanded {
            return .zero
        }

        // 3. 展开态或物理刘海常驻态：计算精准活跃矩形（展开态为悬浮浮轨矩形）
        return geom.interactiveBounds(
            in: bounds,
            isExpanded: isExpanded,
            overflowCount: overflowCount
        )
    }
}
