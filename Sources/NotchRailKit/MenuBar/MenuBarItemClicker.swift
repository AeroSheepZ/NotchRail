import ApplicationServices
import CoreGraphics
import Foundation

/// 点击派发错误类型
public enum ClickError: Error, Sendable {
    case invalidWindow      // 缺少有效 windowID（非窗口枚举路径）
    case frameUnavailable   // 无法获取窗口实时 frame
    case eventCreationFailed
    /// 事件已送达该状态项，但目标应用在**响应观察窗**内既未弹出菜单、也无其它可见响应，
    /// 即「该项没有辅助点击处理」。调用方据此给出抖动反馈（不是静默）。
    case noResponse
}

/// 合成点击的种类（对应用户在菜单栏上的两种真实操作）
///
/// - `single`（左键单击）→ 宿主激活通道：私有字段事件经 `postToPid` 投给窗口 owner；
/// - `secondary`（= 触控板双指点击 = 鼠标右键，macOS 上二者是**同一个操作**）→ 会话事件流通道：
///   同样携带目标窗口字段，但改投 `.cgSessionEventTap`，由窗口服务器按字段精确路由。
///
/// **刻意不提供「左键双击」**：双击属于 `.leftMouseDown` 的 `clickCount == 2`，与辅助点击正交，
/// 而用户对菜单栏图标的实际诉求里并不存在双击。更关键的是，一旦按 `clickCount >= 2` 分流，
/// 用户在双击间隔内对**同一图标**的第二次单击就会被误当成双击补发（`clickState = 2`），
/// 应用侧（如 Electron 托盘只认 `clickCount == 1 / 2` 的单击与双击）对该序列不做单击响应，
/// 表现为「单击时灵时不灵」。
public enum MenuBarClickKind: String, Sendable {
    /// 左键单击
    case single
    /// 辅助点击（触控板双指点击 / 鼠标右键），供应用弹出自己的原生上下文菜单
    case secondary
}

/// 按 windowID 对真实菜单栏窗口合成点击的交互执行器（替代 AXPress）
///
/// 被动溢出场景下，图标窗口仍在菜单栏中（只是被刘海遮住），
/// 直接按 windowID 合成鼠标事件并派发即可触发原生下拉菜单，
/// 无需移动窗口、无需 AX 树遍历。
///
/// ## 核心机制：目标窗口字段 = 窗口服务器的**路由覆盖**（2026-09-15 真机定案）
///
/// 事件里的一组字段由 `MenuBarClickEventFactory` 唯一组装：
/// `menuBarItemWindowID`（私有 0x33）、`mouseEventWindowUnderMousePointer`、
/// `mouseEventWindowUnderMousePointerThatCanHandleThisEvent`。
///
/// **只要事件被推进会话事件流（`CGEvent.post(tap: .cgSessionEventTap)`），
/// 窗口服务器就会把这组字段当作路由覆盖**，把鼠标事件精确交给该 `windowID` 对应的窗口 ——
/// 即便该窗口**未参与合成**（`isOnScreen == false`，即被刘海挤占的那些）。
/// 走的是与真实点击同一条路，因此应用收到的是货真价实的 `rightMouseDown/Up`。
///
/// ## 两条通道为何不能互换（实测边界）
///
/// | 通道 | 投递方式 | 有效按键 |
/// | :--- | :--- | :--- |
/// | 宿主激活 | `postToPid(owner)` | **仅左键** |
/// | 会话事件流 + 字段 | `post(tap: .cgSessionEventTap)` | 左键与右键**均有效** |
///
/// 「宿主激活」通道是宿主（控制中心）内部的「菜单栏项激活」快捷路径，
/// **系统只给它实现了左键**：同样字段配 `rightMouseDown/Up` 经 `postToPid` 投递时被静默丢弃
/// （多轮多应用实测，且与左键行为逐字一致的那组「左类型 + `mouseEventButtonNumber=1`」混合事件
/// 证明其按键判定取自事件类型而非按键号，故**不是**可用于右键的通道）。
///
/// 于是辅助点击恒走会话事件流 + 字段通道，**不以 `isOnScreen` 分流**：
/// 该项是否被合成不再影响可达性，只影响我们是否需要临时穿透自有视口（见下）。
///
/// ## 派发后的响应判定
///
/// 辅助点击的语义是「把右键交给该状态项，由它自己决定」：有菜单就弹菜单，有处理就执行处理。
/// 派发后开一个**响应观察窗**（`SECONDARY_RESPONSE_WINDOW_NANOSECONDS`），
/// 若窗口内出现**新的菜单层窗口**（且不属菜单栏宿主）即判为已响应，返回 `.success`；
/// 否则返回 `.failure(.noResponse)`，由岛内图标触发横向 Shake + 触觉反馈。
/// 已知取舍：把辅助点击实现为**无窗口的即时动作**（如开关类）的应用会被判成无响应而抖动，
/// 这是「不去猜测应用内部行为」的代价。
public actor MenuBarItemClicker {
    public static let shared = MenuBarItemClicker()

    private init() {}

    /// 对指定菜单栏项合成一次原生点击
    ///
    /// - Parameter kind: 点击种类（左键单击 / 辅助点击），通道选择见类注释。
    @discardableResult
    public func performClick(
        for item: MenuBarItem,
        kind: MenuBarClickKind = .single
    ) async -> Result<Void, ClickError> {
        guard item.windowID != 0 else {
            return .failure(.invalidWindow)
        }
        // 用窗口实时 frame 计算点击中心（窗口坐标可能已变化）
        guard Bridging.frame(for: item.windowID) != nil else {
            return .failure(.frameUnavailable)
        }

        switch kind {
        case .single:
            return hostActivation(for: item)
        case .secondary:
            return await secondaryClick(for: item)
        }
    }

    /// 宿主激活通道：左键事件投给**状态项窗口的 owner**，由宿主完成菜单栏项激活并转交真实应用
    private func hostActivation(for item: MenuBarItem) -> Result<Void, ClickError> {
        guard
            let down = MenuBarClickEventFactory.makeMouseEvent(
                for: item,
                button: .left,
                clickState: 1,
                isDown: true
            ),
            let up = MenuBarClickEventFactory.makeMouseEvent(
                for: item,
                button: .left,
                clickState: 1,
                isDown: false
            )
        else {
            return .failure(.eventCreationFailed)
        }

        let pid = item.clickTargetPID
        down.postToPid(pid)
        usleep(Self.CLICK_PRESS_INTERVAL_US)
        up.postToPid(pid)
        return .success(())
    }

    /// 辅助点击通道：会话事件流 + 目标窗口字段，投递后判定目标应用是否给出响应
    ///
    /// 投递期间必须让自有灵动岛视口**临时穿透**：视口位于菜单栏之上，不穿透时落点处的命中
    /// 会被自家视口截走（实测）。结束后按**进入前的真实状态**逐个还原，绝不能一律复位为 false ——
    /// 平直外接屏折叠常态本就要求 `ignoresMouseEvents == true`。
    private func secondaryClick(for item: MenuBarItem) async -> Result<Void, ClickError> {
        guard
            let down = MenuBarClickEventFactory.makeMouseEvent(
                for: item,
                button: .right,
                clickState: 1,
                isDown: true
            ),
            let up = MenuBarClickEventFactory.makeMouseEvent(
                for: item,
                button: .right,
                clickState: 1,
                isDown: false
            )
        else {
            return .failure(.eventCreationFailed)
        }

        // 观察窗基线：投递前已存在的菜单层窗口
        let baselineMenus = Bridging.popUpMenuWindowOwners()

        let saved = await MainActor.run { Self.enterIslandPassthrough() }
        // 穿透标志要等窗口服务器实际生效后才能派发；立刻派发仍会被自家视口吃掉（实测）
        try? await Task.sleep(nanoseconds: Self.PASSTHROUGH_SETTLE_NANOSECONDS)
        down.post(tap: .cgSessionEventTap)
        usleep(Self.CLICK_PRESS_INTERVAL_US)
        up.post(tap: .cgSessionEventTap)
        try? await Task.sleep(nanoseconds: Self.PASSTHROUGH_SETTLE_NANOSECONDS)
        await MainActor.run { Self.exitIslandPassthrough(saved) }

        let responded = await Self.awaitMenuResponse(baseline: baselineMenus, hostPID: item.clickTargetPID)
        return responded ? .success(()) : .failure(.noResponse)
    }

    /// 在响应观察窗内轮询「是否新出现目标应用的菜单层窗口」
    ///
    /// 排除两类必然出现的噪声：菜单栏宿主自身新建的状态项窗口（层不同，已由 `popUpMenuWindowOwners`
    /// 的层级过滤剔除）与 NotchRail 自己的窗口。
    private static func awaitMenuResponse(baseline: [CGWindowID: pid_t], hostPID: pid_t) async -> Bool {
        var waited: UInt64 = 0
        while true {
            let current = Bridging.popUpMenuWindowOwners()
            let appeared = current.contains { windowID, ownerPID in
                baseline[windowID] == nil && ownerPID != hostPID && ownerPID != getpid()
            }
            if appeared { return true }
            if waited >= SECONDARY_RESPONSE_WINDOW_NANOSECONDS { return false }
            try? await Task.sleep(nanoseconds: RESPONSE_POLL_NANOSECONDS)
            waited += RESPONSE_POLL_NANOSECONDS
        }
    }

    /// 按下与抬起之间的间隔（微秒）
    private static let CLICK_PRESS_INTERVAL_US: UInt32 = 20_000

    /// 视口穿透标志生效所需的等待（纳秒）
    private static let PASSTHROUGH_SETTLE_NANOSECONDS: UInt64 = 150_000_000

    /// 辅助点击的响应观察窗总时长（纳秒）
    private static let SECONDARY_RESPONSE_WINDOW_NANOSECONDS: UInt64 = 450_000_000

    /// 响应观察的轮询粒度（纳秒）
    private static let RESPONSE_POLL_NANOSECONDS: UInt64 = 60_000_000

    /// 临时把全部已装载视口置为鼠标穿透，返回进入前的状态用于精确还原
    @MainActor
    private static func enterIslandPassthrough() -> [CGDirectDisplayID: Bool] {
        var saved: [CGDirectDisplayID: Bool] = [:]
        for geometry in ScreenManager.shared.allGeometries {
            guard let panel = IslandWindowCoordinator.shared.panel(for: geometry.displayID) else { continue }
            saved[geometry.displayID] = panel.ignoresMouseEvents
            panel.ignoresMouseEvents = true
        }
        return saved
    }

    @MainActor
    private static func exitIslandPassthrough(_ saved: [CGDirectDisplayID: Bool]) {
        for (displayID, ignores) in saved {
            IslandWindowCoordinator.shared.panel(for: displayID)?.ignoresMouseEvents = ignores
        }
    }
}
