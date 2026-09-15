import Foundation
import AppKit
import SwiftUI

/// 负责独立 Settings 偏好设置窗口的呈现与生命周期
///
/// 生命周期契约（对应「关闭设置后重现空白设置面板」缺陷）：
/// - 只复用**当前可见**的窗口；不可见的一律丢弃重建；
/// - 窗口关闭时同步释放引用**并剥离托管视图**（`windowWillClose`），下次打开必定重建全新窗口与视图树，
///   绝不复用已关闭的旧窗口（旧窗口的托管视图在关闭时已被拆卸，复用会呈现空白）；
/// - 窗口置 `isReleasedWhenClosed = false`，保证引用存活期内不会因关闭而悬垂。
@MainActor
public final class SettingsWindowCoordinator: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowCoordinator()

    /// 自建设置窗口（nil 表示当前没有活动窗口）
    private var window: NSWindow?

    private override init() {
        super.init()
    }

    /// 显示偏好设置窗口
    public func showSettings() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 已关闭的旧窗口一律丢弃并重建，杜绝复用已拆卸视图树导致的空白面板
        window = nil

        let hostingController = NSHostingController(rootView: SettingsView())
        let panel = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsView.SettingsLayout.WINDOW_WIDTH,
                height: SettingsView.SettingsLayout.WINDOW_HEIGHT
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "NotchRail 偏好设置"
        // ⚠️ 顺序不可颠倒：设置 `contentViewController` 会让 AppKit 按视图控制器的适配尺寸**重设窗口大小**。
        // 若先 `center()` 再设控制器，窗口会在居中之后被撑高，顶部越出屏幕后被系统约束回顶边缘，
        // 表现为「窗口贴在屏幕上边缘水平居中」。必须先设控制器，再对**最终尺寸**居中。
        panel.contentViewController = hostingController
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 关闭设置窗口
    public func closeSettings() {
        window?.close()
        window = nil
    }

    // MARK: - NSWindowDelegate

    /// 用户点击关闭按钮时同步释放引用并剥离托管视图（下次打开走全新窗口构建路径）
    public func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        closing.contentViewController = nil
        window = nil
    }
}
