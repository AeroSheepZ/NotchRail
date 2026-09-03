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

            await MenuBarAXResolver.shared.registerCandidatePID(info.ownerPID)
            let app = NSRunningApplication(processIdentifier: info.ownerPID)
            let (resolvedTitle, resolvedBundleID) = Self.resolveIdentity(
                for: info,
                app: app,
                axEntries: axEntries
            )

            let item = MenuBarItem(
                windowID: info.windowID,
                processIdentifier: info.ownerPID,
                bundleIdentifier: resolvedBundleID,
                title: resolvedTitle,
                nativeFrame: info.frame,
                displayMode: .nativeVisible,
                capability: .standardAXPress,
                isOnScreen: info.isOnScreen
            )
            items.append(item)
        }

        // 从右向左物理坐标排序
        items.sort { $0.nativeFrame.maxX > $1.nativeFrame.maxX }
        return items
    }

    // MARK: - 真实身份与 Bundle 解析

    private static func resolveIdentity(
        for info: Bridging.WindowDescriptor,
        app: NSRunningApplication?,
        axEntries: [MenuBarAXResolver.Entry]
    ) -> (title: String, bundleID: String?) {
        let windowTitle = info.title ?? ""

        // 1. 系统核心组件直接按窗口名精准映射
        if let friendlySystemName = systemItemFriendlyName(windowTitle) {
            return (friendlySystemName, "com.apple.controlcenter")
        }

        // 2. 浏览器/Safari 扩展窗口（extension_mole_...）
        if windowTitle.hasPrefix("extension_") {
            return ("浏览器扩展", "com.apple.controlcenter")
        }

        // 3. 优先通过 AX 空间坐标表映射回真实的第三方应用
        if let axEntry = MenuBarAXResolver.resolveApp(forFrame: info.frame, in: axEntries) {
            let title = (axEntry.title?.isEmpty == false ? axEntry.title : nil)
                ?? (axEntry.description?.isEmpty == false ? axEntry.description : nil)
                ?? axEntry.appName
            return (title, axEntry.bundleIdentifier)
        }

        // 4. 次选：通过 WindowServer 标题中的 Bundle ID 反查
        if windowTitle.hasPrefix("com.") || windowTitle.hasPrefix("org.") || windowTitle.hasPrefix("io.") || windowTitle.hasPrefix("net.") {
            let locName = localizedAppName(forBundleID: windowTitle) ?? windowTitle
            return (locName, windowTitle)
        }

        // 5. 归属进程本地化名兜底（排除控制中心宿主名）
        if let appName = app?.localizedName, !appName.isEmpty, appName != "ControlCenter", appName != "控制中心" {
            return (appName, app?.bundleIdentifier)
        }

        if !windowTitle.isEmpty && windowTitle != "Item-0" {
            return (windowTitle, app?.bundleIdentifier)
        }

        return ("菜单栏项", app?.bundleIdentifier)
    }

    private static func systemItemFriendlyName(_ name: String) -> String? {
        switch name {
        case "Clock": return "时钟"
        case "Battery": return "电池"
        case "BentoBox", "BentoBox-0", "ControlCenter": return "控制中心"
        case "WiFi", "AirPort": return "Wi-Fi"
        case "Sound", "Volume": return "声音"
        case "Bluetooth": return "蓝牙"
        case "NowPlaying": return "正在播放"
        case "FocusModes", "DoNotDisturb": return "专注模式"
        case "Shortcuts": return "快捷指令"
        case "Display": return "显示器"
        case "ScreenMirroring": return "屏幕镜像"
        case "MusicRecognition", "Shazam": return "音乐识别"
        case "Hearing": return "听觉"
        case "Accessibility": return "辅助功能"
        case "User", "Users": return "快速用户切换"
        case "apple.passwords": return "密码"
        default:
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
