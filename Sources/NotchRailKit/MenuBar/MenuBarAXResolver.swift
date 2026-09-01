import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// 通过辅助功能 API 获取菜单栏项的应用名与屏幕坐标。
///
/// 背景：macOS 13+ 将所有菜单栏窗口的 owner 统一归到「控制中心」进程，
/// 且 `kCGWindowName` 对部分项返回无意义的 "Item-0"。此时窗口枚举无法得知
/// 该项属于哪个应用，需要用 AX 的 `kAXExtrasMenuBarAttribute` 遍历每个应用
/// 的菜单栏 extra，拿到应用名 + 位置，再按坐标与窗口 frame 对齐匹配。
public enum MenuBarAXResolver {

    public struct Entry {
        public let appName: String
        /// 菜单栏项左上角（Quartz 全局坐标，原点在主屏左上角）
        public let position: CGPoint
    }

    /// 遍历所有运行应用的菜单栏 extra，返回 (应用名, 坐标) 列表。
    ///
    /// 需辅助功能权限；未授权时返回空数组（不影响窗口枚举主流程）。
    public static func scanEntries() -> [Entry] {
        guard AXIsProcessTrusted() else { return [] }

        var entries: [Entry] = []
        for app in NSWorkspace.shared.runningApplications {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            guard
                let extras = attribute(element, kAXExtrasMenuBarAttribute),
                let children = attribute(extras as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
            else {
                continue
            }

            for child in children {
                guard let position = position(of: child) else { continue }

                let title = attribute(child, kAXTitleAttribute) as? String
                let description = attribute(child, kAXDescriptionAttribute) as? String

                // 系统项（电池/时钟/控制中心）在 AX 里 title 常为空、description 有值；
                // 第三方项 title/description 常为空，用应用本地化名。
                let name: String
                if let title, !title.isEmpty {
                    name = title
                } else if let description, !description.isEmpty {
                    name = description
                } else {
                    name = app.localizedName ?? "菜单栏项"
                }
                entries.append(Entry(appName: name, position: position))
            }
        }
        return entries
    }

    /// 按 X 坐标匹配最近的菜单栏项名（同一菜单栏项在主/副屏 X 坐标一致，仅 Y 不同）。
    ///
    /// - Parameter frame: 目标窗口 frame（Quartz 坐标）
    /// - Parameter tolerance: 匹配容差（pt），超过则视为无匹配
    public static func resolveName(forFrame frame: CGRect, entries: [Entry], tolerance: CGFloat = 16) -> String? {
        var best: (name: String, distance: CGFloat)?
        for entry in entries {
            let distance = abs(entry.position.x - frame.minX)
            if distance < tolerance, best == nil || distance < best!.distance {
                best = (entry.appName, distance)
            }
        }
        return best?.name
    }

    // MARK: - Private

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func position(of element: AXUIElement) -> CGPoint? {
        guard
            let value = attribute(element, kAXPositionAttribute),
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }
}
