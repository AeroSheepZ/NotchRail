import Foundation
import CoreGraphics

/// 点击派发错误类型
public enum ClickError: Error, Sendable {
    case invalidWindow      // 缺少有效 windowID（非窗口枚举路径）
    case frameUnavailable   // 无法获取窗口实时 frame
    case eventCreationFailed
}

/// 按 windowID 对真实菜单栏窗口合成点击的交互执行器（替代 AXPress）
///
/// 被动溢出场景下，图标窗口仍在菜单栏中（只是被刘海遮住），
/// 直接按 windowID 合成鼠标事件并派发到目标进程即可触发原生下拉菜单，
/// 无需移动窗口、无需 AX 树遍历。
public actor MenuBarItemClicker {
    public static let shared = MenuBarItemClicker()

    private init() {}

    /// 对指定菜单栏项合成一次原生点击
    @discardableResult
    public func performClick(for item: MenuBarItem) async -> Result<Void, ClickError> {
        guard item.windowID != 0 else {
            return .failure(.invalidWindow)
        }
        // 用窗口实时 frame 计算点击中心（窗口坐标可能已变化）
        guard let frame = Bridging.frame(for: item.windowID) else {
            return .failure(.frameUnavailable)
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return .failure(.eventCreationFailed)
        }
        guard
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
        else {
            return .failure(.eventCreationFailed)
        }

        let pid = item.processIdentifier
        let windowID = item.windowID
        for event in [down, up] {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
            event.setIntegerValueField(CGEventField.menuBarItemWindowID, value: Int64(windowID))
        }
        down.setIntegerValueField(.mouseEventClickState, value: 1)

        down.postToPid(pid)
        usleep(20_000) // 20ms 按下间隔
        up.postToPid(pid)

        return .success(())
    }
}

private extension CGEventField {
    /// 事件携带的目标窗口 ID（私有字段 0x33，用于路由到指定菜单栏窗口）
    static let menuBarItemWindowID = CGEventField(rawValue: 0x33)!
}
