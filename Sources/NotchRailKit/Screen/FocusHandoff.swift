import Foundation
import AppKit
import CoreGraphics

/// 负责跨显示器交互驱动的活动菜单栏移交服务 (ADR 0017 / Ticket #59)
///
/// macOS 状态栏系统服务（WindowServer、控制中心、AXExtrasMenuBar）严格单前台活动屏独占。
/// 本服务在用户与目标屏确立交互意图时（防抖停留意图确立或显式点击），通过瞬态获焦机制将系统活动菜单栏
/// 移交至目标屏幕，使状态项获得真实光栅化与原位点击响应；交互完成后无感还原前台应用焦点，确保零抢焦。
@MainActor
public final class FocusHandoff {
    public static let shared = FocusHandoff()

    /// 此前处于前台的第三方应用（用于交互完成后无感还原）
    private weak var previousFrontApp: NSRunningApplication?

    private init() {}

    /// 将系统活动菜单栏与交互焦点无感移交至目标屏幕
    /// - Parameter displayID: 目标显示器 ID
    /// - Returns: 是否完成移交操作
    @discardableResult
    public func handoffFocus(to displayID: CGDirectDisplayID) -> Bool {
        // 1. 若目标屏已是当前活动屏，直接返回
        if ScreenManager.shared.currentGeometry.displayID == displayID {
            return true
        }

        // 2. 校验目标屏幕是否存在
        guard let targetScreen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            return false
        }

        // 3. 记录当前的第三方前台应用（用于交互完成后无感还原，确保零抢焦）
        let currentFrontApp = NSWorkspace.shared.frontmostApplication
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let app = currentFrontApp, app.processIdentifier != ownPID {
            self.previousFrontApp = app
        }

        // 4. 获取目标屏专属视口并执行瞬态获焦
        guard IslandWindowCoordinator.shared.performTransientKeyActivation(for: displayID) else {
            return false
        }

        // 5. 更新 ScreenManager 内部活动屏幕
        ScreenManager.shared.updateActiveFocusScreen(to: targetScreen)

        return true
    }

    /// 在灵动岛收起或交互完成时，无感将前台焦点还原给此前的工作应用
    public func restorePreviousFocus() {
        guard let app = previousFrontApp, !app.isTerminated else {
            previousFrontApp = nil
            return
        }
        self.previousFrontApp = nil
        app.activate()
    }
}
