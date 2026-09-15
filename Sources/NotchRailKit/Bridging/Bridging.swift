import Foundation
import CoreGraphics

/// 窗口服务器连接标识（SkyLight 私有类型）
public typealias CGSConnectionID = Int32

// MARK: - 私有 SkyLight API 声明
//
// 这些是 macOS 窗口服务器的非公开 API，通过 @_silgen_name 直接链接 C 符号。
// 集中于本文件隔离，便于将来 macOS 升级时做版本兼容与降级。

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetWindowCount")
func CGSGetWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
func CGSGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
func CGSGetScreenRectForWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outRect: inout CGRect
) -> CGError

// MARK: - 窗口枚举与几何查询

/// 底层窗口服务器桥接：菜单栏项本质上是 status window，可直接按窗口枚举，
/// 无需 AX 树遍历，零权限、坐标精确。
public enum Bridging {

    /// 单个窗口的描述信息（几何 + 归属进程，均无需屏幕录制权限；
    /// 仅 `title` 在未授权屏幕录制时可能为空）
    public struct WindowDescriptor {
        public let windowID: CGWindowID
        public let frame: CGRect
        public let ownerPID: pid_t
        public let ownerName: String?
        public let title: String?
        public let layer: Int
        public let isOnScreen: Bool
    }

    /// 枚举当前菜单栏项窗口 ID 列表（含所有 Space 上的菜单栏窗口）
    public static func menuBarWindowIDs() -> [CGWindowID] {
        let cid = CGSMainConnectionID()

        var count: Int32 = 0
        guard CGSGetWindowCount(cid, 0, &count) == .success, count > 0 else {
            return []
        }

        var list = [CGWindowID](repeating: 0, count: Int(count))
        var realCount: Int32 = 0
        guard CGSGetProcessMenuBarWindowList(cid, 0, count, &list, &realCount) == .success else {
            return []
        }
        return Array(list[..<Int(realCount)])
    }

    /// 用公共 API 枚举全部菜单栏窗口（layer == kCGStatusWindowLevel）。
    ///
    /// 相比私有 `CGSGetProcessMenuBarWindowList`：能拿到**完整**列表（不遗漏屏幕右侧窗口），
    /// 且 `kCGWindowName` 对第三方应用返回其 **bundle identifier**（如 com.raycast.macos），
    /// 对系统项返回 "Clock"/"Battery"/"BentoBox-0" 等，可用于反查真实应用名。
    /// 代价：窗口名在未授权屏幕录制时可能为空（仅名称字段受影响，窗口本身仍可枚举）。
    public static func menuBarWindowDescriptors() -> [WindowDescriptor] {
        let opts = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: [WindowDescriptor] = []
        for dict in list {
            let layer = dict[kCGWindowLayer as String] as? Int ?? 0
            guard layer == kCGStatusWindowLevel else { continue }

            let frame: CGRect = {
                guard
                    let bounds = dict[kCGWindowBounds as String] as? NSDictionary,
                    let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
                else { return .zero }
                return rect
            }()

            let windowID = (dict[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            let ownerPID = (dict[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0

            result.append(WindowDescriptor(
                windowID: windowID,
                frame: frame,
                ownerPID: ownerPID,
                ownerName: dict[kCGWindowOwnerName as String] as? String,
                title: dict[kCGWindowName as String] as? String,
                layer: layer,
                isOnScreen: dict[kCGWindowIsOnscreen as String] as? Bool ?? false
            ))
        }
        return result
    }

    /// 枚举当前**弹出的菜单层窗口**（`kCGPopUpMenuWindowLevel`）→ 归属进程
    ///
    /// 用途：辅助点击派发后，以「观察窗内是否新出现菜单层窗口」判定目标应用**是否给出响应**
    /// （弹出菜单即视为有对应辅助处理；无菜单则交由调用方给出抖动反馈）。
    ///
    /// 只取菜单层可天然滤除主要噪声：菜单栏项自身的布局扰动（`kCGStatusWindowLevel`）——
    /// 实测每次点击后宿主都会因 `AudioVideoModule` 等状态项进出而新建 48pt 宽的窗口，
    /// 若一并计入会永远判成「有响应」。
    public static func popUpMenuWindowOwners() -> [CGWindowID: pid_t] {
        let opts = CGWindowListOption([.optionAll, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        var result: [CGWindowID: pid_t] = [:]
        for dict in list {
            guard (dict[kCGWindowLayer as String] as? Int) == menuLevel else { continue }
            let windowID = (dict[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            let ownerPID = (dict[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            result[windowID] = ownerPID
        }
        return result
    }

    /// 获取指定窗口的实时 frame（屏幕坐标，原点在屏幕左上角）
    public static func frame(for windowID: CGWindowID) -> CGRect? {
        var rect = CGRect.zero
        guard CGSGetScreenRectForWindow(CGSMainConnectionID(), windowID, &rect) == .success else {
            return nil
        }
        return rect
    }

    /// 获取指定窗口的详细描述（几何 / 归属 / 标题 / 层级）
    public static func windowDescriptor(for windowID: CGWindowID) -> WindowDescriptor? {
        return windowDescriptors(for: [windowID])[windowID]
    }

    /// 批量获取多个窗口的详细描述（单次批量 IPC，消除循环内 30 余次单独 C 系统调用，Issue #52）
    public static func windowDescriptors(for windowIDs: [CGWindowID]) -> [CGWindowID: WindowDescriptor] {
        guard !windowIDs.isEmpty else { return [:] }
        let count = windowIDs.count
        let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
        defer { pointer.deallocate() }
        for (i, wid) in windowIDs.enumerated() {
            pointer[i] = UnsafeRawPointer(bitPattern: UInt(wid))
        }
        guard
            let array = CFArrayCreate(kCFAllocatorDefault, pointer, count, nil),
            let list = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]]
        else {
            return [:]
        }

        var result: [CGWindowID: WindowDescriptor] = [:]
        result.reserveCapacity(list.count)

        for dict in list {
            guard let widNum = dict[kCGWindowNumber as String] as? NSNumber else { continue }
            let wid = CGWindowID(widNum.uint32Value)
            let frame: CGRect = {
                guard
                    let bounds = dict[kCGWindowBounds as String] as? NSDictionary,
                    let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
                else { return .zero }
                return rect
            }()
            let desc = WindowDescriptor(
                windowID: wid,
                frame: frame,
                ownerPID: dict[kCGWindowOwnerPID as String] as? pid_t ?? 0,
                ownerName: dict[kCGWindowOwnerName as String] as? String,
                title: dict[kCGWindowName as String] as? String,
                layer: dict[kCGWindowLayer as String] as? Int ?? 0,
                isOnScreen: dict[kCGWindowIsOnscreen as String] as? Bool ?? false
            )
            result[wid] = desc
        }
        return result
    }

    /// 按窗口 ID 截取窗口自身内容（即使被遮挡或 offscreen 也能截到窗口内容）
    ///
    /// 刻意使用 CGWindowList 系列而非 ScreenCaptureKit：SCK 的 SCContentFilter
    /// 是 display-bounded 的，对负坐标离屏菜单栏项会返回 -3812/-3811 错误，
    /// CGWindowList 是 macOS 26 上唯一可捕获 status window 的公共路径。
    /// deprecated 警告由 cgWindowListCreateImage 的自管理声明屏蔽。
    public static func captureWindow(_ windowID: CGWindowID, screenBounds: CGRect? = nil) -> CGImage? {
        let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        pointer[0] = UnsafeRawPointer(bitPattern: UInt(windowID))
        guard let windowArray = CFArrayCreate(kCFAllocatorDefault, pointer, 1, nil) else {
            return nil
        }
        return cgWindowListCreateImage(
            screenBounds ?? .null,
            windowArray,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }

    /// 合成截取多个窗口（一次系统调用，按数组顺序前至后合成）
    ///
    /// - Parameters:
    ///   - windowIDs: 要截取的窗口 ID 列表
    ///   - screenBounds: 截取的屏幕区域（通常为所有窗口 frame 的并集）
    /// - Returns: 合成图；任一环节失败返回 nil
    public static func captureComposite(windowIDs: [CGWindowID], screenBounds: CGRect) -> CGImage? {        guard !windowIDs.isEmpty, !screenBounds.isNull else { return nil }

        let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: windowIDs.count)
        defer { pointer.deallocate() }
        for (index, windowID) in windowIDs.enumerated() {
            pointer[index] = UnsafeRawPointer(bitPattern: UInt(windowID))
        }
        guard let windowArray = CFArrayCreate(kCFAllocatorDefault, pointer, windowIDs.count, nil) else {
            return nil
        }
        return cgWindowListCreateImage(
            screenBounds,
            windowArray,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }

    /// 按屏幕区域截取**合成后**的桌面内容（含菜单、面板、状态项等所有可见层）
    ///
    /// 与 `captureWindow` 的差异：后者截的是单个窗口自身内容，本方法截的是该区域
    /// **屏幕上真实呈现的样子**，用于人工取证「某次点击之后画面上到底出现了什么」。
    /// 同样以 `@_silgen_name` 自管理符号声明屏蔽 SDK 的弃用标注。
    public static func captureRegion(_ rect: CGRect, onScreenOnly: Bool = true) -> CGImage? {
        cgWindowListCreateRegionImage(
            rect,
            onScreenOnly ? .optionOnScreenOnly : .optionAll,
            kCGNullWindowID,
            [.bestResolution]
        )
    }

    /// CGWindowListCreateImageFromArray 的自管理符号声明
    ///
    /// SDK 自 macOS 14 起将该 API 标记弃用（推荐 ScreenCaptureKit），但符号
    /// 在运行时始终存在（deprecated ≠ removed），且 SCK 无法捕获负坐标的
    /// 离屏菜单栏项，此 API 仍是唯一可行路径。自管理声明不携带弃用标注，
    /// 编译器不再发出 deprecated 警告；未来若迁移 SCK，改动集中于此。
    /// 参数类型与 clang importer 对该 C 原型生成的签名完全一致，ABI 安全。
    @_silgen_name("CGWindowListCreateImageFromArray")
    private static func cgWindowListCreateImage(
        _ screenBounds: CGRect,
        _ windowArray: CFArray,
        _ imageOption: CGWindowImageOption
    ) -> CGImage?

    /// CGWindowListCreateImage 的自管理符号声明（理由同 `cgWindowListCreateImage`）
    @_silgen_name("CGWindowListCreateImage")
    private static func cgWindowListCreateRegionImage(
        _ screenBounds: CGRect,
        _ listOption: CGWindowListOption,
        _ windowID: CGWindowID,
        _ imageOption: CGWindowImageOption
    ) -> CGImage?
}
