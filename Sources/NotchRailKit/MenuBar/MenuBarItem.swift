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

    /// 图标缓存键（persistentKey + windowID 唯一限定）
    ///
    /// 仅 persistentKey 不够唯一：macOS 13+ 系统菜单栏项 owner 统一归控制中心进程，
    /// 窗口名不可得时所有系统项的 persistentKey 相同（键冲突 → 全部渲染成同一图标）。
    /// 追加 windowID（窗口生命周期内稳定、跨扫描周期不变）保证唯一且不闪占位。
    public var iconCacheKey: String {
        "\(persistentKey)#\(windowID)"
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
    
    public init(
        id: UUID = UUID(),
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
        isUnresponsive: Bool = false
    ) {
        self.id = id
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
    }
}
