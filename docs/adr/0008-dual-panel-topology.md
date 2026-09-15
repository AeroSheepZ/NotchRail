# 0008. 双面板独立拓扑与聚焦流转架构（废除单例视口借调与平直托轨形态）

> **状态：部分被取代** —— 本 ADR 的**决议 2**（主屏 `primaryPanel` / 外接屏 `externalPanel` 的双槽位模型）与**决议 5** 中「第三块及以上显示器无归属面板」的部分，已被 [ADR 0009](0009-multi-display-panel-registry.md) 取代，改为按 `displayID` 的视口与状态机注册表，屏幕数量不设上限。决议 1、3、4、6 继续有效。依 ADR 规范，正文保持原样不改写。

### 背景
自 ADR 0002 起，外接平直显示器采用「全局单例 `IslandPanel` 视口借调」模型：面板常态守护 MacBook 物理刘海屏，仅在外接屏触发溢出且光标停留顶部中央热区时原子迁移至外接屏展开，收起后归位。该模型在 v0.0.9 暴露出两个不可调和的缺陷：

1. **「余光小胶囊消失」**：面板实体迁往外接屏（常态隐形挂起）后，MacBook 物理刘海下方原本常驻的紧凑胶囊与黄色溢出徽标完全消失，破坏刘海屏的原生视觉锚点，并引发「应用是否仍在运行」的故障疑虑；
2. **跨屏徽标抢夺与闪烁**：主屏收起与外接屏展开在单实例面板上互相覆盖状态，聚焦切换时出现徽标闪烁与视觉瞬移。

同时，ADR 0002 决议 4 要求外接屏展开时 `topEarRadius = 0`，呈现无喇叭弧的平直托轨（Floating Shelf），与刘海屏灵动岛形成两套割裂的视觉语言。

### 决议
1. **废除单例视口借调（Viewport Leasing）与「平直托轨（Floating Shelf）」形态**：相关术语与机制永久废止，`topEarRadius = 0.0` 的平直形态不再存在。
2. **确立双面板独立拓扑（Dual Panel Topology）**：主屏基准屏由常驻 `primaryPanel` 永久守护，外接平直屏由独立 `externalPanel` 常驻接管；两者各自持有物理隔离的 `IslandStateMachine` 与事件穿透流，互不借调、互不抢夺。
3. **确立聚焦流转架构（Focus Following Architecture）**：面板归属权由屏幕焦点唯一决定。外接屏折叠常态为 `externalStealth`（`alpha = 0.0`、`ignoresMouseEvents = true`，100% 物理直通），触碰顶部中央 240pt 热区停留 120ms 后原位升起，收起时原位淡出。
4. **展开形态视觉 100% 统一**：外接屏展开态与刘海屏灵动岛共用同一视觉语言 —— `topEarRadius = IslandTheme.CornerRadius.TOP_EAR (5.0pt)` 外展喇叭弧、纯黑吸光底座、微光渐变描边。
5. **面板归属 Fail-Fast**：`panel(for:)` / `stateMachine(for:)` 仅在目标屏确为对应面板锚定屏时返回实例；屏幕无归属面板（如第三块及以上显示器）时返回 `nil`，严禁把面板回退返回给非其锚定的屏幕几何。
6. **双轨物理自闭环与全局应用图元注册表**：废除跨屏窗口成对路由；`IconResolver` 以 `bundleIdentifier` 为索引维护全局 `appAssetVault`，任一激活屏捕获到的真实位图即登记入库，非激活屏凭自身确凿 Bundle ID 直出，0 兜底、0 错配。

### 理由与权衡
双面板模型以「每个物理屏幕一个独立视口」换取视觉与交互的完全隔离，代价是同时存在两块常驻透明窗口。由于折叠常态下副面板为 `alpha = 0.0` 且完全穿透、心跳由单一协调器按三档节拍统一调度，额外开销可控。借此，多显示器场景下的胶囊蒸发、徽标抢夺与视觉撕裂被从架构层面根治，而非依赖时序补丁掩盖。

### 影响
- 取代 [ADR 0002](0002-physical-notch-only-architecture.md) 的决议 3 及决议 4 中的形态部分（决议 1、2 继续有效）；
- 相关实现见 `IslandWindowCoordinator`（`primaryPanel` / `externalPanel` / `externalOwnedDisplayID`）、`IconResolver.appAssetVault`、`MenuBarSyncCoordinator` 三档心跳；
- 需求与验收依据见 Issue #50（v0.0.9 Spec）与 Ticket #51–#54。
