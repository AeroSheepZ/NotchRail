import Foundation
import AppKit
import SwiftUI

/// 专为灵动岛定制的高精度 Hit-Test 宿主视图
/// 仅在鼠标落入真实可见的灵动岛异形几何胶囊内时认领事件，
/// 胶囊外的所有透明空白区域一律返回 nil，100% 物理穿透到底层应用（如 Chrome、Safari 等）
public final class IslandHostingView<Content: View>: NSHostingView<Content> {
    
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
        
        return super.hitTest(point)
    }
    
    /// 计算当前在本地视图坐标系（以左下角为原点）内的有效灵动岛胶囊区域
    private var currentIslandBounds: NSRect {
        let prefs = PreferenceStore.shared.preferences
        let geom = ScreenManager.shared.effectiveGeometry(for: prefs.externalDisplayMode)
        
        let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)
        let overflowCount = targetSnapshot?.overflowCount ?? 0
        let hasNoOverflow = overflowCount == 0
        let isExpanded = IslandStateMachine.shared.currentState.isExpanded
        
        // 0 溢出且开启自动隐藏（且非主动展开态）时，完全不响应任何鼠标
        if prefs.hideWhenNoOverflow && hasNoOverflow && !isExpanded {
            return .zero
        }
        
        return geom.interactiveBounds(
            in: bounds,
            isExpanded: isExpanded,
            overflowCount: overflowCount
        )
    }
}
