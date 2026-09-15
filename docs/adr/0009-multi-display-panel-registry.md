# 0009. 多屏视口与状态机注册表（取代双槽位面板模型）

### 背景
ADR 0008 确立的双面板拓扑把「每个物理屏幕一个独立视口」实现成了**两个固定槽位**：主屏 `primaryPanel` 与外接屏 `externalPanel`。该模型在 v0.0.9 之后暴露出三类结构性缺陷：

1. **屏幕数量被写死**：`externalOwnedDisplayID` 只取「主屏基准屏之外的第一块屏」，`panel(for:)` / `stateMachine(for:)` 对第三块及以上显示器一律返回 `nil` —— 用户接入三屏时，第三块屏**没有灵动岛，也没有任何提示**，属静默失效；而同期文档却宣称兼容「双外接平直屏」。
2. **渲染对账暗含副作用**：`updatePanelLifecycle` 名义上是按屏的纯渲染计算，却会在屏幕处于展开态时改写 `ScreenManager` 的全局焦点屏。由于 `applyDisplayAndVisibilityRules` 同时订阅 `ScreenManager.$currentGeometry`，二者构成重入环：展开外接屏 → 焦点屏被改写 → 溢出判定基准随之变化 → 再次触发对账。
3. **能耗与刷新判定全局化**：`IconResolver` 以全局 `heartbeatState == .active` 决定是否全量重捕获，任一屏展开都会把所有屏拖入全量截图；`MenuBarSyncCoordinator` 另持有只写不读的全局单值快照与跨屏合并池，且仅在焦点屏才广播快照，非焦点屏的界面更新因此停滞。

### 决议
1. **视口与状态机一律按 `displayID` 注册**：分别存于 `IslandWindowCoordinator.panelsByDisplay` 与 `machinesByDisplay`，屏幕数量不设上限；禁止任何 `primary*` / `external*` 式的成对字段。
2. **视口按需装载、状态机常驻**：主屏视口常驻；其余屏在「展开中或存在溢出项」时保留视口，空闲达到宽限时长（常量见 `IslandWindowCoordinator.PANEL_IDLE_UNLOAD_SECONDS`）后卸载视口以回收开销，但**状态机不得随之销毁** —— 否则「触碰顶部热区展开」的交互链路会断在 `stateMachine(for:)` 上。
3. **渲染对账必须幂等且无副作用**：`applyDisplayAndVisibilityRules` 只负责按当前拓扑装载 / 更新 / 卸载，**绝不改写全局焦点屏**；焦点跟随由 `MouseMonitor` 在真实用户交互处驱动。
4. **屏幕增减由对账处理**：屏幕插入即建立独立状态机并按需装载视口，拔出即卸载，无需任何写死屏数的分支。
5. **快照广播按屏无差别**：快照自身携带 `displayID`，由订阅方按本屏过滤；移除只写不读的全局单值快照与跨屏合并池。
6. **图标解析的动态重捕获判定按屏独立**：以该屏是否处于展开态为准，杜绝任一屏展开即全屏重捕获。
7. **图元注册表的键必须逐项唯一**：系统类状态项不得共用控制中心宿主 `bundleIdentifier`，否则注册表槽位互相覆盖，非激活屏回退取图必然张冠李戴。
8. **宿主视图自带屏幕上下文**：`IslandHostingView` 注入 `displayID`，命中区一律以本屏几何与本屏状态机计算，不得读取全局焦点屏或共享状态机。

### 理由与权衡
按屏注册表以「视口与状态机同屏自闭环」换取屏幕数量上的可扩展性：任意屏数都不需要新增分支，第三块屏不再静默失效。视口按需装载把常驻透明窗口的数量压到「主屏 + 当前真正有内容的屏」，与 Issue #51 定下的休眠期零空转目标一致；而状态机保持常驻是必要代价 —— 它是轻量对象，却是触碰展开链路在视口未装载时唯一可用的入口。

### 影响
- 取代 [ADR 0008](0008-dual-panel-topology.md) 的决议 2，以及决议 5 中「第三块及以上显示器无归属面板」的部分；0008 的决议 1、3、4、6 继续有效；
- 相关实现见 `IslandWindowCoordinator`（`panelsByDisplay` / `machinesByDisplay` / 对账与按需装载）、`IslandHostingView`、`StatusItemManager`、`IconResolver.resolveIcons(for:displayID:forceRefresh:)`；
- 术语与方向表述见 `CONTEXT.md` 与 `AGENTS.md` §2.1、§3.1。
