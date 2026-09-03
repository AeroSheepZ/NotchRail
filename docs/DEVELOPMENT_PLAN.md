# NotchRail · 开发总方案 (Architecture & Roadmap)

> **把被刘海挤走的菜单栏，延伸到灵动岛**  
> 英文名称：**NotchRail**（Extended Menu Bar for MacBook Notch）

---

## 1. 产品定位与核心价值

### 核心痛点
MacBook 的物理刘海占据了菜单栏中央空间。当用户安装较多菜单栏 App 时：
```text
┌───────────────────────────────────────────┐
│               macOS Menu Bar              │
│  WiFi  VPN  Battery  Slack  Dropbox       │  [被刘海挤走：Raycast, GitHub, Timer...]
└─────────────────────┬─────────────────────┘
                      │
                 MacBook Notch
```
被挤走的图标在原生菜单栏中直接不可见，用户**看不到、点不到、找不到**。

### NotchRail 的精准定位
NotchRail 是一个**纯非侵入式的窗口级扩展菜单栏 (Window-Level Extended Menu Bar)**：
* **零侵入**：不插入 Spacer，不强行压缩、移动或篡改原生菜单栏原有布局。
* **精准补足**：灵动岛展开时，**仅展示被刘海/屏幕边缘挤出而不可见的溢出图标**（原生已展示的图标不重复出现）。
* **原生交互入口**：点击岛内溢出图标，直接向对应窗口与进程合成原生点击事件，唤起应用原有下拉菜单。

```text
                 MacBook Notch
                      │
                ┌─────▼─────┐
                │ NotchRail │ (Compact 胶囊)
                └───────────┘
                      │ 
           Hover 停顿 120ms 或 点击胶囊
                      ↓
       ┌────────────────────────────────┐
       │  Raycast  GitHub  Timer  Cloud │ (单行横向平铺被刘海挤出的溢出项)
       └────────────────────────────────┘
                      │ 点击图标 (CGEvent postToPid)
                      ↓
               原生 App 菜单弹出
```

---

## 2. 产品信息架构与形态

### Level 1：Compact Island (常驻胶囊)
* 尺寸：贴合刘海轮廓，全屏幕统一刘海包边造型。
* 状态指示：常驻数字徽标，当原生屏幕无遮挡且开启「无溢出自动隐藏」或处于未唤醒全屏空间时平滑淡出。

### Level 2：Extended Menu Bar (扩展菜单栏)
* 触发方式：支持「鼠标悬停（默认）」、「仅点击展开」、「悬停或点击」三种多通道模式。
* **展示内容**：后台原子化预热的高清实时像素位图（第 0 帧直接展示，零加载等待）。
* **交互反馈**：点击图标通过 `CGEvent` 派发点击；支持成功震动与点击后自动收起。
* **离开收起**：鼠标离开灵动岛后延迟 300ms 自动收回为 Compact 态（仅点击模式下移出不收起）。

### Level 3：Status Item (系统菜单栏常驻托盘)
* 系统顶部托盘图标（`tray.full.fill`），支持一键开关灵动岛、重新扫描、偏好设置 (⌘,) 和退出应用 (⌘Q)。

### Level 4：Settings (4 栏现代化设置中心)
* **常规**：触发方式、点击自动收起、触觉震动反馈、无溢出自动隐藏、多屏策略、托盘图标、开机自启与退出。
* **悬停与动效**：防抖与宽限时延精细滑块调节（50–300ms / 150–600ms）。
* **应用管理**：全局活动应用汇聚池、子序列模糊搜索、高清状态位图容器、两档极简状态徽标（`岛内展示 (溢出)` / `原生可见`）与一键重扫。
* **关于与诊断**：辅助功能与屏幕录制权限实时检测、一键重扫与状态刷新。

---

## 3. 技术栈与架构选型

* **开发语言**：Swift 5.9+ / Swift 6.0
* **模块架构**：`NotchRailKit`（核心业务库）+ `NotchRail`（可执行 App 容器）
* **UI 框架**：SwiftUI + AppKit (`IslandPanel`: `.screenSaver` 级非激活 NSPanel 视口架构)
* **系统底层**：
  * `Bridging`：SkyLight 私有 API (`CGSGetProcessMenuBarWindowList`, `CGSGetScreenRectForWindow`)
  * `CoreGraphics`：`CGWindowListCreateImageFromArray`、`CGEvent.postToPid`
  * `MenuBarAXResolver`：Swift `actor` 并发非阻塞后台辅助功能空间映射
* **配置持久化**：`UserDefaults`（`com.notchrail.NotchRail.preferences`）

---

## 4. 项目目录结构

```text
NotchRail/
│
├── Package.swift                             # SPM 清单 (NotchRailKit + NotchRail)
├── scripts/
│   ├── build_app.sh                          # 独立 macOS App 打包与签名脚本
│   └── test.sh                               # 全套测试与诊断脚本
│
├── Sources/
│   ├── NotchRail/
│   │   └── NotchRailApp.swift                # App 可执行入口
│   │
│   └── NotchRailKit/
│       ├── App/
│       │   ├── AppDelegate.swift             # Agent 模式与服务生命周期管理
│       │   └── StatusItemManager.swift       # 系统菜单栏托盘管理
│       │
│       ├── Bridging/
│       │   └── Bridging.swift                # SkyLight CGS 私有 API 桥接层
│       │
│       ├── Window/
│       │   ├── IslandPanel.swift             # 穿透所有 Space、全透明、无阴影 NSPanel
│       │   └── IslandWindowCoordinator.swift # 窗口 frame 锚定、先隐后迁与全屏淡入淡出调度
│       │
│       ├── Island/
│       │   ├── IslandRootView.swift          # 灵动岛根容器
│       │   ├── CompactIslandView.swift       # 常驻紧凑态胶囊
│       │   ├── ExtendedMenuBarView.swift     # 展开态单行滑动菜单栏
│       │   ├── IslandIconCell.swift          # 单个图标单元格与 Shake 动效
│       │   ├── IslandBackground.swift        # 统一 Notch 造型底座与微光描边
│       │   ├── IslandStateMachine.swift      # 多模式触发状态机控制器
│       │   └── ShakeEffect.swift             # 错误抖动 GeometryEffect
│       │
│       ├── MenuBar/
│       │   ├── MenuBarItem.swift             # 实体模型 (以 CGWindowID 为主键)
│       │   ├── MenuBarSnapshot.swift         # 菜单栏快照聚合 (含 overflowCount)
│       │   ├── MenuBarWindowScanner.swift    # 极速 SkyLight 窗口枚举器 (< 20ms)
│       │   ├── MenuBarAXResolver.swift       # Actor 并发非阻塞辅助功能解析器
│       │   ├── MenuBarItemClicker.swift      # 基于 CGEvent postToPid 的原生点击器
│       │   ├── OverflowCalculator.swift      # 几何碰撞溢出计算器 (纯函数)
│       │   ├── IconResolver.swift            # 100% 真实位图捕获与增量对比
│       │   └── MenuBarSyncCoordinator.swift  # 工作区事件、多屏预热与图标同步协调器
│       │
│       ├── Screen/
│       │   ├── ScreenManager.swift           # 多显示器测量与全屏空间监听
│       │   ├── NotchGeometry.swift           # 屏幕几何、全屏状态与顶边缘热区判定
│       │   └── MouseMonitor.swift            # 全局多屏追踪与顶边缘 3pt 碰顶唤醒
│       │
│       ├── Permissions/
│       │   ├── PermissionManager.swift       # 辅助功能 + 屏幕录制权限检测
│       │   ├── PermissionGuideView.swift     # 权限引导与系统设置跳转面板
│       │   └── PermissionWindowCoordinator.swift
│       │
│       ├── Persistence/
│       │   ├── PreferenceStore.swift         # 响应式持久化配置中心
│       │   └── UserPreferences.swift         # 偏好数据结构 (含 TriggerMode, ExternalDisplayMode)
│       │
│       ├── Settings/
│       │   ├── SettingsView.swift            # 4 栏现代化偏好设置中心视图
│       │   ├── SettingsWindowCoordinator.swift
│       │   └── LaunchAtLoginManager.swift    # SMAppService 开机自启动
│       │
│       └── Spike/
│           └── SpikeRunner.swift             # 架构自测与底层诊断套件
│
└── Tests/
    └── NotchRailTests/
        ├── OverflowCalculatorTests.swift
        ├── IslandStateMachineTests.swift
        ├── PreferenceStoreTests.swift
        ├── ScreenManagerTests.swift
        └── MouseMonitorTests.swift
```

---

## 5. 演进路线图

| 阶段 | 核心任务 | 交付物 / 状态 |
| :--- | :--- | :--- |
| **v0.0.1：MVP 验证** | 验证 SkyLight 窗口枚举、按 `windowID` 截取遮挡图标与 `postToPid` 点击 | ✅ **已闭环** |
| **v0.0.2：视口架构与稳定性** | 落地 boring.notch 视口架构、三级图标管道与双向事件调度 | ✅ **已闭环** |
| **v0.0.3：设置体系与多屏打磨** | 4 栏现代设置中心、多通道触发模式、系统托盘管理、精准多屏聚焦策略 | ✅ **已闭环** |
| **v0.0.3-perf：极速性能重构** | 扫描耗时由 2700ms 降至 16ms、后台图标原子预热、切屏先隐后迁零闪烁 | ✅ **已闭环** |
| **v0.0.4：高保真动态耳翼与空间映射** | 零降级原生位图截取、AXExtrasMenuBar 空间映射、多屏视图隔离、动态数值增量刷新 | ✅ **已闭环** |
| **v0.0.5：全屏沉浸协同与空间适配** | 原生 Full-Screen 空间沉浸式唤出协同、顶边缘 3pt 几何探测、设置应用管理瘦身重构 | ✅ **已闭环** |
| **v0.0.6+：空间拓展与交互增强** | 全局快捷键调用呼出、多屏幕独立常驻与手势微调 | 📋 **规划中** |
