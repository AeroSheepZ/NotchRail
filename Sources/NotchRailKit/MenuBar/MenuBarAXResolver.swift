import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

public actor MenuBarAXResolver {
    public static let shared = MenuBarAXResolver()

    public struct Entry: Sendable {
        public let appName: String
        public let bundleIdentifier: String?
        public let title: String?
        public let description: String?
        public let position: CGPoint
        public let size: CGSize
    }

    private var cachedEntries: [Entry] = []
    private var lastScanDate: Date?

    private init() {}

    /// 获取最新的所有运行应用的菜单栏 Extra 空间映射表（带 2 秒缓存）
    public func latestEntries() -> [Entry] {
        if let last = lastScanDate, Date().timeIntervalSince(last) < 2.0, !cachedEntries.isEmpty {
            return cachedEntries
        }
        let entries = Self.performAXScan()
        self.cachedEntries = entries
        self.lastScanDate = Date()
        return entries
    }

    /// 空间坐标匹配（X 坐标相差 <= tolerance 且 Y 坐标在状态栏范围）
    public static func resolveApp(forFrame frame: CGRect, in entries: [Entry], tolerance: CGFloat = 6.0) -> Entry? {
        var best: (entry: Entry, distance: CGFloat)?
        for entry in entries {
            let distance = abs(entry.position.x - frame.minX)
            if distance <= tolerance, best == nil || distance < best!.distance {
                best = (entry, distance)
            }
        }
        return best?.entry
    }

    /// 遍历系统运行的所有应用程序，提取其状态栏菜单项的真实身份与坐标
    private static func performAXScan() -> [Entry] {
        guard AXIsProcessTrusted() else { return [] }

        let apps = NSWorkspace.shared.runningApplications
        var entries: [Entry] = []

        for app in apps {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var extras: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &extras) == .success,
                  let extrasElem = extras,
                  CFGetTypeID(extrasElem) == AXUIElementGetTypeID()
            else {
                continue
            }
            let extrasUIElem = extrasElem as! AXUIElement

            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(extrasUIElem, "AXChildren" as CFString, &children) == .success,
                  let childrenArr = children as? [AXUIElement]
            else {
                continue
            }

            for child in childrenArr {
                var posVal: CFTypeRef?
                var sizeVal: CFTypeRef?
                var titleVal: CFTypeRef?
                var descVal: CFTypeRef?
                var pt = CGPoint.zero
                var sz = CGSize.zero

                if AXUIElementCopyAttributeValue(child, "AXPosition" as CFString, &posVal) == .success,
                   let posVal, CFGetTypeID(posVal) == AXValueGetTypeID() {
                    AXValueGetValue(posVal as! AXValue, .cgPoint, &pt)
                }

                if AXUIElementCopyAttributeValue(child, "AXSize" as CFString, &sizeVal) == .success,
                   let sizeVal, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
                    AXValueGetValue(sizeVal as! AXValue, .cgSize, &sz)
                }

                AXUIElementCopyAttributeValue(child, "AXTitle" as CFString, &titleVal)
                AXUIElementCopyAttributeValue(child, "AXDescription" as CFString, &descVal)

                let title = titleVal as? String
                let desc = descVal as? String
                let appName = app.localizedName ?? "应用"

                entries.append(Entry(
                    appName: appName,
                    bundleIdentifier: app.bundleIdentifier,
                    title: (title?.isEmpty == false ? title : nil),
                    description: (desc?.isEmpty == false ? desc : nil),
                    position: pt,
                    size: sz
                ))
            }
        }

        return entries
    }
}
