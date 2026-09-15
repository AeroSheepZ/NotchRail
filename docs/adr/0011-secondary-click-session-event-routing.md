# 0011. 辅助点击改走会话事件流 + 目标窗口字段路由（修正 ADR 0010 决议 3、6）

> **状态：现行** —— 本 ADR 修正 [ADR 0010](0010-status-item-owner-event-dispatch.md) 的**决议 3**（辅助点击先按 `isOnScreen` 判定可达性）与**决议 6**（未合成项无可用辅助点击通道、返回 `ClickError.unreachableTarget`）。ADR 0010 的决议 1、2、4、5、7、8 继续有效。

### 背景

[ADR 0010](0010-status-item-owner-event-dispatch.md) 结论「辅助点击没有可用通道」建立在**两条已穷尽的失败样本**之上：

- 样本 A —— 私有字段 + `postToPid`（宿主激活通道）：右键被静默丢弃，该通道**只认左键**；
- 样本 B —— 系统事件流的**裸坐标**右键（不带目标窗口字段）：被自有视口吃掉或落点无归属，同样失败。

ADR 0010 由这两条失败**外推**出「未参与合成的溢出项不存在可用的辅助点击通道」，并把该外推当作平台边界写入决议 6。v0.0.10 真机复核发现这一外推**不成立**：样本 B 并不等于「右键经系统事件流投递」的全集 —— 它遗漏了第三条组合，即**在同一会话事件流上同时携带目标窗口字段**。

真机对照（内建刘海屏，目标为被刘海挤占、`isOnScreen == false` 的 Electron 系托盘项）：以 `CGEvent.post(tap: .cgSessionEventTap)` 投递 `rightMouseDown` / `rightMouseUp`，事件同时携带 `mouseEventWindowUnderMousePointer`、`mouseEventWindowUnderMousePointerThatCanHandleThisEvent` 与私有 `0x33` 三个字段且均等于目标 `windowID`，应用**立即弹出自己的原生上下文菜单**（新窗口落在 `kCGPopUpMenuWindowLevel`、owner 为该应用）。

⇒ 未参与合成的溢出项**有**可用的辅助点击通道。ADR 0010 决议 3、6 的平台边界自此被推翻。

失败样本 A 的结论在本 ADR 范围内**继续有效**：宿主激活通道确实只认左键，因此辅助点击不能复用它。

### 决议

1. **辅助点击不再以 `isOnScreen` 分流**。可达性的唯一前置条件是「目标项持有有效 `windowID`」；该项是否被窗口服务器合成，不再影响本通道的成败，也不再是拒绝派的理由。
2. **辅助点击恒走会话事件流 + 目标窗口字段通道**：`CGEvent.post(tap: .cgSessionEventTap)`，事件携带 `MenuBarClickEventFactory` 组装的目标窗口字段与 `rightMouseDown` / `rightMouseUp`。投递前须让自有视口临时穿透**并等待穿透标志在窗口服务器侧生效**，投递后按进入前的真实状态逐屏还原（承接 ADR 0010 决议 4、5，本文不复述理由）。
3. **机制**：只要事件进入会话事件流，窗口服务器就把这组字段当作**路由覆盖**，把鼠标事件精确交给目标 `windowID` 的窗口 —— 走的是与真实点击同一条路，因此应用收到的是货真价实的 `rightMouseDown` / `rightMouseUp`。该通道对左键与右键**均有效**；宿主激活通道的「仅左键」限制（ADR 0010 背景 2）不适用于本通道。
4. **派发后判定目标应用是否响应**，作为抖动反馈的依据：投递后开启一个**响应观察窗**（常量见 `MenuBarItemClicker.SECONDARY_RESPONSE_WINDOW_NANOSECONDS`），窗内若出现**新的菜单层窗口**（`kCGPopUpMenuWindowLevel`，owner 非菜单栏宿主、非本进程）即判定为已响应，返回 `.success`；否则返回 `.failure(.noResponse)`，由岛内图标触发横向 Shake 与触觉反馈。
5. **`ClickError.unreachableTarget` 一并删除**。错误集合为 `invalidWindow` / `frameUnavailable` / `eventCreationFailed` / `noResponse`；`noResponse` 的语义是「事件已送达，但该状态项没有辅助点击处理」，**不是**「不可达」。
6. **严禁因本修正而改发左键**：左键单击与辅助点击仍是两个不同的用户操作，绝不互相冒充。左键在部分应用是「立即动作」而非菜单（静音 / 暂停 / 开关），冒充与用户意图相悖。

### 理由与权衡

**为何 ADR 0010 会错**：把「两条投递组合失败」归纳成「平台无通道」，而正确的做法是把「投递方式 × 事件类型 × 是否携带目标窗口字段」张成矩阵**逐格穷尽**，再谈边界。ADR 0010 的取证虽带有效性对照（可见项作对照项），但对照只证明了**所试组合**的有效性，无法证明**未试组合**的无效性 —— 对照组的存在排除了「取景框整体失效」，却没有排除「组合遗漏」。这类「穷尽性声明」必须由矩阵覆盖度支撑，不能由样本失败数支撑。

**代价**：决议 4 的响应判定引入了两重成本 —— 一是派发后需等待观察窗才有反馈（用户感知为一次点击的判定延时）；二是把辅助点击实现为**无窗口的即时动作**（如开关类）的应用会被判成无响应而抖动。后者是「不去猜测应用内部行为」的代价：宁可对少数无窗口动作误报抖动，也不去伪造一个可见响应。

**保留 ADR 0010 的正确部分**：派发目标恒为状态项窗口 owner（决议 1）、穿透须等待生效（决议 4）、穿透状态精确还原（决议 5）、字段唯一构造器（决议 7）、不提供左键双击（决议 8）。

### 影响

- 修正 [ADR 0010](0010-status-item-owner-event-dispatch.md) 决议 3、6；决议 1、2、4、5、7、8 继续有效，0010 正文按 ADR 规范保持原样不改写；
- **「刘海屏岛内辅助点击弹不出菜单」的平台边界不再成立**，需在 `AGENTS.md` §3.4、`docs/DOMAIN_MODEL.md` §2.7、`README.md` 同步撤销该表述；
- 相关实现见 `MenuBarItemClicker.secondaryClick(for:)`、`MenuBarItemClicker.awaitMenuResponse(baseline:hostPID:)`、`Bridging.popUpMenuWindowOwners()`、`MenuBarClickEventFactory`；
- 与 Issue #55 §3「Real Owner PID」的差异（派发目标取窗口 owner 而非真实归属进程）**不受本 ADR 影响**，仍按 ADR 0010 的影响条款以 issue 评论回填。
