import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

public actor MenuBarAXResolver {
    public static let shared = MenuBarAXResolver()

    public struct Entry: Sendable {
        /// 该 Extra 菜单栏项的真实归属进程 PID（持有 AXExtrasMenuBar 的应用本身）
        ///
        /// 状态项窗口的 owner 恒为控制中心宿主，**绝不能**用窗口 ownerPID 作为事件投递目标；
        /// 此处的 pid 是事件派发的唯一正确目标（见 `MenuBarItem.sourcePID`）。
        public let processIdentifier: pid_t
        public let appName: String
        public let bundleIdentifier: String?
        public let title: String?
        public let description: String?
        public let position: CGPoint
        public let size: CGSize
    }

    /// 空间映射缓存有效期（Issue #52：延长至 60 秒以上，由进程生命周期事件定向失效）
    private static let MAPPING_CACHE_TTL: TimeInterval = 60.0

    private var cachedEntries: [Entry] = []
    private var lastScanDate: Date?
    /// 维护已确认拥有菜单栏 Extra 项的增量进程 PID 缓存池 (AGENTS.md 3.4)
    private var knownMenuBarPIDs: Set<pid_t> = []

    private init() {}

    /// 获取最新的所有运行应用的菜单栏 Extra 空间映射表
    ///
    /// 命中契约：缓存在 `MAPPING_CACHE_TTL` 内且非空即直出；进程启动 / 退出 / 窗口扫描发现新
    /// ownerPID 时由 `invalidateCache()` 定向失效，因此稳态下不再随心跳周期重复执行 AX 全表遍历 (Issue #52)。
    public func latestEntries() -> [Entry] {
        if let last = lastScanDate, Date().timeIntervalSince(last) < Self.MAPPING_CACHE_TTL, !cachedEntries.isEmpty {
            return cachedEntries
        }
        let entries = performAXScan()
        self.cachedEntries = entries
        self.lastScanDate = Date()
        return entries
    }

    /// 强制失效缓存（当有新菜单栏应用启动、退出或被动态注册时触发）
    public func invalidateCache() {
        self.cachedEntries = []
        self.lastScanDate = nil
    }

    /// 注册潜在的菜单栏窗口拥有进程 PID（如窗口扫描中发现的 ownerPID）
    public func registerCandidatePID(_ pid: pid_t) {
        if pid != getpid() && pid != 0 {
            let inserted = knownMenuBarPIDs.insert(pid).inserted
            if inserted {
                invalidateCache()
            }
        }
    }

    /// 响应新应用启动事件：定向探测 AXExtrasMenuBar，命中则增量入池并定向失效缓存 (Issue #52)
    public func handleAppLaunched(app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != getpid(), !app.isTerminated else { return }
        guard app.activationPolicy != .prohibited else { return }

        if let bundleID = app.bundleIdentifier?.lowercased() {
            if bundleID.contains("webkit") ||
               bundleID.contains("renderer") ||
               bundleID.contains("helper") ||
               bundleID.contains("gpu") {
                return
            }
        }

        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.05)
        var extras: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &extras) == .success,
           let extrasElem = extras,
           CFGetTypeID(extrasElem) == AXUIElementGetTypeID() {
            knownMenuBarPIDs.insert(pid)
            invalidateCache()
        }
    }

    /// 响应应用退出事件：即时移出候选池并定向失效缓存 (Issue #52)
    public func handleAppTerminated(pid: pid_t) {
        if knownMenuBarPIDs.remove(pid) != nil {
            invalidateCache()
        }
    }

    /// 空间坐标匹配（水平**中心**相差 <= tolerance）
    ///
    /// ## ✅ 前提已由真机取证（2026-09-14 `--spike`，已授权辅助功能）
    ///
    /// **`AXExtrasMenuBar` 只返回「活动屏」的项** —— 26 条池中，14 条可用条目（微信/UU远程/Clash/
    /// Notion/WorkBuddy/NotchRail/Snipaste/Kiro/天气/拼音/密码/输入法/控制中心×3）**全部落在活动屏**；
    /// 非活动屏只回了 12 条控制中心条目，且**位置全为退化的 `(0,956,0x0)`**（尺寸 0，不可用于匹配）。
    ///
    /// ⇒ **「按屏过滤」被永久否决**：池中本就没有非活动屏的可用数据，过滤只会把仅有的活动屏数据也丢掉。
    /// 非活动屏的身份改由 `MenuBarWindowScanner.resolveIdentity` 的「窗口标题即 Bundle ID」分支（第 4 步）承担。
    ///
    /// ## ⚠️ 比对基准必须是「水平中心」，不能是 `minX`
    ///
    /// 实测 15 个活动屏窗口 × 14 条 AX 条目对照：
    /// - **按 `minX`**：命中 10/15，漏配 5（控制中心占位的 3 项偏 8pt、Snipaste 偏 7pt，均超出容差）；
    /// - **按水平中心**：命中 14/15，且**全部 14 对偏差为 0.0**（完全重合），唯一漏配项在 AX 池中无对应条目。
    ///
    /// 原因是 AX 元素有时只是状态项的**内层内容**（左右各内缩若干 pt，如 Snipaste 的 AX 宽 24 对窗口宽 38），
    /// 此时只有**中心**是不变量。故容差维持 6.0 即可，且比原实现更宽松可靠。
    public static func resolveApp(forFrame frame: CGRect, in entries: [Entry], tolerance: CGFloat = 6.0) -> Entry? {
        var best: (entry: Entry, distance: CGFloat)?
        for entry in entries {
            // 1. 过滤尺寸为 0 的退化条目（非活动屏系统返回的 0x0 假条目）
            guard entry.size.width > 0 && entry.size.height > 0 else { continue }
            // 2. 校验 Y 轴中心差值，杜绝上下多屏排列时发生跨屏 X 轴错位匹配
            let entryMidY = entry.position.y + entry.size.height / 2
            guard abs(entryMidY - frame.midY) <= max(40.0, frame.height * 1.5) else { continue }

            let distance = abs(entry.position.x + entry.size.width / 2 - frame.midX)
            if distance <= tolerance, best == nil || distance < best!.distance {
                best = (entry, distance)
            }
        }
        return best?.entry
    }

    /// 异步提取前台 App 菜单栏在特定屏幕水平范围内的最右端坐标（Quartz 坐标系）
    /// - Parameter screenBounds: 目标屏幕的几何边界（Quartz / Cocoa 水平 X 轴坐标对齐）
    /// - Returns: 若成功探测返回最右侧菜单项的 maxX；若为 Finder、无菜单或探测失败返回安全基准 `screenBounds.minX + NotchGeometry.DEFAULT_APP_MENU_WIDTH`；若前台 App 无效、终止或为自身返回 nil
    public func fetchFrontmostAppMenuMaxX(for screenBounds: CGRect) -> CGFloat? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              !app.isTerminated,
              app.processIdentifier != getpid() else {
            return nil
        }

        let defaultEdge = screenBounds.minX + NotchGeometry.DEFAULT_APP_MENU_WIDTH

        // 访达特殊处理：直接返回安全基准
        if app.bundleIdentifier == "com.apple.finder" {
            return defaultEdge
        }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)

        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBar = menuBarValue,
              CFGetTypeID(menuBar) == AXUIElementGetTypeID() else {
            return defaultEdge
        }

        let menuBarElem = menuBar as! AXUIElement
        AXUIElementSetMessagingTimeout(menuBarElem, 0.1)

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBarElem, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement],
              !children.isEmpty else {
            return defaultEdge
        }

        var maxItemX: CGFloat?

        for child in children {
            AXUIElementSetMessagingTimeout(child, 0.05)
            var posVal: CFTypeRef?
            var sizeVal: CFTypeRef?
            var pt = CGPoint.zero
            var sz = CGSize.zero

            if AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posVal) == .success,
               let posVal, CFGetTypeID(posVal) == AXValueGetTypeID() {
                AXValueGetValue(posVal as! AXValue, .cgPoint, &pt)
            } else {
                continue
            }

            if AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeVal) == .success,
               let sizeVal, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
                AXValueGetValue(sizeVal as! AXValue, .cgSize, &sz)
            } else {
                continue
            }

            let itemMaxX = pt.x + sz.width
            // 判断是否落在该屏幕的水平跨度内（包含 1pt 容差）
            if pt.x >= screenBounds.minX - 1.0 && pt.x < screenBounds.maxX {
                if let currentMax = maxItemX {
                    maxItemX = max(currentMax, itemMaxX)
                } else {
                    maxItemX = itemMaxX
                }
            }
        }

        return maxItemX ?? defaultEdge
    }

    /// 提取系统运行应用的菜单栏真实身份与坐标（增量毫秒级扫描）
    private func performAXScan() -> [Entry] {
        guard AXIsProcessTrusted() else { return [] }

        let ownPID = getpid()

        // 1. 候选池仅在本进程首次扫描（冷启动）时执行一次带子进程过滤的全量发现；
        //    此后完全由 NSWorkspace 启动 / 退出事件与窗口扫描的 registerCandidatePID 增量维护，
        //    彻底移除 60s 定时全系统进程遍历机制 (Issue #52)
        if knownMenuBarPIDs.isEmpty {
            discoverMenuBarPIDs()
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
            // 过滤无 UI 交互能力的后台守护服务（.prohibited 绝无菜单栏 Extra，直接跳过）
            guard app.activationPolicy != .prohibited else { continue }
            
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
            AXUIElementSetMessagingTimeout(element, 0.03)
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
                processIdentifier: pid,
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
