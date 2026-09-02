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
                title: Self.displayName(for: info, app: app),
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

    // MARK: - 名称与 Bundle 解析

    private static func resolveBundleIdentifier(for info: Bridging.WindowDescriptor, app: NSRunningApplication?) -> String? {
        if let appBundle = app?.bundleIdentifier, !appBundle.isEmpty {
            return appBundle
        }
        if let name = info.title, name.hasPrefix("com.") || name.hasPrefix("org.") || name.hasPrefix("io.") || name.hasPrefix("net.") {
            return name
        }
        return nil
    }

    private static func displayName(
        for info: Bridging.WindowDescriptor,
        app: NSRunningApplication?
    ) -> String {
        let bundleID = app?.bundleIdentifier ?? ""
        let isSystemControlCenter = bundleID == "com.apple.controlcenter" || bundleID == "com.apple.systemuiserver"

        // 1. 系统控制中心各项（时钟、电池、WiFi、声音等）
        if isSystemControlCenter {
            if let windowName = info.title, !windowName.isEmpty {
                if let friendly = systemItemFriendlyName(windowName) {
                    return friendly
                }
            }
            if let axName = MenuBarAXResolver.resolveName(forPID: info.ownerPID, frame: info.frame) {
                if let friendly = systemItemFriendlyName(axName) {
                    return friendly
                }
                return axName
            }
            return "控制中心"
        }

        // 2. 第三方应用：100% 绑定其实际归属进程本地化名称（杜绝跨进程错乱）
        if let appName = app?.localizedName, !appName.isEmpty {
            return appName
        }

        // 3. 次选：通过 Bundle Identifier 反查本地化名称
        if let windowName = info.title, !windowName.isEmpty {
            if windowName.hasPrefix("com.") || windowName.hasPrefix("org.") || windowName.hasPrefix("io.") || windowName.hasPrefix("net.") {
                if let locName = localizedAppName(forBundleID: windowName) {
                    return locName
                }
            }
            if let friendly = systemItemFriendlyName(windowName) {
                return friendly
            }
            if windowName != "Item-0" && !windowName.contains(".") {
                return windowName
            }
        }

        // 4. 进程名兜底
        if let ownerName = info.ownerName, !ownerName.isEmpty {
            return ownerName
        }

        return "菜单栏项"
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
