import AppKit
import NotchRailKit

/// 应用入口
///
/// **刻意不使用 SwiftUI 的 `App` 协议**：本应用的全部窗口（灵动岛吸顶面板、偏好设置窗口、
/// 权限引导窗口）均由 AppKit 手动创建与托管，SwiftUI 仅用于视图层
/// （`NSHostingController` / `NSHostingView`）。
///
/// 原因（真机实测）：只要声明了 SwiftUI 场景（`Settings` 或 `WindowGroup`），macOS 会在
/// **应用启动时自动创建并显示**该场景的窗口 —— 在 `.app` bundle + `LSUIElement` 环境下实测为
/// 「启动即多出一个普通层级窗口（680×528，位置固定在焦点屏）」。历史缺陷「关闭设置后冒出
/// 空白设置面板」正是它：v0.0.9 的 `Settings` 场景渲染 `EmptyView`（故为空白），自建设置窗口
/// 一关闭，它就露了出来。改用 AppKit 手动启动可彻底消除这个窗口。
@main
@MainActor
enum NotchRailMain {
    /// 强引用委托（`NSApplication.delegate` 为 weak，须自行持有）
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
