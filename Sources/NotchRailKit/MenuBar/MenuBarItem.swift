import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

/// 表示单一菜单栏项模型
public struct MenuBarItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 菜单栏项窗口 ID（窗口枚举路径的主键；AX 路径为 0）
    public let windowID: CGWindowID
    /// 窗口的 owner 进程（状态项窗口恒为控制中心宿主）
    ///
    /// 该值**同时是事件派发的唯一正确目标**：状态项窗口归宿主所有，投给真实应用进程时，
    /// 其进程内不存在该 windowID 对应的窗口，AppKit 无从路由，事件被静默丢弃。
    public let processIdentifier: pid_t
    /// 经 AXExtrasMenuBar 空间配对解析出的**真实归属应用 PID**
    ///
    /// 仅供图元归属、AX 元素定位、界面展示等场景使用，**不参与点击派发**（原因见 `clickTargetPID`）。
    /// 为 nil 表示该窗口未能配到任何真实应用（如系统原生项由控制中心代管、或 AX 权限不足）。
    public let sourcePID: pid_t?
    public let bundleIdentifier: String?
    public let title: String?
    public let axIdentifier: String?
    public let axRole: String?
    public let axSubrole: String?
    public var nativeFrame: CGRect
    public var displayMode: DisplayMode
    public var capability: InteractionCapability
    public var isUnresponsive: Bool
    public var isOnScreen: Bool
    /// 跨扫描周期的稳定持久化缓存键（优先 Bundle ID，若缺失则以 windowID 严格物理隔离，绝不共享通用 key）
    public var persistentKey: String {
        if let bundleID = bundleIdentifier, !bundleID.isEmpty {
            return "\(bundleID):\(axIdentifier ?? title ?? "default")"
        } else if let axID = axIdentifier, !axID.isEmpty {
            return "ax:\(axID)"
        } else if let t = title, !t.isEmpty, t != "菜单栏项", t != "Item-0" {
            return "title:\(t)"
        } else {
            return "win:\(windowID)"
        }
    }

    /// 图标缓存键（以 windowID 为主键，确保跨扫描周期和 AX 解析前后绝对稳定）
    public var iconCacheKey: String {
        if windowID != 0 {
            return "win_\(windowID)"
        } else {
            return "\(persistentKey)"
        }
    }
    
    /// 统一偏好与排序唯一标识键（优先 Bundle ID，回退持久化键）
    public var preferenceKey: String {
        bundleIdentifier ?? persistentKey
    }
    
    /// 事件派发的目标进程（唯一事实来源）
    ///
    /// **恒取状态项窗口的 owner**（`processIdentifier`）。
    ///
    /// 历史实现优先取 `sourcePID`（AX 反查出的真实应用），真机实测该优先级是**错的**：
    /// 状态项窗口恒归控制中心宿主所有，把事件投给真实应用进程时，该进程内并不存在该
    /// `windowID` 对应的窗口，AppKit 无从路由，事件被静默丢弃 —— 表现即「第三方图标点了没反应」。
    /// 投给窗口 owner 后，由宿主完成菜单栏项激活并把动作转交真实应用；
    /// 实测对隐藏项（`isOnScreen == false`，即被刘海挤占的那些）同样生效。
    public var clickTargetPID: pid_t {
        processIdentifier
    }
    
    /// 生成基于 customItemOrder 排序规则的纯函数比较器
    public static func comparator(for order: [String]) -> (MenuBarItem, MenuBarItem) -> Bool {
        return { a, b in
            guard !order.isEmpty else { return false }
            let keyA = a.preferenceKey
            let keyB = b.preferenceKey
            let idxA = order.firstIndex(of: keyA) ?? (a.bundleIdentifier.flatMap { order.firstIndex(of: $0) })
            let idxB = order.firstIndex(of: keyB) ?? (b.bundleIdentifier.flatMap { order.firstIndex(of: $0) })
            
            switch (idxA, idxB) {
            case let (.some(iA), .some(iB)):
                return iA < iB
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return false
            }
        }
    }
    
    public enum DisplayMode: String, Codable, Sendable {
        case nativeVisible   // 在原生菜单栏仍清晰可见
        case overflowed      // 因刘海遮挡或空间不足被挤出
    }
    
    public enum InteractionCapability: String, Codable, Sendable {
        case standardAXPress // 支持标准 AXPress 触发原生下拉
        case unsupported     // 不支持直接 AX 触发
    }
    
    /// 根据 windowID 与 pid 生成跨扫描确定性 UUID
    public static func deterministicUUID(for windowID: CGWindowID, pid: pid_t) -> UUID {
        if windowID != 0 {
            var bytes: [UInt8] = [0x4E, 0x6F, 0x74, 0x63, 0x68, 0x52, 0x61, 0x69, 0x6C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            withUnsafeBytes(of: windowID.bigEndian) { raw in
                for (i, b) in raw.enumerated() {
                    bytes[12 + i] = b
                }
            }
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        } else {
            return UUID()
        }
    }
    
    public init(
        id: UUID? = nil,
        windowID: CGWindowID = 0,
        processIdentifier: pid_t,
        sourcePID: pid_t? = nil,
        bundleIdentifier: String?,
        title: String?,
        axIdentifier: String? = nil,
        axRole: String? = nil,
        axSubrole: String? = nil,
        nativeFrame: CGRect,
        displayMode: DisplayMode = .nativeVisible,
        capability: InteractionCapability = .standardAXPress,
        isUnresponsive: Bool = false,
        isOnScreen: Bool = true
    ) {
        self.id = id ?? Self.deterministicUUID(for: windowID, pid: processIdentifier)
        self.windowID = windowID
        self.processIdentifier = processIdentifier
        self.sourcePID = sourcePID
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.axIdentifier = axIdentifier
        self.axRole = axRole
        self.axSubrole = axSubrole
        self.nativeFrame = nativeFrame
        self.displayMode = displayMode
        self.capability = capability
        self.isUnresponsive = isUnresponsive
        self.isOnScreen = isOnScreen
    }
}
