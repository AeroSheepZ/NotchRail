# NotchRail 开发准则与 Agent 协作规范 (AGENTS.md)

本文件是 **NotchRail** 项目的全局架构与开发指引，面向所有参与本仓库特性开发、重构优化、故障排查与日常维护的 AI 编程智能体（Agents）及人类开发者。任何代码修改均须严格遵守本规范。

---

## 目录
1. [系统架构全景与模块职责](#1-系统架构全景与模块职责)
2. [核心工程哲学与架构不变量](#2-核心工程哲学与架构不变量)
3. [关键子系统实现与交互准则](#3-关键子系统实现与交互准则)
4. [研发自测与发布闭环工作流](#4-研发自测与发布闭环工作流)
5. [编码规范与协作纪律](#5-编码规范与协作纪律)

---

## 1. 系统架构全景与模块职责

NotchRail 是一款基于 Swift 与 SwiftUI 构建的 macOS 原生沉浸式物理刘海灵动岛与状态栏管理工具。整个工程分为主应用入口（`NotchRail`）与核心框架（`NotchRailKit`）。

### 1.1 核心模块分层

```
NotchRail/
├── Sources/NotchRail/               # 主应用生命周期 (NotchRailApp, AppDelegate)
└── Sources/NotchRailKit/
    ├── Screen/                      # 屏幕拓扑、几何测绘、全屏 Space 检测与光标监听
    ├── MenuBar/                     # 窗口扫描 (SkyLight CGS)、AX 身份映射、溢出计算、图标截取管线
    ├── Island/                      # 灵动岛 UI 视图体系、自适应动态耳翼、悬停/点击交互状态机
    ├── Window/                      # NSPanel 悬浮面板、吸顶视口、Frame 同步与事件物理直通管理
    ├── Settings/                    # 现代化偏好设置中心 (常规、悬停动效、应用管理、诊断)
    ├── Permissions/                 # 辅助功能 (AX) 与屏幕录制 (CGScreenCapture) 权限流
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
- 每一台显示器（`displayID`）拥有完全独立的数据空间、几何配置与菜单栏快照；
- **坚决禁止任何跨屏快照继承或全局兜底借用**（例如严禁使用 `snapshotsByDisplay[displayID] ?? latestSnapshot`），杜绝跨屏坐标污染与虚假溢出；
- 遇到数据异常应遵循 Fail-Fast（快速失败）原则并在源头阻断，严禁用“猜测性兜底”掩盖底层系统事实。

### 2.2 零降级原生位图截取 (Zero-Fallback Real Capture)
- **100% 真实菜单栏截图**：通过私有 CoreGraphics 桥接对每个状态项进行独立逐窗截图，并执行透明边距动态裁剪，保留真实长宽比例与原生观感；
- **像素级比对（Visual Equality）**：仅在像素内容真正变更时触发发布更新，静态项保持 0 渲染开销，动态数值项（网速、时钟、天气）鲜活实时刷新；
- **严禁降级**：绝不允许使用彩色 Dock 应用图标或通用 SF Symbol 充当单色菜单栏剪影的占位符；加载态统一采用中性呼吸脉动胶囊，加载完成后原位无感替换。

### 2.3 硬件级透明事件直通 (Zero-Occlusion Passthrough)
- **稳固吸顶视口架构**：灵动岛窗口采用稳定常驻吸顶视口，通过 SwiftUI 动画驱动形变，杜绝频繁创建/销毁窗口导致的跳动；
- **物理穿透管理**：通过 `IslandWindowCoordinator` 联动 `MouseMonitor` 精确控制 `ignoresMouseEvents`。仅在灵动岛展开区域或紧凑胶囊实际像素有效区内认领鼠标事件，其余透明区域 100% 物理直通底层应用（确保底层 Chrome 标签栏、书签栏及操作毫无阻滞）。

### 2.4 纯物理几何判定 (Pure Physical Geometry)
- 溢出项判定（`OverflowCalculator`）必须完全基于真实物理几何与碰撞判定：
  - **内建物理刘海屏**：基于物理 X 坐标与刘海右侧过渡区安全余量（`notchRightEdge + 12pt`）；
  - **平直外接显示器**：基于前台 App 菜单右边缘碰撞阈值（`appMenuRightEdge + 12pt`）；
- **严禁依赖 `!item.isOnScreen`**：在 macOS 切换 Space 或全屏时，WindowServer 会将所有菜单项标记为未上屏，依赖该状态会导致菜单项被误判为全量溢出；
- 仅当菜单项的水平跨度确实落在当前屏幕有效宽度内（`isWithinScreenSpan`）时参与计算，非本屏窗口绝不可标记为本屏溢出项。

---

## 3. 关键子系统实现与交互准则

### 3.1 多显示器物理适配准则
macOS 用户常混合使用内建刘海屏与外接平直显示器，两者的渲染与几何特性存在本质差异：
- **内建刘海屏 (`hasPhysicalNotch == true`)**：
  - 状态栏高度以系统安全区（通常为 32pt 或 34pt）为准；
  - 顶部保留 5pt 硬件级喇叭口耳翼（`topEarRadius = IslandTheme.CornerRadius.TOP_EAR`，默认 5.0pt）；
  - 全局单例 `IslandPanel` 常态常驻守护于此，呈现紧凑态胶囊（Compact Island）。
- **外接平直显示器 (`hasPhysicalNotch == false`)**：
  - **彻底废除 160pt 虚拟假刘海**：平直外接屏 `physicalNotchRect == .zero`，消除假刘海与常驻黑胶囊的视觉污染；
  - **动态菜单碰撞判定**：溢出判定完全基于前台 App 菜单右边缘碰撞（`appMenuRightEdge + 12pt`），仅当三方项被挤压时才判定为溢出；
  - **常态 100% 隐形**：无溢出或未激活时面板完全隐退（`alpha = 0`，`ignoresMouseEvents = true`），底层窗口 100% 物理直通；
  - **展开采用吸顶平直托轨 (Floating Shelf)**：展开时顶部耳翼半径必须置 0（`topEarRadius = 0.0`），呈现无假刘海的原生吸顶悬浮托轨；
  - **视口借调流转架构 (Viewport Lease)**：全局单例 `IslandPanel` 常态守护在 MacBook 物理刘海屏，仅在外接屏检测到溢出且光标在顶部中央热区停留达阈值时原子借调展开，收起后无感归位回主刘海屏；
  - **状态栏高度探测**：状态栏高度必须通过 WindowServer 状态栏窗口（Layer 24）动态探测（通常为 30pt 或 31pt），严禁硬编码 34.0pt。

### 3.2 全屏空间 (Full-Screen Spaces) 沉浸协同
- **全屏判定标准**：
  - 在外接扩展屏上，即使处于普通桌面，`visibleFrame.maxY` 也严格等于 `frame.maxY`，因此**绝不可通过 `visibleFrame` 高度差判定全屏**；
  - 必须通过当前激活应用主窗口的 `AXFullScreen` 原生属性及其在目标屏幕边界的相交性进行判定。
- **顶边缘热区唤醒与淡退**：
  - 全屏隐退态下，面板 `alpha = 0` 且 `ignoresMouseEvents = true`；
  - 当光标碰触屏幕顶边缘热区（$\le 2\text{pt}$）时，随系统菜单栏平滑淡入唤出紧凑态；移出交互区后经过 300ms 缓冲平滑淡出，全屏项点击后自动退出唤醒。

### 3.3 交互状态机与防抖时序 (`IslandStateMachine`)
- **多通道触发**：支持「鼠标悬停（默认）」、「仅点击展开」、「悬停或点击」三种交互方式；
- **防误触时序**：
  - **移入意图识别（120ms）**：鼠标快速划过刘海区域不触发展开；
  - **移出离开缓冲（300ms）**：鼠标短暂离开灵动岛时保留 Grace Period，防止误收起；
- **点击自动收起**：触发项分发后，根据用户偏好原子流转回紧凑态并触发触觉反馈（`NSHapticFeedbackManager`）。

### 3.4 辅助功能 (AX) 与系统代理穿透准则
- **外接屏代理反查**：macOS 在扩展屏上将三方状态项统一归入系统宿主进程代管，绝不可依据窗口的 `ownerPID` 过滤候选进程；必须由 `MenuBarAXResolver` 维护增量缓存池（`knownMenuBarPIDs`），通过空间物理位置（`AXPosition`）反查真实应用与 Bundle ID；
- **子进程防挂起过滤**：扫描候选应用时必须过滤排除 `WebKit.WebContent` / `renderer` 等子进程，防止 Accessibility IPC 出现 1.5s 以上超时；日常刷新保持增量扫描耗时 $< 10\text{ms}$。

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

### 4.2 单元测试全量回归
```bash
swift test
```
- 保证 `ScreenManagerTests`、`MouseMonitorTests`、`OverflowCalculatorTests`、`IslandStateMachineTests` 等单元测试 100% 通过。

### 4.3 现场真实硬件诊断 (`SpikeRunner`)
```bash
swift run NotchRail --spike
```
在具备外接屏或物理刘海的环境中运行，重点核查以下输出指标：
1. **算法自测**：内置全量边界验证 Case 全部通过；
2. **扫描耗时**：`MenuBarWindowScanner` 耗时处于健康范围（日常增量 $< 50\text{ms}$）；
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
