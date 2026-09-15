# Specification: NotchRail v0.0.9 - 双屏多实例架构、能耗发热根治、极速事件驱动与岛内图标排序管理

> ⚠️ **历史归档 · 非现状（ARCHIVED — NOT CURRENT）**
> 本文件是 **v0.0.9 已闭环版本**的规格快照（归档自 Issue #50 及其 Ticket #51–#54），**仅作历史追溯之用**。
> 它**不是**当前系统行为的依据：当前需求与验收标准一律以 **GitHub Issues** 为唯一来源
> （查询方式见 `docs/agents/issue-tracker.md`）；与本文冲突时，**以 Issues、代码与 `AGENTS.md` 为准**。
>
> - **版本演进**：见 `docs/DEVELOPMENT_PLAN.md`
> - **架构决策**：见 `docs/adr/0001` ~ `docs/adr/0011`（ADR 正文为唯一来源，本文只引编号）
> - **领域术语**：见 `CONTEXT.md`（本文不定义术语）
> - **数值与常量**：以代码中的具名常量声明为唯一来源，本文只引常量名

---

## 1. Problem Statement

用户在使用 NotchRail 进行全天候及多显示器日常开发时，面临三大核心体验与系统级性能问题：

1. **隔夜长时运行严重发热与系统卡顿**：应用程序在后台运行数小时后，机身持续发热、风扇高转，并出现系统级操作卡顿。根本诱因在于系统内存在无条件 2.5 秒常驻轮询心跳，每次心跳无差别截取数十个窗口并执行底层 `CGContext` 逐像素循环遍历；叠加鼠标移动事件缺乏节流，高频抛出海量异步任务阻塞主线程，CPU 无法进入低功耗休眠。
2. **多显示器聚焦迁移导致的「余光小胶囊消失」视觉缺陷**：由于全局仅维护单一视口窗口实例，当用户将鼠标或焦点切换至外接平直显示器时，窗口实体被强制迁往外接屏（常态隐形挂起）；此时用户望向 MacBook 内建屏幕时，物理刘海下方原本常驻的紧凑胶囊与黄色溢出徽标完全消失，破坏了刘海屏原生的常态视觉锚点。
3. **岛内展开项缺乏自定义排序能力**：灵动岛展开时，图标完全按 WindowServer 物理扫描顺序被动排列，用户无法在岛内直接拖拽重排以定制自己的视觉顺序。

---

## 2. Solution

v0.0.9 引入 **双屏独立视口架构、事件驱动零空转能耗根治体系与岛内图标轻量排序管理**：

```
                        [User Multi-Display Workspace]
                                      │
        ┌─────────────────────────────┴─────────────────────────────┐
        ▼                                                           ▼
【MacBook Built-In Notch Screen】                        【External Flat Display (Non-Notch)】
• Physical Invariant: Camera cutout centered on top      • Physical Invariant: Zero hardware obstructions
• Panel Ownership: 常驻 primaryPanel (permanent guard)   • Panel Ownership: 独立 externalPanel (independent)
• Overflow Formula: minX < notchRightEdge                • Overflow Formula: minX < AppMenuBoundary
                     + OverflowCalculator.NOTCH_          + OverflowCalculator.APP_MENU_COLLISION_
                       CORNER_SAFETY_MARGIN                 SAFETY_MARGIN
• Idle State: Permanent black capsule + yellow wings     • Idle State: externalStealth (100% click-through)
• Expansion Form: Liquid drop-down fluid expansion       • Expansion Form: 中央受限热区 (NotchGeometry.
                                                           EXTERNAL_CENTER_HOT_ZONE_SPAN) 停留
                                                           (IslandTheme.Timing.HOVER_EXPAND_DELAY) 唤醒
• Expanded Visual: 纯黑吸光底座                           • Expanded Visual: 与刘海屏 100% 统一
  (IslandTheme.CornerRadius.TOP_EAR)                       (同 IslandTheme.CornerRadius.TOP_EAR)
```

### 2.1 双面板拓扑架构（Multi-Panel Topology）

- 彻底废除单例窗口在多屏之间的流转迁移；
- MacBook 物理刘海屏由 **主面板 `primaryPanel` 永久守护**，常驻呈现紧凑态刘海胶囊与动态溢出计数；
- 外接平直显示器由 **副面板 `externalPanel` 独立常驻**，折叠常态 100% 隐形透明且鼠标硬件级物理直通，触碰顶部中央受限热区时独立就地展开；
- 双屏互不借调、互不抢夺，实现真正的双屏独立视觉与交互共存。

### 2.2 能耗与发热根治体系（Zero-Overhead Event-Driven Pipeline）

- **按需休眠心跳（Smart Heartbeat）**：灵动岛折叠且光标远离热区时彻底停用高频轮询，后台空闲 CPU 占用严格压至 0.0%；
- **像素重绘与裁剪 Dirty-Check**：引入窗口指纹与图元缓存校验，已捕获的静态图标坚决不再重复创建 `CGContext` 与像素扫描；
- **全局鼠标移动采样节流**：消除鼠标监听闭包内的异步并发任务堆分配，引入时间戳节流（间隔见 `MouseMonitor.MOVE_THROTTLE_SECONDS`，即 60Hz 采样上限），并在屏幕中下部无关区域实行 0 开销快速熔断；
- **无障碍发现事件驱动化**：以 `NSWorkspace` 的应用启动与退出系统通知为触发源动态维护菜单项进程池，彻底终结定时全系统进程全量探测。

### 2.3 岛内流体拖拽重排与排序偏好持久化

- 保持 100% 原生菜单物理事件派发不变，不侵入、不拦截第三方应用的原生左键与右键弹窗逻辑；
- 灵动岛展开态下支持直接拖拽图标进行流体位移重排，实时更新自定义排序索引并原子持久化。

### 2.4 双轨物理自律与全局应用图元注册表（Application Asset Vault）

- 各显示器轨道 100% 独立闭环，各管本屏几何、窗口扫描与溢出判定，彻底杜绝跨屏窗口寻窗与借调；
- 针对 macOS WindowServer 在非聚焦屏幕暂停光栅化的机制，图元层建立以系统唯一 `bundleIdentifier` 为索引的应用资产注册表；
- 任何激活屏幕成功截取即登记入库，非激活屏幕展开灵动岛时直接凭本轨项的 Bundle ID 直出真实高清位图，0 兜底、0 错配、0 延迟。

---

## 3. User Stories

### 3.1 多显示器双面板独立架构
1. 作为双屏用户，我希望紧凑胶囊与黄色溢出计数在我把鼠标与活动窗口移到外接屏后**依然常驻 MacBook 物理刘海**，以便随时瞥见笔记本的溢出状态。
2. 作为在全屏编辑器工作的外接屏用户，我希望外接屏拥有独立隐形窗口，仅在我主动悬停顶部中央热区时才唤醒，以便永不打扰当前工作区。
3. 作为 MacBook 用户，我希望悬停笔记本刘海时其灵动岛在本屏平滑展开，且完全不影响外接屏的隐形待机态，以便两屏视觉完全独立。
4. 作为多屏用户，我希望焦点在显示器之间移动时**零窗口撕裂、零徽标闪烁、零视觉瞬移**，以便体验与 macOS 原生基础设施一致。
5. 作为合盖模式用户，我希望 NotchRail 自动禁用内建面板并仅保持外接面板活跃，以便不产生幻影窗口占用内存或拦截事件。

### 3.2 能耗、发热与长时稳定性
6. 作为电池供电过夜的用户，我希望灵动岛收起且空闲时 NotchRail 占用 0.0% CPU，以便机器保持凉爽、静音并延长续航。
7. 作为关注性能的开发者，我希望窗口指纹未变的状态项不再创建临时 `CGContext` 与扫描像素缓冲，以便彻底消除无谓的内存带宽与 CPU 开销。
8. 作为 ProMotion 120Hz 屏或高回报率鼠标用户，我希望鼠标移动事件被节流（上限见 `MouseMonitor.MOVE_THROTTLE_SECONDS`）且不在堆上分配异步闭包，以便主线程 RunLoop 始终保持响应。
9. 作为日常用户，我希望状态项发现严格响应应用启动与退出系统通知，以便应用永不周期性扫描整个系统进程表。
10. 作为动态状态项用户（网速表、时钟等），我希望系统仅在宽松节拍下选择性刷新动态项、静态图标完全不动，以便数字准确又不烧 CPU。
11. 作为长时运行用户，我希望 NotchRail 在 24 小时以上运行中保持扁平内存占用，无字典无界增长或 Combine 订阅泄漏。

### 3.3 岛内图标管理与拖拽排序
12. 作为拥有数十个菜单栏应用的用户，我希望在展开的灵动岛内直接拖拽图标，以便以流体布局动画直观定制视觉顺序。
13. 作为已定制图标优先级的用户，我希望偏好的状态项出现在岛内行的前部，以便常用工具始终最易触及。
14. 作为点击岛内任意镜像图标的用户，我希望其原生下拉菜单或配置浮层从所属应用真实弹出，以便所有原始上下文菜单、子菜单与快捷键继续按设计工作。

---

## 4. Implementation Decisions

### 4.0 核心领域契约不变量（Core Domain Contract Invariants）

1. **彻底废除平直托轨（flat-docked shelf）形态**
   - 旧草案中「外接屏无喇叭弧平直托轨（耳翼半径置 0）」已被彻底废除；
   - **新不变量**：扩展屏展开形态与刘海屏灵动岛**视觉完全统一**，均保留 `IslandTheme.CornerRadius.TOP_EAR` 经典外展喇叭弧与纯黑吸光底座；
   - 该不变量覆盖所有展开态渲染路径，包括 `IslandBackground` 的形态推导。
2. **废除 Viewport Leasing（视口借调流转）术语与逻辑**
   - 旧设计中「向主屏借调视口」导致主屏收起与外接屏展开的徽标闪烁冲突；
   - **新不变量**：确立为 **聚焦流转架构（Focus Following Architecture）**，面板归属权由屏幕焦点唯一决定；折叠常态外接屏处于 `externalStealth`（100% 隐形穿透），展开时原位升起、收起时原位淡出。
3. **设置项领域默认契约更新**
   - `UserPreferences.triggerMode` 领域默认值正式固化为 `.hoverAndClick`（悬停或点击）。

### 4.1 视口拓扑与管理：双独立面板模型

- **多屏解耦决策**：淘汰单例 Panel 视口迁移模型，引入具备物理独立性的主屏面板与外接屏面板生命周期管理；
- **全拓扑自适应**：智能适配 MacBook 刘海、单平直屏（Mac mini / 合盖模式）、双平直外接屏；主屏由主面板守护，扩展屏由副面板守护；
- **各屏状态独立约束**：每一台物理屏幕分配独立的几何描述实体与展示状态机；主刘海屏与外接平直屏的展开、收起、全屏唤醒状态彼此物理隔离；
- **硬件穿透统一管线**：各面板独立遵循各自屏幕光标坐标的 Hit-Test 穿透判定，非交互像素区 100% 物理直通底层应用；
- **Fail-Fast 归属契约**：`stateMachine(for:)` / `panel(for:)` 仅在目标屏确为对应面板锚定屏时返回实例，屏幕无归属面板时返回 `nil`，**严禁把面板回退返回给非其锚定的屏幕几何**。

### 4.2 扫描管线与心跳：事件驱动按需休眠与双轨自闭环

- **三档能耗节拍架构**：
  - `Dormant`（完全休眠态）：所有面板均处于折叠收起态且光标位于屏幕中下部时，心跳定时器完全挂起，后台无轮询；
  - `Armed`（就绪警戒态）：光标移入屏幕顶边缘热区时瞬间激活单次极速增量扫描与预热，确保展开第 0 帧位图命中；离开顶区立即回退 `Dormant`（超时保护见 `MenuBarSyncCoordinator.SmartHeartbeat.PREWARM_TIMEOUT_SECONDS`）；
  - `Active`（展开活动态）：任一面板处于展开展示态时按 `MenuBarSyncCoordinator.SmartHeartbeat.ACTIVE_INTERVAL_SECONDS` 执行轻量增量差分检测，收起后经 `MenuBarSyncCoordinator.SmartHeartbeat.COLLAPSE_COOLDOWN_SECONDS` 冷却回归 `Dormant`。
- **AX 空间映射缓存契约**：缓存有效期见 `MenuBarAXResolver.MAPPING_CACHE_TTL`，由进程启动 / 退出事件与窗口扫描发现的候选 PID 定向失效；稳态下不再随心跳周期重复执行 AX 全表遍历。
- **候选进程池维护**：候选池执行一次冷启动全量发现后，完全由 `NSWorkspace.didLaunchApplicationNotification` / `didTerminateApplicationNotification` 与窗口扫描的 `registerCandidatePID` 增量维护，**不存在定时全系统进程遍历机制**。
- **批量窗口提取**：窗口层级与几何信息查询采用单次批量获取，消除循环内逐个单独 C 系统调用。
- **双轨物理自律**：各显示器轨道绝对独立闭环，各管本屏几何、窗口扫描与溢出判定；代码中不存在 `pairedWindowID` 与跨屏寻窗。
- **全局应用图元注册表**：`IconResolver` 维护全局 `appAssetVault: [BundleID: CapturedIcon]`；任何激活屏幕成功截取真实位图时原子入库，非激活屏幕展开时凭自身确凿的 `bundleIdentifier` 直出真实位图，无配对、0 兜底、0 错配。

### 4.3 双轨几何碰撞解析器（Dual-Track Geometric Collision Resolver）

溢出计算引擎作为纯函数强制执行两条互斥物理轨道：

```swift
public enum OverflowCalculator {
    /// 数值以代码中的具名常量声明为准
    public static let NOTCH_CORNER_SAFETY_MARGIN: CGFloat
    public static let APP_MENU_COLLISION_SAFETY_MARGIN: CGFloat
    public static let SCREEN_EDGE_TOLERANCE: CGFloat

    public static func resolve(
        items: [MenuBarItem],
        geometry: NotchGeometry,
        customItemOrder: [String] = []
    ) -> MenuBarSnapshot { ... }
}
```

- **物理刘海轨道（`hasPhysicalNotch == true`）**：`item.nativeFrame.minX < (notchRightEdge + NOTCH_CORNER_SAFETY_MARGIN)`；
- **平直非刘海轨道（`hasPhysicalNotch == false`）**：`item.nativeFrame.minX < (appMenuRightEdge + APP_MENU_COLLISION_SAFETY_MARGIN)`，`physicalNotchRect` 永久 `.zero`；
- **严禁依赖 `!item.isOnScreen`**：Space / 全屏切换时 WindowServer 会将所有菜单项标记为未上屏。

### 4.4 事件驱动应用菜单边界提取（AppMenuBoundary）

- 绑定 `NSWorkspace.didActivateApplicationNotification`、`NSWorkspace.activeSpaceDidChangeNotification` 与 `NSApplication.didChangeScreenParametersNotification`；
- 后台异步提取前台应用 `kAXMenuBarAttribute` → `kAXChildrenAttribute`，取最右子项 `position.x + size.width`；提取实现见 `MenuBarAXResolver`，结果经 `ScreenManager.updateAppMenuRightEdge(_:for:)` 写入其内部缓存，并最终以 `NotchGeometry.appMenuRightEdge` 暴露给调用方；
- 基准回退：AX 返回为空或前台为访达时，回退 `screen.frame.minX + NotchGeometry.DEFAULT_APP_MENU_WIDTH`（Apple 标志与应用标题预留）。

### 4.5 图标流体拖拽重排与偏好模型

- **数据结构**：`UserPreferences.customItemOrder: [String]`，持久化用户自定义唯一标识排序数组，须保证向前向后编解码兼容（缺失键回退空数组）；
- **排序契约**：溢出计算与快照构建管线优先应用自定义排序权重，未排序项按物理空间坐标依序自然追加；
- **交互契约**：展开态通过 `ReorderableIconRow` 支持原生手势拖拽流体位移重排；拖拽结束原子更新 `customItemOrder` 并同步持久化至 UserDefaults；
- **零侵入契约**：不拦截次级点击（Right Click / Control Click），底层 `CGEvent.postToPid` 原生菜单物理派发机制完全不变，第三方应用原生弹出菜单 100% 完整。

### 4.6 边缘交互与中央热区

- **空间约束**：水平跨度为屏幕中心对称的 `NotchGeometry.EXTERNAL_CENTER_HOT_ZONE_SPAN`；垂直深度为屏幕顶边缘 ≤ `NotchGeometry.EXTERNAL_CENTER_HOT_ZONE_THRESHOLD`（刘海屏另见顶边缘唤醒热区 `NotchGeometry.TOP_EDGE_HOT_ZONE_THRESHOLD`）；
- **时间过滤**：光标进入热区即启动一次性停留定时器（时长取 `UserPreferences.hoverExpandDelayMs`，默认 `IslandTheme.Timing.HOVER_EXPAND_DELAY`）；到期前离开、或向下高速竖穿速度超过 `MouseMonitor.DOWNWARD_CROSS_SPEED_THRESHOLD` 则取消且零状态变更；
- **零溢出静音门**：`effectiveSnapshot.overflowCount == 0` 时热区求值立即中止。

### 4.7 视觉呈现与形态

- 外接平直屏展开态与刘海屏灵动岛**视觉完全统一**：`IslandTheme.CornerRadius.TOP_EAR`、纯黑吸光底座、微光渐变描边；
- 折叠常态：`alpha = 0.0`、`ignoresMouseEvents = true`，底层窗口 100% 物理直通。

---

## 5. Testing Decisions

### 5.1 良好测试准则
- **外部行为黑盒验证**：测试严禁依赖私有内部实现细节，仅验证外部输入（屏幕拓扑变化、光标物理移动、系统应用启动事件、用户偏好调整）与外部契约（快照产物、面板几何、可见性透明度、事件穿透标志、排序顺序）的一致性；
- **测试必须守护生产契约**：被测函数的默认参数即生产调用语义，严禁出现「单测验证默认分支、生产显式传入另一阈值」的契约脱节；
- **长时能耗与心跳契约**：必须引入针对心跳休眠门禁的断言，确保静止折叠态下定时器处于非激活状态。

### 5.2 重点测试模块与接缝

1. **视口拓扑接缝（Window Coordinator Seam）**
   - 模拟双屏拓扑（主物理刘海屏 + 外接平直大屏）；
   - 验证主屏面板常驻保持 `compact` 几何，而外接屏面板处于穿透态，光标在外接屏操作时主屏面板状态严格不受影响；
   - 验证无归属面板的屏幕调用 `panel(for:)` / `stateMachine(for:)` 返回 `nil`（Fail-Fast）。
2. **能耗与节流接缝（Monitor & Throttling Seam）**
   - 向鼠标监听器注入 1000 次高频微小位移，验证下游几何碰撞判定调用次数严格受限于节流窗口且不产生异步任务堆积；
   - 验证空闲收起状态下无重复截图与像素处理调用。
3. **图元缓存与增量比对接缝（Icon Resolver Seam）**
   - 验证相同窗口指纹的多次解析直接命中内存缓存，且不重复创建图形上下文。
4. **自定义排序接缝（Overflow Calculator Seam）**
   - 验证 `customItemOrder` 对溢出项输出顺序的确定性约束。
5. **几何热区接缝（Geometry Seam）**
   - 验证外接屏中央热区（`NotchGeometry.EXTERNAL_CENTER_HOT_ZONE_SPAN`）的水平防误触边界与 `NotchGeometry.EXTERNAL_CENTER_HOT_ZONE_THRESHOLD` 垂直阈值契约；
   - 验证多显示器水平偏移下热区坐标正确换算。

### 5.3 既有实践（Prior Art）
- `Tests/NotchRailTests/ScreenManagerTests.swift` 的多屏几何测试；
- `Tests/NotchRailTests/MouseMonitorTests.swift` 的热区、防抖状态机与节流测试；
- `Tests/NotchRailTests/OverflowCalculatorTests.swift` 的双轨碰撞与自定义排序测试；
- `Sources/NotchRailKit/Spike/SpikeRunner.swift` 的真实硬件端到端诊断体系（22 个用例，编号 1–24 含历史断档）。

---

## 6. Failure Pre-Mortem & Mitigation Matrix

| Failure Mode | Early Warning Signal | Root Cause | Architectural Mitigation |
| :--- | :--- | :--- | :--- |
| **AX IPC Hang / Latency Spike** | 应用切换时主线程卡顿 > 50ms | 同步 `AXUIElement` 遍历阻塞 RunLoop | 在独立后台 Task 中执行提取；只查询顶层菜单子项（< 10 项）；结果缓存于原子内存变量中，由进程事件定向失效。 |
| **多屏视口撕裂** | 光标移向副屏时笔记本刘海胶囊消失 | 单例 Panel 在待机时被迁移到外接屏 | **已由 v0.0.9 双面板架构根治**：主屏 `primaryPanel` 常驻守护、副屏 `externalPanel` 独立常驻，双轨互不借调。 |
| **全屏空间菜单碰撞** | 全屏视频下双黑条遮挡原生时钟 | 外接屏顶边缘触发覆盖正在滑出的 macOS 菜单栏 | 判定 `isFullScreenSpace`：全屏空间中让位原生菜单栏，仅在已滑出的菜单栏中央受限区（`NotchGeometry.EXTERNAL_CENTER_HOT_ZONE_SPAN`）产生悬停意图才触发。 |
| **竖向屏幕穿行误触发** | 从上屏向下移动光标时灵动岛弹出 | 光标穿行时跨过下屏顶边缘坐标 | 停留定时器（取 `UserPreferences.hoverExpandDelayMs`） + 下向速度判定（`MouseMonitor.DOWNWARD_CROSS_SPEED_THRESHOLD`），在高速竖穿时取消触发。 |
| **非激活屏图标空白 / 错配** | 非聚焦屏展开灵动岛时图标为空白或张冠李戴 | 非聚焦屏 WindowServer 暂停菜单项光栅化，截图返回全透明 | **已由 v0.0.9 全局应用图元注册表根治**：按 `bundleIdentifier` 直出该应用的真实位图，0 兜底、0 错配。 |
| **图元缓存语义漂移** | 单测通过但真机行为不符 | 同一语义在多个调用点各自展开，默认值与显式传参分叉 | 三层图元查找收敛为唯一入口；几何阈值等契约只保留一处定义，调用点不得覆写。 |

---

## 7. Out of Scope

1. **私有菜单弹窗重定位（Private Menu Hooking）**：坚决不通过 Hook 私有 AppKit / WindowServer 篡改第三方应用原生下拉菜单与 Popover 的物理弹出位置，避免系统升级崩溃；
2. **Spacer 强行插入与原生菜单篡改**：坚决不修改原生 macOS 菜单栏顺序，不向原生菜单栏插入空白占位项；
3. **泛化为副 Dock 栏**：坚守纯粹防遮挡扩展与溢出补足原则，不支持用户常驻钉选原生已完全可见的非溢出应用；
4. **云同步配置**：偏好设置与排序仅保存在本地持久化存储，不引入任何云端通信或网络依赖；
5. **用户可拖拽的浮层自由定位**：浮层位置由物理几何唯一决定，不支持任意拖放；
6. **自定义主题与颜色覆写**：浮层背景不提供主题与配色覆写；
7. **macOS 13 (Ventura) 及更早版本支持**：仅支持 macOS 14.0 (Sonoma) 及以上。

> **说明**：「灵动岛内图标拖拽重排」曾列入 v0.0.9 之前的 Out of Scope，现已由 v0.0.9 的 `ReorderableIconRow` 正式交付（见 §4.5），**不再属于范围外**。

---

## 8. Further Notes

- **性能预算**：菜单边界查询 < 1ms（事件驱动）；几何溢出计算 < 0.01ms（纯算术）；静息折叠态后台 CPU 开销 0.0%；稳态菜单栏扫描耗时契约见 `AGENTS.md` §3.4 / §4.3（该指标的唯一定义处，本文件不复述数值）。
- **全量归入 v0.0.9**：本 Spec 成果全量归入 NotchRail v0.0.9。
- **开发节奏**：遵循架构重构原则，优先实施「能耗发热根治（§4.2）」与「双屏独立面板拓扑（§4.1）」，再闭环「岛内图标排序（§4.5）」。
- 全规格 100% 遵守 Fail-Fast 与 Zero-Fallback 架构不变量，不引入任何猜测性兜底。
