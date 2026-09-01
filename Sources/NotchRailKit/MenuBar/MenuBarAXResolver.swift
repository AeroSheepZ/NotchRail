import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// 通过辅助功能 API 异步获取菜单栏项的应用名与屏幕坐标（带高频内存缓存与后台非阻塞刷新）
public actor MenuBarAXResolver {
    public static let shared = MenuBarAXResolver()

    public struct Entry: Sendable {
        public let appName: String
        /// 菜单栏项左上角（Quartz 全局坐标，原点在主屏左上角）
        public let position: CGPoint
    }

    private var cachedEntries: [Entry] = []
    private var lastScanDate: Date?
    private var isRefreshing: Bool = false

    private init() {
        Task {
            await self.refreshInBackground()
        }
    }

    /// 获取最新的已缓存 AX 条目（0 延迟，绝不阻塞主扫描流）
    public func latestEntries() -> [Entry] {
        let entries = cachedEntries
        let shouldRefresh = (lastScanDate == nil || Date().timeIntervalSince(lastScanDate!) > 20.0) && !isRefreshing

        if shouldRefresh {
            Task {
                await self.refreshInBackground()
            }
        }
        return entries
    }

    /// 触发后台异步刷新
    public func refreshInBackground() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        let entries = await Task.detached(priority: .utility) {
            Self.performAXScan()
        }.value

        self.cachedEntries = entries
        self.lastScanDate = Date()
        self.isRefreshing = false
    }

    /// 遍历所有运行应用的菜单栏 extra，返回 (应用名, 坐标) 列表。
    private static func performAXScan() -> [Entry] {
        guard AXIsProcessTrusted() else { return [] }

        let appsToScan = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .accessory || $0.bundleIdentifier?.contains("controlcenter") == true
        }

        var entries: [Entry] = []
        for app in appsToScan {
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

    /// 按 X 坐标匹配最近的菜单栏项名
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
