import SwiftUI
import AppKit

/// 岛内图标的**几何锚点**（AppKit 桥接，只回答「这一点落在哪个图标上」）
///
/// SwiftUI 无法回答「某个窗口坐标落在哪个 `MenuBarItem` 上」，而辅助点击（触控板双指 / 鼠标右键）
/// 必须知道目标项才能透传。本视图由 SwiftUI 按图标的真实布局摆位，因此它自己的 `frame`
/// 就是该图标的权威矩形 —— 绝不在 AppKit 侧重算一遍 SwiftUI 布局（那会制造第二处布局真相）。
///
/// ## 关键契约：绝不认领任何事件
///
/// `hitTest` **恒返回 nil**：本视图不参与事件路由，左键点击、流体拖拽重排、悬停高亮
/// 全部照常落到下方的 SwiftUI 手势上，对既有交互完全透明。
/// 辅助点击由 `IslandSecondaryClickRouter` 在视口宿主视图处裁决，命中后直接调用
/// `triggerSecondaryClick()`，不经过 AppKit 命中测试链。
struct IslandIconHitZone: NSViewRepresentable {
    /// 辅助点击（触控板双指 / 鼠标右键）触发回调
    let onSecondaryClick: () -> Void

    func makeNSView(context: Context) -> HitZoneView {
        let view = HitZoneView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: HitZoneView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }

    /// 纯几何锚点视图：不绘制、不认领事件
    final class HitZoneView: NSView {
        var onSecondaryClick: (() -> Void)?

        /// 恒不认领事件：本视图只是几何锚点，事件一律穿透给下面的 SwiftUI 视图
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// 由辅助点击裁决入口显式调用（不经 AppKit 命中测试）
        func triggerSecondaryClick() {
            onSecondaryClick?()
        }
    }
}

/// 辅助点击（触控板双指点击 = 鼠标右键）的**唯一裁决入口**
///
/// 由 `IslandHostingView`（视口宿主视图）在 `rightMouseDown` / `rightMouseUp` 处调用。
///
/// ## 为什么挂在宿主视图上，而不是 App 级事件监听器
///
/// 宿主视图位于**本应用窗口的事件链内**，与左键点击走同一条投递路径 —— 左键能进 SwiftUI 的
/// `Button`，右键必然也能进本视图。而 `NSEvent.addLocalMonitorForEvents` 在本应用非前台时并不可靠
/// （本地监听器随应用事件派发链路走），且 `addGlobalMonitorForEvents` **看不到本应用自身的事件**；
/// 一旦本地监听器不投递，辅助点击就会静默失效 —— 这正是真机「右键毫无反应」的原因。
///
/// 宿主视图处于视图类继承链最末端（`IslandHostingView` → `NSHostingView` → `NSView`），
/// 其 `rightMouseDown` 覆写**必然先于** `NSHostingView` 的实现被调用，因此不受 SwiftUI 内部处理策略影响。
///
/// **不依赖 `NSApp.currentEvent`**：裁决只用锚点自身 frame 做坐标换算，结果完全确定。
@MainActor
enum IslandSecondaryClickRouter {

    /// 裁决一次辅助点击
    ///
    /// - Returns: `true` 表示已被灵动岛图标认领，调用方**必须丢弃**该事件
    ///   （不得再上抛给 `super`，否则窗口层会再做一次无意义处理）。
    static func route(
        windowPoint: NSPoint,
        in hostView: NSView
    ) -> Bool {
        let zones = collectZones(in: hostView)
        guard let zone = zones.first(where: {
            $0.bounds.contains($0.convert(windowPoint, from: nil))
        }) else {
            return false
        }

        zone.triggerSecondaryClick()
        return true
    }

    /// 收集宿主视图树内全部图标锚点（显式深度遍历，不依赖 AppKit 命中测试链）
    private static func collectZones(in rootView: NSView) -> [IslandIconHitZone.HitZoneView] {
        var found: [IslandIconHitZone.HitZoneView] = []
        var pending: [NSView] = [rootView]
        while let view = pending.popLast() {
            if let zone = view as? IslandIconHitZone.HitZoneView,
               zone.window != nil,
               !zone.isHiddenOrHasHiddenAncestor {
                found.append(zone)
            }
            pending.append(contentsOf: view.subviews)
        }
        return found
    }
}
