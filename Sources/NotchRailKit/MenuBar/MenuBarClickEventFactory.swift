import ApplicationServices
import CoreGraphics
import Foundation

extension CGEventField {
    /// 事件携带的目标窗口 ID（私有字段 0x33，用于路由到指定菜单栏窗口）
    ///
    /// 该私有字段值是**唯一来源**：生产派发路径（`MenuBarItemClicker`）与诊断派发路径
    /// （`SpikeRunner` 的单边事件采样）一律经 `MenuBarClickEventFactory` 取用，
    /// 绝不可各自复制一份魔法常量。
    static let menuBarItemWindowID = CGEventField(rawValue: 0x33)!
}

/// 合成点击使用的鼠标按键
public enum MenuBarMouseButton: Sendable {
    case left
    case right

    fileprivate var cgButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        }
    }

    /// 事件字段 `kCGMouseEventButtonNumber` 的取值（左 0 / 右 1）
    ///
    /// **必须显式写入事件**：仅靠 `CGEventCreateMouseEvent` 的 `mouseButton` 形参不足以保证该字段落值，
    /// 而目标进程 AppKit 侧的鼠标抬起路由会读该字段；缺失时右键抬起事件可能被当作左键处理。
    fileprivate var rawButtonNumber: Int64 {
        switch self {
        case .left: return 0
        case .right: return 1
        }
    }

    fileprivate func eventType(isDown: Bool) -> CGEventType {
        switch (self, isDown) {
        case (.left, true): return .leftMouseDown
        case (.left, false): return .leftMouseUp
        case (.right, true): return .rightMouseDown
        case (.right, false): return .rightMouseUp
        }
    }
}

/// 菜单栏项点击事件的**唯一构造器**（生产派发与诊断派发强制同源）
///
/// ## 为什么必须同源（2026-09-15 真机定案）
///
/// 诊断路径曾自行组装同一组字段，并**额外**把 `mouseEventClickState` 设在**抬起**事件上，
/// 而生产路径只设在按下事件上；两者的注释却声称「字段组装逐项一致」。
/// 后果是：诊断路径能打通、生产路径打不通，缺陷被诊断路径**静默掩盖**，
/// 排查时会得出「合成点击对任何应用都打不开菜单」的假结论。
///
/// 抬起的 `clickState` 恰恰是 Electron 系状态项（Notion 7.32.1 / Electron 43.5.1）能否收到
/// click 的**唯一门禁**：其托盘在 `mouseUp:` 处以 `event.clickCount == 1` 判定单击，
/// 而 `NSEvent.clickCount` 直接取自该字段。
public enum MenuBarClickEventFactory {

    /// 生成单边鼠标事件（`isDown` 决定按下 / 抬起）
    ///
    /// - 目标进程取 `item.clickTargetPID`（**状态项窗口的 owner**，见 `MenuBarItem.clickTargetPID`；
    ///   投入真实应用进程会让事件因「进程内不存在该窗口」而被静默丢弃）；
    /// - 中心点取窗口**实时** frame（窗口坐标可能已变化，`nativeFrame` 可能过期）；
    /// - 私有字段 `0x33` 与 `mouseEventClickState` **按下与抬起两侧都设**：
    ///   `CGEvent` 造出的抬起事件默认 `clickState == 0`（本机实测），缺此字段会让
    ///   Electron 托盘的单击门禁判定为「既非单击也非双击」而丢弃抬起事件；
    /// - `clickState` 即 `NSEvent.clickCount` 的来源：单击恒传 1（本工程不派发双击序列）。
    public static func makeMouseEvent(
        for item: MenuBarItem,
        button: MenuBarMouseButton = .left,
        clickState: Int = 1,
        isDown: Bool
    ) -> CGEvent? {
        guard item.windowID != 0,
              let frame = Bridging.frame(for: item.windowID) else {
            return nil
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)

        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                  mouseEventSource: source,
                  mouseType: button.eventType(isDown: isDown),
                  mouseCursorPosition: center,
                  mouseButton: button.cgButton
              ) else {
            return nil
        }

        let pid = Int64(item.clickTargetPID)
        let windowID = Int64(item.windowID)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)
        event.setIntegerValueField(CGEventField.menuBarItemWindowID, value: windowID)
        event.setIntegerValueField(.mouseEventButtonNumber, value: button.rawButtonNumber)
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))

        return event
    }
}
