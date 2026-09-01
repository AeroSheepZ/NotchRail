import Foundation
import CoreGraphics
import AppKit

/// 基于私有 SkyLight API 的菜单栏极速扫描器（微秒级窗口枚举与几何解析）
public actor MenuBarWindowScanner {
    public static let shared = MenuBarWindowScanner()

    private init() {}

    /// 扫描指定屏幕上的全部菜单栏项（全流程 < 2ms）
    public func scanMenuBarItems(for geometry: NotchGeometry) async -> [MenuBarItem] {
        let windowIDs = Bridging.menuBarWindowIDs()
        let screenBounds = CGDisplayBounds(geometry.displayID)
        let axEntries = await MenuBarAXResolver.shared.latestEntries()
        
        var items: [MenuBarItem] = []

        for windowID in windowIDs {
            guard let info = Bridging.windowDescriptor(for: windowID) else { continue }
            guard info.layer == kCGStatusWindowLevel else { continue }
            guard info.frame.intersects(screenBounds) else { continue }
            guard info.frame.width > 2 && info.frame.height > 2 else { continue }
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

        // 从右向左排序
        items.sort { $0.nativeFrame.maxX > $1.nativeFrame.maxX }
        return items
    }

    // MARK: - 名称与 Bundle 解析

    private static func resolveBundleIdentifier(for info: Bridging.WindowDescriptor, app: NSRunningApplication?) -> String? {
        if let name = info.title, name.contains(".") {
            return name
        }
        return app?.bundleIdentifier
    }

    private static func displayName(
        for info: Bridging.WindowDescriptor,
        app: NSRunningApplication?,
        axEntries: [MenuBarAXResolver.Entry]
    ) -> String {
        guard let windowName = info.title, !windowName.isEmpty else {
            if let axName = MenuBarAXResolver.resolveName(forFrame: info.frame, entries: axEntries) {
                return systemItemFriendlyName(axName) ?? axName
            }
            return app?.localizedName ?? "菜单栏项"
        }

        if let friendly = systemItemFriendlyName(windowName) {
            return friendly
        }

        if windowName.contains(".") {
            return localizedAppName(forBundleID: windowName) ?? windowName
        }

        if windowName == "Item-0", let axName = MenuBarAXResolver.resolveName(forFrame: info.frame, entries: axEntries) {
            return systemItemFriendlyName(axName) ?? axName
        }

        return windowName
    }

    private static func systemItemFriendlyName(_ name: String) -> String? {
        switch name {
        case "Clock": return "时钟"
        case "Battery": return "电池"
        case "BentoBox", "BentoBox-0": return "控制中心"
        case "apple.passwords": return "密码"
        default:
            if name.hasPrefix("extension_") { return "浏览器扩展" }
            return nil
        }
    }

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
