import Foundation
import CoreGraphics
import AppKit

/// 基于私有 SkyLight API 的菜单栏扫描器（替代 AX 树遍历）
///
/// 菜单栏项本质上是 status window（layer == kCGStatusWindowLevel），
/// 直接按窗口枚举：零权限、一次系统调用、坐标精确。
public actor MenuBarWindowScanner {
    public static let shared = MenuBarWindowScanner()

    /// AX 扫描结果缓存（应用名 + 坐标），5s 内复用，避免每次扫描遍历所有应用（约 1.8s）
    private var cachedAXEntries: [MenuBarAXResolver.Entry] = []
    private var lastAXScanDate: Date?

    private init() {}

    /// 扫描指定屏幕上的全部菜单栏项
    ///
    /// - Parameter geometry: 目标屏幕几何（仅保留该屏幕上的窗口）
    public func scanMenuBarItems(for geometry: NotchGeometry) async -> [MenuBarItem] {
        // 私有 SkyLight API：能拿到完整窗口列表（含被刘海遮挡/紧贴刘海的窗口），
        // 公共 API `.optionOnScreenOnly` 会丢失这些窗口导致溢出检测失效。
        let windowIDs = Bridging.menuBarWindowIDs()
        let axEntries = axEntrySnapshot()
        var items: [MenuBarItem] = []

        // 窗口 frame 是 Quartz 全局坐标（左上原点），与 CGDisplayBounds 一致，
        // 不能用 NSScreen.frame（Cocoa 左下原点）直接比较。
        let screenBounds = CGDisplayBounds(geometry.displayID)

        for windowID in windowIDs {
            guard let info = Bridging.windowDescriptor(for: windowID) else { continue }

            // 1. 仅保留状态栏层级窗口（菜单栏项；全宽菜单栏底板为 layer 24，天然被过滤）
            guard info.layer == kCGStatusWindowLevel else { continue }

            // 2. 仅保留当前屏幕上的窗口
            guard info.frame.intersects(screenBounds) else { continue }

            // 3. 过滤无像素尺寸的占位窗口
            guard info.frame.width > 2 && info.frame.height > 2 else { continue }

            // 4. 防御性过滤全宽菜单栏底板（宽度接近屏宽）
            guard info.frame.width < screenBounds.width * 0.85 else { continue }

            let app = NSRunningApplication(processIdentifier: info.ownerPID)
            let item = MenuBarItem(
                windowID: info.windowID,
                processIdentifier: info.ownerPID,
                bundleIdentifier: Self.resolveBundleIdentifier(for: info, app: app),
                title: Self.displayName(for: info, app: app, axEntries: axEntries),
                nativeFrame: info.frame,
                displayMode: .nativeVisible,
                capability: .standardAXPress
            )
            items.append(item)
        }

        // 从右向左排序（符合 macOS 菜单栏从右往左的排布顺序）
        items.sort { $0.nativeFrame.maxX > $1.nativeFrame.maxX }
        return items
    }

    /// 返回 AX 扫描快照（带 30s 缓存，避免空闲心跳频繁遍历系统应用）
    private func axEntrySnapshot() -> [MenuBarAXResolver.Entry] {
        if let last = lastAXScanDate, Date().timeIntervalSince(last) < 30.0 {
            return cachedAXEntries
        }
        let entries = MenuBarAXResolver.scanEntries()
        cachedAXEntries = entries
        lastAXScanDate = Date()
        return entries
    }

    // MARK: - 名称与 Bundle 解析

    /// 解析窗口的 bundle identifier：
    /// - 第三方菜单栏项的 `kCGWindowName` 即其 bundleID（如 com.raycast.macos）；
    /// - 系统项（Clock/Battery/BentoBox 等）无独立 bundle，回退 owner 的 bundleID。
    private static func resolveBundleIdentifier(for info: Bridging.WindowDescriptor, app: NSRunningApplication?) -> String? {
        if let name = info.title, name.contains(".") {
            return name
        }
        return app?.bundleIdentifier
    }

    /// 解析用于展示的应用名。
    ///
    /// macOS 13+ 将所有菜单栏窗口的 owner 统一归到「控制中心」进程，`NSRunningApplication.localizedName`
    /// 对第三方项一律返回「控制中心」，因此不能依赖 owner 名称。正确来源（按优先级）：
    /// 1. 系统项（Clock/Battery/BentoBox）→ 友好中文名；
    /// 2. 第三方项（窗口名为 bundleID）→ 用 bundleID 反查应用显示名；
    /// 3. 空名 / "Item-0" → 用 AX 坐标匹配应用名；
    /// 4. 兜底 → 窗口名 / 应用名 / 占位。
    private static func displayName(
        for info: Bridging.WindowDescriptor,
        app: NSRunningApplication?,
        axEntries: [MenuBarAXResolver.Entry]
    ) -> String {
        guard let windowName = info.title, !windowName.isEmpty else {
            // 空窗口名：优先 AX 匹配，其次应用名
            if let axName = MenuBarAXResolver.resolveName(forFrame: info.frame, entries: axEntries) {
                return systemItemFriendlyName(axName) ?? axName
            }
            return app?.localizedName ?? "菜单栏项"
        }

        // 1. 系统项友好名
        if let friendly = systemItemFriendlyName(windowName) {
            return friendly
        }

        // 2. bundleID 反查应用显示名
        if windowName.contains(".") {
            return localizedAppName(forBundleID: windowName) ?? windowName
        }

        // 3. 无意义的占位名（如 "Item-0"）→ AX 坐标匹配应用名
        if windowName == "Item-0", let axName = MenuBarAXResolver.resolveName(forFrame: info.frame, entries: axEntries) {
            return systemItemFriendlyName(axName) ?? axName
        }

        // 4. 兜底
        return windowName
    }

    /// 系统菜单栏项窗口名 → 友好中文名映射
    private static func systemItemFriendlyName(_ name: String) -> String? {
        switch name {
        case "Clock": return "时钟"
        case "Battery": return "电池"
        case "BentoBox", "BentoBox-0": return "控制中心"
        case "apple.passwords": return "密码"
        default:
            // 浏览器扩展类菜单栏项（如 extension_mole_health-menu-bar__...）
            if name.hasPrefix("extension_") { return "浏览器扩展" }
            return nil
        }
    }

    /// 通过 bundleID 反查应用显示名（LS 注册的应用路径 + Info.plist）
    private static func localizedAppName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let bundle = Bundle(url: url)
        return bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.infoDictionary?["CFBundleName"] as? String
    }
}
