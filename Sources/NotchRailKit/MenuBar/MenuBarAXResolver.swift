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
    /// 维护已确认拥有菜单栏 Extra 项的增量进程 PID 缓存池 (AGENTS.md 3.4)
    private var knownMenuBarPIDs: Set<pid_t> = []
    private var lastFullDiscoveryDate: Date?

    private init() {}

    /// 获取最新的所有运行应用的菜单栏 Extra 空间映射表（带 2 秒缓存）
    public func latestEntries() -> [Entry] {
        if let last = lastScanDate, Date().timeIntervalSince(last) < 2.0, !cachedEntries.isEmpty {
            return cachedEntries
        }
        let entries = performAXScan()
        self.cachedEntries = entries
        self.lastScanDate = Date()
        return entries
    }

    /// 注册潜在的菜单栏窗口拥有进程 PID（如窗口扫描中发现的 ownerPID）
    public func registerCandidatePID(_ pid: pid_t) {
        if pid != getpid() && pid != 0 {
            knownMenuBarPIDs.insert(pid)
        }
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

    /// 提取系统运行应用的菜单栏真实身份与坐标（增量毫秒级扫描）
    private func performAXScan() -> [Entry] {
        guard AXIsProcessTrusted() else { return [] }

        let ownPID = getpid()
        let now = Date()

        // 1. 若已知池为空，或距上次全量发现超过 60 秒，执行一次带子进程过滤的快速发现
        let shouldRunFullDiscovery = knownMenuBarPIDs.isEmpty ||
            lastFullDiscoveryDate == nil ||
            now.timeIntervalSince(lastFullDiscoveryDate!) > 60.0

        if shouldRunFullDiscovery {
            discoverMenuBarPIDs()
            lastFullDiscoveryDate = now
        }

        // 2. 针对已知池中的 PID 执行增量极速扫描 (< 5ms)
        var entries: [Entry] = []
        var deadPIDs: Set<pid_t> = []

        for pid in knownMenuBarPIDs {
            guard pid != ownPID else { continue }
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
                deadPIDs.insert(pid)
                continue
            }

            let appEntries = scanAppExtras(app: app, pid: pid)
            entries.append(contentsOf: appEntries)
        }

        // 清理已退出的进程
        if !deadPIDs.isEmpty {
            knownMenuBarPIDs.subtract(deadPIDs)
        }

        return entries
    }

    /// 快速发现候选有状态栏的进程（严格过滤 WebKit / Renderer 等高延迟子进程及自身）
    private func discoverMenuBarPIDs() {
        let ownPID = getpid()
        let apps = NSWorkspace.shared.runningApplications

        for app in apps {
            let pid = app.processIdentifier
            guard pid != ownPID, !app.isTerminated else { continue }
            
            // 过滤已知高延迟子进程 (AGENTS.md 3.4)
            if let bundleID = app.bundleIdentifier?.lowercased() {
                if bundleID.contains("webkit") ||
                   bundleID.contains("renderer") ||
                   bundleID.contains("helper") ||
                   bundleID.contains("gpu") {
                    continue
                }
            }

            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.05)
            var extras: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &extras) == .success,
               let extrasElem = extras,
               CFGetTypeID(extrasElem) == AXUIElementGetTypeID() {
                knownMenuBarPIDs.insert(pid)
            }
        }
    }

    /// 扫描单个应用的 AXExtrasMenuBar 项（带严格 80ms 超时）
    private func scanAppExtras(app: NSRunningApplication, pid: pid_t) -> [Entry] {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.08)

        var extras: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &extras) == .success,
              let extrasElem = extras,
              CFGetTypeID(extrasElem) == AXUIElementGetTypeID()
        else {
            return []
        }

        let extrasUIElem = extrasElem as! AXUIElement
        AXUIElementSetMessagingTimeout(extrasUIElem, 0.08)

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(extrasUIElem, "AXChildren" as CFString, &children) == .success,
              let childrenArr = children as? [AXUIElement]
        else {
            return []
        }

        var results: [Entry] = []
        for child in childrenArr {
            AXUIElementSetMessagingTimeout(child, 0.05)
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

            results.append(Entry(
                appName: appName,
                bundleIdentifier: app.bundleIdentifier,
                title: (title?.isEmpty == false ? title : nil),
                description: (desc?.isEmpty == false ? desc : nil),
                position: pt,
                size: sz
            ))
        }

        return results
    }
}
