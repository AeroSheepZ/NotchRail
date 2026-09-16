# NotchRail 开发准则与 Agent 协作规范 (AGENTS.md)

本文件是 **NotchRail** 项目的全局架构与开发指引，面向所有参与本仓库特性开发、重构优化、故障排查与日常维护的 AI 编程智能体（Agents）及人类开发者。任何代码修改均须严格遵守本规范。

---

## 目录
0. [事实唯一归属（Single Home per Fact）](#0-事实唯一归属single-home-per-fact)
1. [系统架构全景与模块职责](#1-系统架构全景与模块职责)
2. [核心工程哲学与架构不变量](#2-核心工程哲学与架构不变量)
3. [关键子系统实现与交互准则](#3-关键子系统实现与交互准则)
4. [研发自测与发布闭环工作流](#4-研发自测与发布闭环工作流)
5. [编码规范与协作纪律](#5-编码规范与协作纪律)

---

## 0. 事实唯一归属（Single Home per Fact）

**硬规则**：每一类事实在本仓库**有且只有一个权威「家」**；其余文档**只能引用，不得复制**——不得复述别处的定义，不得内联别处的数值。

违反此规则即制造「**文档幻觉**」：同一事实存在多个可能被读到的地方，AI 编程智能体便会随机采纳其中一个，产出与代码不符的方案与代码。历史上反复出现的「同一指标多处口径不一」「文档引用已删除的符号」皆源于此。

| # | 事实类型 | 唯一权威「家」 | 其余文档的义务 |
| :--- | :--- | :--- | :--- |
| 1 | 领域术语的词义与禁用别名 | `CONTEXT.md` | 只引用词条名，不得重定义；该文件**零实现细节** |
| 2 | 实体 / 枚举 / 状态机 / 字段的**结构**与签名 | `docs/DOMAIN_MODEL.md` | 术语含义引 `CONTEXT.md`；ADR 只引编号 |
| 3 | 架构不变量、模块分层与职责、编码与协作纪律 | 本文件（`AGENTS.md`） | 唯一权威，其他文档不得重述 |
| 4 | 跨版本架构决策的**理由** | `docs/adr/NNNN-*.md` | 只引用 ADR 编号，不复述决议内容 |
| 5 | 版本演进史（各版本交付了什么、是否闭环） | `docs/DEVELOPMENT_PLAN.md` | 唯一版本清单 |
| 6 | 版本 → Issue 编号映射与 Spec 查询约定 | `docs/agents/issue-tracker.md` | 不得手写版本清单，一律由 `gh` 现查 |
| 7 | 单个已闭环版本的详细规格 | `docs/SPEC.md`（历史归档，**非现状**） | 新版本规格一律进 GitHub Issues |
| 8 | 面向用户的安装与特性说明 | `README.md` | 不得陈述架构不变量，不得内联数值 |
| 9 | **一切数值常量与阈值** | **代码中的具名常量声明** | 文档**只准引用常量名，禁止内联数值** |

**推论（须自觉遵守）**：

- 需要引用数值时写常量名（如 `OverflowCalculator.NOTCH_CORNER_SAFETY_MARGIN`），**不要写出数值本身**；代码若尚无具名常量，先抽常量再引名。
- 需求的第一来源永远是 GitHub Issues（见 `docs/agents/issue-tracker.md`）；`docs/SPEC.md` 只是滞后归档，不可当作现状。
- 若某事实无处安放、或与既有文档冲突，**先向用户澄清再落笔**，不要新增第三处出处。
- 一致性由 `scripts/check_docs.sh` 机器校验兜底，改动文档后须本地跑一次。

---

## 1. 系统架构全景与模块职责

NotchRail 是一款基于 Swift 与 SwiftUI 构建的 macOS 原生沉浸式物理刘海灵动岛与状态栏管理工具。整个工程分为主应用入口（`NotchRail`）与核心框架（`NotchRailKit`）。

### 1.1 核心模块分层

```
NotchRail/
├── Sources/NotchRail/               # 主应用入口 (NotchRailApp)
└── Sources/NotchRailKit/
    ├── App/                         # 应用生命周期代理与状态项常驻托盘管理 (AppDelegate, StatusItemManager)
    ├── Screen/                      # 屏幕拓扑、几何测绘、全屏 Space 检测与光标监听
    ├── MenuBar/                     # 窗口扫描 (SkyLight CGS)、AX 身份映射、溢出计算、图标截取管线
    ├── Island/                      # 灵动岛 UI 视图体系、自适应动态耳翼、流体拖拽重排、悬停/点击交互状态机
    ├── Window/                      # 按 displayID 注册的每屏 NSPanel 视口、Frame 同步与事件物理直通管理
    ├── Persistence/                 # UserPreferences 领域模型 (含 customItemOrder) 与 PreferenceStore 持久化
    ├── Settings/                    # 现代化偏好设置中心 (常规、悬停动效、应用管理、诊断)
    ├── Permissions/                 # 辅助功能 (AX) 与屏幕录制 (CGScreenCapture) 权限流
    ├── Spike/                       # 真实硬件端到端诊断运行器 (22 个用例，编号 1–24 含历史断档)
    └── Bridging/                    # CoreGraphics / SkyLight 私有 CGS API 桥接
```

### 1.2 单向数据流动拓扑

整个系统的状态流转严格遵循单向数据流原则，禁止逆向依赖：

```
[WindowServer 窗口层级 Layer 25]
                │
                ▼
      MenuBarWindowScanner (毫秒级 CGS 状态项枚举)
                │
                ▼
      MenuBarAXResolver (增量空间坐标 AXPosition 邻近反查真实应用)
                │
                ▼
       OverflowCalculator (基于屏幕跨度与刘海安全余量的纯几何溢出计算)
                │
                ▼
          IconResolver (逐窗真机截图、透明裁切与视觉相等性对比)
                │
                ▼
     MenuBarSyncCoordinator (原子发布单屏快照 MenuBarSnapshot)
                │
                ▼
      IslandRootView / IslandIconCell (SwiftUI GPU 驱动流体渲染与事件路由)
```

---

## 2. 核心工程哲学与架构不变量

任何改动不得破坏以下四项核心工程基石：

### 2.1 单一真实来源与多屏物理隔离 (Single Source of Truth)
- 每一台显示器（`displayID`）拥有完全独立的数据空间、几何配置、菜单栏快照、灵动岛视口与交互状态机；
- **屏幕数量不设上限，一律按 `displayID` 注册与取用**：视口与状态机分别注册于 `IslandWindowCoordinator.panelsByDisplay` / `machinesByDisplay`，严禁出现「主槽位 / 副槽位」这类写死屏数的结构，也严禁任何 `primary*` / `external*` 式的成对字段（否则第三块屏起将静默失效）；
- **坚决禁止任何跨屏快照继承或全局兜底借用**（例如严禁使用 `snapshotsByDisplay[displayID] ?? 任一默认快照`），杜绝跨屏坐标污染与虚假溢出；
- **严禁任何跨屏图元借用**：每块屏的图标**只能由该屏自己采到**的结果供给。全局应用图元注册表、跨窗口持久缓存、以及由两者构成的 `??` 级联回退**一律禁止**作为图元来源；图元缓存键必须包含 `displayID`，**不得以裸 `windowID` 充当稳定键**（窗口服务器在状态项集合增删时整体重建菜单栏项窗口，裸窗口 ID 随即全量失配）。理由与实测见 [ADR 0013](docs/adr/0013-per-display-icon-capture.md)；
- **跨屏共享一律默认关闭，且只能由用户显式开启**：涉及多屏共用的**偏好数据**（如状态项排序）**默认按屏独立**，共享须由用户在设置中主动选择；升级不得静默把既有数据跨屏合并。注意与上一条的分野 —— **图元数据的跨屏借用没有商量余地**（它决定「这块屏的内容是否正确」），而**偏好数据允许跨屏但必须经用户同意**（它只关乎「用户想怎么摆」）。理由见 [ADR 0014](docs/adr/0014-per-display-item-order.md)；
- **严禁任何共享全局状态机**：每屏状态机物理隔离，`stateMachine(for:)` / `panel(for:)` 未命中一律 Fail-Fast 返回 nil，绝不回退到别的屏幕或某个单例；
- **渲染对账不得改写全局焦点屏**：`applyDisplayAndVisibilityRules` 必须是幂等的按屏对账，焦点跟随只能由 `MouseMonitor` 在真实用户交互处驱动，否则会与 `ScreenManager.$currentGeometry` 的订阅构成重入环；
- 遇到数据异常应遵循 Fail-Fast（快速失败）原则并在源头阻断，严禁用“猜测性兜底”掩盖底层系统事实。

### 2.2 零降级原生位图截取 (Zero-Fallback Real Capture)
- **100% 真实菜单栏截图**：通过私有 CoreGraphics 桥接对**本屏菜单栏区域**执行区域级合成取图，再按各项真实几何裁出单项位图并执行透明边距动态裁剪，保留真实长宽比例与原生观感；
  - **绝不可改用逐窗截图**：该 API 对非活动屏的窗口返回全透明、对刘海带内的项返回空图。这两者都是**API 读取限制**，不是「窗口未被绘制」——一旦混为一谈，就会把取图路径选错当成平台死界，并催生跨屏供图这类反向补丁（见 [ADR 0013](docs/adr/0013-per-display-icon-capture.md)）；
- **像素级比对（Visual Equality）**：仅在像素内容真正变更时触发发布更新，静态项保持 0 渲染开销，动态数值项（网速、时钟、天气）鲜活实时刷新；
- **严禁降级**：绝不允许使用彩色 Dock 应用图标或通用 SF Symbol 充当单色菜单栏剪影的占位符；加载态统一采用中性呼吸脉动胶囊，加载完成后原位无感替换。

### 2.3 硬件级透明事件直通 (Zero-Occlusion Passthrough)
- **稳固吸顶视口架构**：灵动岛窗口采用稳定常驻吸顶视口，通过 SwiftUI 动画驱动形变，杜绝频繁创建/销毁窗口导致的跳动；
- **物理穿透管理**：通过 `IslandWindowCoordinator` 联动 `MouseMonitor` 精确控制 `ignoresMouseEvents`。仅在灵动岛展开区域或紧凑胶囊实际像素有效区内认领鼠标事件，其余透明区域 100% 物理直通底层应用（确保底层 Chrome 标签栏、书签栏及操作毫无阻滞）。

### 2.4 纯物理几何判定 (Pure Physical Geometry)
- 溢出项判定（`OverflowCalculator`）必须完全基于真实物理几何与碰撞判定：
  - **内建物理刘海屏**：基于物理 X 坐标与刘海右侧过渡区安全余量（余量常量见 `OverflowCalculator.NOTCH_CORNER_SAFETY_MARGIN`）；
  - **平直外接显示器**：基于前台 App 菜单右边缘碰撞阈值（阈值常量见 `OverflowCalculator.APP_MENU_COLLISION_SAFETY_MARGIN`）；
- **严禁依赖 `!item.isOnScreen`**：在 macOS 切换 Space 或全屏时，WindowServer 会将所有菜单项标记为未上屏，依赖该状态会导致菜单项被误判为全量溢出；
- 仅当菜单项的水平跨度确实落在当前屏幕有效宽度内时才参与计算（该边界判定内联于 `OverflowCalculator.resolve`，不存在独立的辅助函数），非本屏窗口绝不可标记为本屏溢出项。

---

## 3. 关键子系统实现与交互准则

### 3.1 多显示器物理适配准则
macOS 用户常混合使用内建刘海屏与外接平直显示器，两者的渲染与几何特性存在本质差异：
- **内建刘海屏 (`hasPhysicalNotch == true` 或内建主屏)**：
  - 状态栏高度以系统安全区（`safeAreaTop`）实测为准；无安全区数据时兜底 `NotchGeometry.DEFAULT_STATUS_BAR_HEIGHT`；
  - 顶部保留硬件级喇叭口耳翼（半径常量见 `IslandTheme.CornerRadius.TOP_EAR`）；
  - 主屏视口（`IslandWindowCoordinator.panelsByDisplay` 中主屏基准屏那一项）常态常驻守护于此，运行本屏独立状态机，呈现紧凑态胶囊（Compact Island）。
- **外接平直显示器 (`hasPhysicalNotch == false && !isBuiltIn`)**：
  - **彻底废除 160pt 虚拟假刘海**：平直外接屏 `physicalNotchRect == .zero`，消除假刘海与常驻黑胶囊的视觉污染；
  - **动态菜单碰撞判定**：溢出判定完全基于前台 App 菜单右边缘碰撞（阈值常量见 `OverflowCalculator.APP_MENU_COLLISION_SAFETY_MARGIN`），仅当三方项被挤压时才判定为溢出；
  - **常态 100% 隐形**：平直外接屏折叠常态下完全隐退（`alpha = 0`，`ignoresMouseEvents = true`），底层窗口 100% 物理直通；
  - **展开统一黑仿真灵动岛设计**：展开态保持统一纯黑吸光底座、微光渐变描边与顶部标志性外展平滑喇叭弧（耳翼半径同刘海屏，见 `IslandTheme.CornerRadius.TOP_EAR`）；
  - **多屏独立多实例架构与隔离状态机**：每块屏幕各持一台物理隔离的 `IslandStateMachine` 与一个独立视口，全部按 `displayID` 注册于 `IslandWindowCoordinator`（见 §2.1）；心跳由 `MenuBarSyncCoordinator` 按展开屏集合集中聚合；触碰任意外接屏顶部中央热区即时原位平滑展开，收起后原位淡出，杜绝跨屏抢夺与徽标闪烁；
  - **屏幕数量无上限**：智能兼容 MacBook 内置刘海、单平直屏（Mac mini / 盒盖模式）、双外接平直屏乃至更多屏幕的任意组合；主屏视口常驻，其余屏视口按需装载（展开中或存在溢出项时保留，空闲宽限后卸载），**屏幕增减一律由幂等对账处理，不得写死屏数**；
- **多轨物理自律与按屏独立取图 (Per-Display Icon Capture)**：
  - 各显示器轨道绝对独立闭环，各管本屏物理几何、窗口扫描、溢出判定与**图标采集**，**坚决杜绝跨屏窗口配对或图元借用**；
  - **每块屏的菜单栏项都被窗口服务器真实绘制**，非活动屏同样如此（实测：非活动屏状态项区域图标完整可见，且比活动屏**多出**被刘海挤占的项）。所以「非活动屏看不到图标」不是绘制问题而是**取图 API 选错**，须按 §2.2 走区域级合成；
  - **活动菜单栏屏 = 前台窗口所在屏**（**不是**光标所在屏）。该归属可由程序显式移交，双向可逆、可重复。其纯枚举镜像判据是 `kCGWindowName`：**活动屏的项被抹为 `Item-0`、非活动屏的项保留实名 bundle id**，两者逐屏互补——可据此无授权地判定哪块屏是活动屏；
  - **非活动屏不得对外承诺点击可用**：非活动屏原位派发的可达性**尚未取证**（本机外壳无辅助功能权限，事件合成类实验只能走应用内诊断运行器）。在取得证据之前，只允许走「先显式移交活动权、再派发」这一条路径——其两段均已实证，而「非活动屏原位派发」仍属未验证假设，不得写入实现或对外承诺；
  - **身份键与图元键分离**：`bundleIdentifier` 只用于身份识别（AX 配对、偏好键），**绝不可作为跨屏取图索引**。`preferenceKey` 用 `bundleIdentifier` 时须保证逐项唯一——不同状态项共用同一 Bundle ID（例如把时钟 / 电池 / Wi-Fi 等系统项统一写成控制中心宿主 ID）会让偏好排序互相覆盖、张冠李戴；

### 3.2 全屏空间 (Full-Screen Spaces) 沉浸协同
- **全屏判定标准**：
  - 在外接扩展屏上，即使处于普通桌面，`visibleFrame.maxY` 也严格等于 `frame.maxY`，因此**绝不可通过 `visibleFrame` 高度差判定全屏**；
  - 必须通过当前激活应用主窗口的 `AXFullScreen` 原生属性及其在目标屏幕边界的相交性进行判定。
- **顶边缘热区唤醒与淡退**：
  - 全屏隐退态下，面板 `alpha = 0` 且 `ignoresMouseEvents = true`；
  - 当光标碰触屏幕顶边缘热区（阈值常量见 `NotchGeometry.TOP_EDGE_HOT_ZONE_THRESHOLD`）时，随系统菜单栏平滑淡入唤出紧凑态；移出交互区后经过移出宽限（时序见 §3.3）平滑淡出，全屏项点击后自动退出唤醒。

### 3.3 交互状态机与防抖时序 (`IslandStateMachine`)
- **多通道触发**：支持「仅鼠标悬停」、「仅鼠标点击」、「悬停或点击（默认）」三档，三档**两两可区分**；语义只在 `TriggerMode.respondsToHover` / `TriggerMode.respondsToCapsuleTap` 两个谓词里定义一次，视图层、状态机、鼠标监听一律引用谓词，**严禁**各自再写 `== .click` 式比较（ADR 0016 决议 3）；
- **胶囊点击恒为切换，且唯一入口是 `IslandStateMachine.handleCapsuleTap`**：`.click` / `.hoverAndClick` 两档下点第一次展开、点第二次收起；`.hover` 档**刻意不响应点击**（若响应，该档与「悬停或点击」即退化为可观察行为相同的假选择）。承载该语义的容器手势**必须**是 `.onTapGesture` —— 用 `simultaneousGesture(TapGesture())` 会与图标、设置齿轮的 `Button` 并列触发而连带收起，这正是当初误判「切换会劫持图标交互」的成因（ADR 0016 决议 1、4）；
- **点击路径的收起只有两处**：`handleCapsuleTap`（点岛本体）与「点击灵动岛以外区域」（`IslandWindowCoordinator.handleOutsideClickIfNeeded`）；前者不因 `.click` 档而失效；
- **「无遮挡时静默」优先于触发方式**：`UserPreferences.hideWhenNoOverflow` 为真且当前屏 0 溢出时，灵动岛整体隐退且**任何唤出形式一律不生效**（悬停 / 点击 / 托盘菜单命令）—— 该档的语义是「不出现」，故它压过上面三种交互方式，不得为「让用户还能唤出」而给它开特例（ADR 0015 决议 3，词义见 `CONTEXT.md` 的 `SilencedByNoOverflow`）；
- **防误触时序**（均由用户偏好驱动，下述为默认值）：
  - **移入意图识别**：延迟取 `UserPreferences.hoverExpandDelayMs`，默认值为 `IslandTheme.Timing.HOVER_EXPAND_DELAY`；鼠标快速划过刘海区域不触发展开；
  - **移出离开缓冲**：延迟取 `UserPreferences.collapseDelayMs`，默认值为 `IslandTheme.Timing.COLLAPSE_DELAY`；鼠标短暂离开灵动岛时保留 Grace Period，防止误收起；
- **点击自动收起是平台不变式，不可由偏好关闭**：触发项分发成功后**恒定**原子流转回紧凑态并触发触觉反馈（`NSHapticFeedbackManager`）。灵动岛视口层级高于原生菜单窗口，不收起则刚弹出的原生菜单被遮挡；故该行为**不提供用户开关**（ADR 0015 决议 2），任何「让它变成可选」的改动都视为回退。

### 3.4 辅助功能 (AX) 与系统代理穿透准则
- **外接屏代理反查**：macOS 在扩展屏上将三方状态项统一归入系统宿主进程代管，绝不可依据窗口的 `ownerPID` 过滤候选进程；必须由 `MenuBarAXResolver` 维护增量缓存池（`knownMenuBarPIDs`），通过空间物理位置（`AXPosition`）反查真实应用与 Bundle ID；
- **AX 条目池是全局单份，但其数据只覆盖活动屏**：`MenuBarAXResolver` 的条目池与候选 PID 池**不分屏**（全局共享一份），而实测该池只返回**活动屏**项的可用数据，非活动屏只回落到零尺寸的退化条目。因此把该池当「跨屏可共用」的共享数据源是**伪共享**——非活动屏的身份必须由窗口侧判据承担（见 §3.1 的 `kCGWindowName` 逐屏镜像判据），不得依赖池中数据，也不得为迁就该池而新增跨屏回退；
- **子进程防挂起过滤**：扫描候选应用时必须过滤排除 `WebKit.WebContent` / `renderer` 等子进程，防止 Accessibility IPC 出现秒级以上超时；日常刷新保持增量扫描耗时 $< 10\text{ms}$。
- **点击派发目标恒为状态项窗口的 owner**：合成事件的目标进程必须与事件携带的「鼠标下窗口」字段同属一个进程。状态项窗口在窗口服务器层恒归控制中心宿主所有，故目标恒取 `MenuBarItem.clickTargetPID`（即窗口 owner），由宿主完成菜单栏项激活并转交真实应用。**绝不可改投 AX 反查出的真实归属应用**（`sourcePID` 只服务于图元归属与 AX 元素定位）：该进程内不存在此 `windowID` 对应的窗口，事件会被静默丢弃，表现即「岛内第三方图标点了没反应」。此规则曾被反向着写，理由见 `docs/adr/0010`。
- **左键单击与辅助点击走不同通道**：左键单击走宿主激活通道（私有字段 + `postToPid`），对未参与合成的溢出项同样有效；辅助点击走**会话事件流 + 目标窗口字段**通道（`CGEvent.post(tap: .cgSessionEventTap)`，事件携带 `MenuBarClickEventFactory` 组装的目标窗口字段），投递前须让自有视口临时穿透，并等待穿透标志实际生效。
  - **辅助点击不以 `isOnScreen` 分流**：该项是否被窗口服务器合成，与本通道成败无关；可达性的唯一前置条件是「目标项持有有效 `windowID`」。窗口服务器把事件携带的目标窗口字段当作**路由覆盖**，因此被刘海挤占、未参与合成的溢出项同样能收到真实右键。此规则曾按相反方向写入并被 [ADR 0011](docs/adr/0011-secondary-click-session-event-routing.md) 取代，理由见该 ADR。
  - **判据是「响应」而非「不可达」**：派发后开启响应观察窗（常量见 `MenuBarItemClicker.SECONDARY_RESPONSE_WINDOW_NANOSECONDS`），窗内出现新的菜单层窗口即视为已响应；否则返回 `.noResponse`，由调用方给出可见反馈（岛内图标 Shake + 触觉），**不得静默**。`noResponse` 的语义是「事件已送达但该项没有辅助点击处理」，**不是**「不可达」。
    - **判据不得按 owner 排除本进程**：NotchRail 自身状态项的托盘菜单由本进程弹出、同样落在菜单层，把它当噪声排除会让「右键自家被挤占的溢出图标，菜单确实弹出」反过来被判成无响应（岛内 Shake 且灵动岛不收起的自相矛盾反馈）。理由与真机取证见 [ADR 0012](docs/adr/0012-secondary-response-accepts-own-menu.md)。
  - **严禁改发左键冒充右键**：左键在部分应用是「立即动作」而非菜单（静音 / 暂停 / 开关），冒充与用户意图相悖（理由见 [ADR 0010](docs/adr/0010-status-item-owner-event-dispatch.md)）。
- **事件字段唯一构造器**：点击事件的字段组装（私有字段、按键号、`clickState`）一律经 `MenuBarClickEventFactory` 取用，生产路径与诊断路径不得各自拼装 —— 两侧字段漂移会让诊断路径静默掩盖生产缺陷。
- **不提供左键双击**：`MenuBarClickKind` 只有 `.single` 与 `.secondary` 两种。双击是 `.leftMouseDown` 的 `clickCount == 2`，与辅助点击（触控板双指 = 鼠标右键）正交；一旦按 `clickCount >= 2` 分流，双击间隔内对同一图标的第二次单击会被误吞，表现为「单击时灵时不灵」。

---

## 4. 研发自测与发布闭环工作流

代码修改完成后，不得盲目提交，必须严格依次执行以下“三步自检法”：

```
[代码修改] ➔ 1. swift build ➔ 2. swift test ➔ 3. swift run NotchRail --spike ➔ [人工验收 / 打包]
```

### 4.1 编译与静态检查
```bash
swift build
```
- 必须保证 **0 Error，0 Warning**；若引入新 API 须确保兼容 macOS 14.0+。
- **工具链前提（SDK 27 宏插件陷阱）**：若本机仅装 CommandLineTools 且其 `MacOSX.sdk` 已指向 macOS 27 系列，SwiftUI 的 `@State` 等已改为宏实现，而宏插件 `SwiftUIMacros` **只随完整 Xcode 分发**，会导致全项目编译失败并刷出大量**级联假错**（`self is immutable`、`cannot find '$searchText' in scope`、`generic parameter 'SelectionValue' could not be inferred` 等）。此时**切勿修改业务代码**，把 SDK 指回 26.5 即可（`--disable-sandbox` 供受限/沙箱环境使用）：

  ```bash
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  swift build --disable-sandbox
  ```

### 4.2 单元测试全量回归
```bash
swift test
```
- 保证 `ScreenManagerTests`、`MouseMonitorTests`、`OverflowCalculatorTests`、`IslandStateMachineTests` 等单元测试 100% 通过。
- **工具链前提（勿谎称通过）**：`swift test` 依赖完整 Xcode 提供的 `xctest`。若本机仅有 CommandLineTools，`swift test` 只会编译测试包后**静默退出**（退出码 0 但不执行任何用例），此时**不得声称单测已通过**；须在装有完整 Xcode 的环境（或 CI）中执行后方可下结论。

### 4.3 现场真实硬件诊断 (`SpikeRunner`)
```bash
swift run NotchRail --spike
```
在具备外接屏或物理刘海的环境中运行，重点核查以下输出指标：
1. **算法自测**：内置全量边界验证 Case 全部通过；
2. **扫描耗时**：日常增量扫描期望 $< 10\text{ms}$（与 §3.4 为同一契约，本文件为该指标的唯一定义处）；超过 $50\text{ms}$ 即视为异常，须排查根因；
3. **图标解析率**：成功解析图标率必须为 **100%**，全部状态为 `[State: loaded]`，严禁残留 `[State: pending]`；
4. **屏幕几何对齐**：显示器状态栏测量高度与系统实际高度一致。

### 4.4 本地打包与签名
```bash
./scripts/build_app.sh
```
- 自动生成具备 `NotchRail-Dev` 稳定开发证书签名的制品：
  - `build/NotchRail.app`
  - `build/NotchRail-v0.0.x.dmg`
  - `build/NotchRail-v0.0.x.zip`

---

## 5. 编码规范与协作纪律

### 5.1 编码规范
- **语言习惯**：代码注释统一使用中文，变量名、函数名、文件名遵循标准英文命名；
- **命名惯例**：
  - 类名、结构体、枚举名：`PascalCase`；
  - 常量：`UPPER_SNAKE_CASE`；
- **代码整洁**：严禁过度工程化与臆想抽象；任务完成后必须彻底清理临时插入的 `print`、`NSLog` 等调试打印；
- **严禁擅自添加兜底与旧逻辑兼容代码**：禁止在未经明确讨论与用户授权的情况下，自行添加任何形式的猜测性兜底（如多层 `?? fallback` 级联、跨屏借用快照等）、臆想的容错补丁或对废弃旧逻辑的兼容层。遇到异常必须遵循 Fail-Fast（快速失败）原则暴露真实问题并在源头阻断，严禁用“私自兜底”掩盖底层架构缺陷与事实。

### 5.2 Git 提交规范
- **禁止未经许可的提交**：不要主动 commit / push，除非用户发出明确指令；
- **提交信息格式**：必须使用中文，严格遵循格式：`类型: 简短描述`；
  - 允许类型：`feat` / `fix` / `refactor` / `docs` / `chore` / `style` / `perf` / `test`；
  - 示例：`fix: 修复外接屏状态项真实应用名称匹配异常`。

### 5.3 安全协作红线
- **破坏性命令绝对禁令**：
  - **严禁执行** `git push --force` 或 `git push --force-with-lease`；
  - **严禁执行** `git reset --hard`；
  - 遇到需要回滚历史的场景，必须通过前向安全提交（Forward Commit）或精准安全检出解决。

---

> **致 Agent 协作备忘**：遇到不确定的系统行为或复杂设计决策时，先向用户提问澄清，方案确认后再动手；切忌自行揣测假设，更切忌为追求局部微小指标而破坏全局数据一致性闭环。
