import Foundation
import CoreGraphics
import AppKit

/// 基于私有 SkyLight API 的菜单栏极速扫描器（微秒级窗口枚举与几何解析）
public actor MenuBarWindowScanner {
    public static let shared = MenuBarWindowScanner()

    private init() {}

    /// 记忆已确认的第三方窗口真实身份（按 windowID 维护生命周期，防切屏时差瞬态丢失）
    private var confirmedIdentities: [CGWindowID: (title: String, bundleID: String, sourcePID: pid_t?)] = [:]

    /// 扫描指定屏幕上的全部菜单栏项（全流程 < 2ms）
    public func scanMenuBarItems(for geometry: NotchGeometry) async -> [MenuBarItem] {
        let windowIDs = Bridging.menuBarWindowIDs()
        let screenBounds = CGDisplayBounds(geometry.displayID)
        
        // 依据 ADR 0017 单前台活动屏独占公理：
        // AX 全局条目池仅在活动菜单栏屏有效且匹配其坐标；
        // 非活动屏直接传入空数组，走 kCGWindowName 镜像判据映射 Bundle ID，杜绝空间坐标跨屏错配。
        let isActiveDisplay = await MainActor.run {
            ScreenManager.shared.currentGeometry.displayID == geometry.displayID
        }
        let axEntries = isActiveDisplay ? await MenuBarAXResolver.shared.latestEntries() : []
        
        // 单次批量获取所有窗口描述，消除循环内 30 余次单独 IPC 调用 (Issue #52)
        let descriptors = Bridging.windowDescriptors(for: windowIDs)
        
        var items: [MenuBarItem] = []

        for windowID in windowIDs {
            guard let info = descriptors[windowID] else { continue }
            guard info.layer == kCGStatusWindowLevel else { continue }
            guard info.frame.intersects(screenBounds) else { continue }
            guard info.frame.width > 2 && info.frame.height > 2 else { continue }
            guard info.frame.width < screenBounds.width * 0.85 else { continue }

            await MenuBarAXResolver.shared.registerCandidatePID(info.ownerPID)
            let app = NSRunningApplication(processIdentifier: info.ownerPID)
            let identity = resolveIdentity(
                for: info,
                app: app,
                axEntries: axEntries
            )

            // 若本次成功解析出可信的应用身份，更新稳定记忆
            if let bundleID = identity.bundleID, !bundleID.isEmpty, identity.title != "菜单栏项" {
                confirmedIdentities[info.windowID] = (identity.title, bundleID, identity.sourcePID)
            }

            let item = MenuBarItem(
                windowID: info.windowID,
                processIdentifier: info.ownerPID,
                sourcePID: identity.sourcePID,
                bundleIdentifier: identity.bundleID,
                title: identity.title,
                nativeFrame: info.frame,
                displayMode: .nativeVisible,
                capability: .standardAXPress,
                isOnScreen: info.isOnScreen,
                displayID: geometry.displayID
            )
            items.append(item)
        }

        // 清理已销毁窗口的历史身份记录（仅在有效窗口列表稳定就绪时清理）
        let validIDs = Set(descriptors.keys)
        if validIDs.count >= 5 {
            confirmedIdentities = confirmedIdentities.filter { validIDs.contains($0.key) }
        }

        // 从右向左物理坐标排序
        items.sort { $0.nativeFrame.maxX > $1.nativeFrame.maxX }
        return items
    }

    // MARK: - 真实身份与 Bundle 解析

    private func resolveIdentity(
        for info: Bridging.WindowDescriptor,
        app: NSRunningApplication?,
        axEntries: [MenuBarAXResolver.Entry]
    ) -> (title: String, bundleID: String?, sourcePID: pid_t?) {
        let windowTitle = info.title ?? ""

        // 1. 系统核心组件：按窗口名精准映射，并派生**各自独立**的图元键。
        //    严禁统一返回 com.apple.controlcenter —— 那会让时钟/电池/Wi-Fi/声音等全部共享
        //    appAssetVault 的同一个槽位而互相覆盖，非激活屏回退取图时张冠李戴。
        if let friendlySystemName = Self.systemItemFriendlyName(windowTitle) {
            return (friendlySystemName, "com.apple.controlcenter.\(windowTitle)", nil)
        }

        // 2. 浏览器/Safari 扩展窗口（extension_mole_...）：每个扩展独立成键
        if windowTitle.hasPrefix("extension_") {
            return ("浏览器扩展", "com.apple.controlcenter.\(windowTitle)", nil)
        }

        // 3. 实名原生反查（非活动屏与原生保留项 100% 确定性命中，零模糊匹配误差）
        let looksLikeBundleID = (windowTitle.hasPrefix("com.") || windowTitle.hasPrefix("org.") || windowTitle.hasPrefix("io.") || windowTitle.hasPrefix("net.") || windowTitle.contains(".")) && !windowTitle.contains(" ") && !windowTitle.hasPrefix("Item-")
        if looksLikeBundleID {
            let locName = Self.localizedAppName(forBundleID: windowTitle) ?? windowTitle
            let resolvedPID = NSRunningApplication
                .runningApplications(withBundleIdentifier: windowTitle)
                .first { !$0.isTerminated }?
                .processIdentifier
            return (locName, windowTitle, resolvedPID)
        }

        // 4. 活动屏匿名项（Item-0）：优先通过 AX 空间坐标表映射回真实的第三方应用
        if windowTitle == "Item-0" {
            if let axEntry = MenuBarAXResolver.resolveApp(forFrame: info.frame, in: axEntries) {
                let title = (axEntry.title?.isEmpty == false ? axEntry.title : nil)
                    ?? (axEntry.description?.isEmpty == false ? axEntry.description : nil)
                    ?? axEntry.appName
                return (title, axEntry.bundleIdentifier, axEntry.processIdentifier)
            }
            // 切屏瞬态 AX 条目未命中：优先从本屏稳定记忆继承真实身份，杜绝毫秒级退化为“菜单栏项”
            if let confirmed = confirmedIdentities[info.windowID] {
                return (confirmed.title, confirmed.bundleID, confirmed.sourcePID)
            }
        }

        // 5. 归属进程本地化名兜底：能走到此处说明 owner 并非控制中心宿主，其 bundleID 与 pid 可信
        if let appName = app?.localizedName, !appName.isEmpty, appName != "ControlCenter", appName != "控制中心" {
            return (appName, app?.bundleIdentifier, app?.processIdentifier)
        }

        // 6. 稳定身份回退防御：若窗口为其它形式但此前已有确认身份，继承之
        if let confirmed = confirmedIdentities[info.windowID] {
            return (confirmed.title, confirmed.bundleID, confirmed.sourcePID)
        }

        // 7. 无法确定归属应用：绝不冒用控制中心的 bundleID（会造成图元槽位互相覆盖），
        //    留空令 persistentKey 回退到 title / windowID 分支，天然唯一
        if !windowTitle.isEmpty && windowTitle != "Item-0" {
            return (windowTitle, nil, nil)
        }

        return ("菜单栏项", nil, nil)
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
