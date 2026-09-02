import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

/// 表示单一菜单栏项模型
public struct MenuBarItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 菜单栏项窗口 ID（窗口枚举路径的主键；AX 路径为 0）
    public let windowID: CGWindowID
    public let processIdentifier: pid_t
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
    
    /// 跨扫描周期的稳定持久化缓存键（基于 Bundle ID、AX 标识符或 Title）
    public var persistentKey: String {
        if let bundleID = bundleIdentifier, !bundleID.isEmpty {
            return "\(bundleID):\(axIdentifier ?? title ?? "default")"
        } else if let axID = axIdentifier, !axID.isEmpty {
            return "ax:\(axID)"
        } else if let t = title, !t.isEmpty {
            return "title:\(t)"
        } else {
            return "pid:\(processIdentifier)"
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
    
    public enum DisplayMode: String, Codable, Sendable {
        case nativeVisible   // 在原生菜单栏仍清晰可见
        case overflowed      // 因刘海遮挡或空间不足被挤出
        case ignored         // 用户配置为忽略
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
