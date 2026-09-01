# NotchRail · 开发总方案 (v2 Baseline)

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
           Hover 停顿 100~150ms
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
* 尺寸：约 `172 × 36 pt`（贴合刘海轮廓，全屏幕统一刘海包边造型）。
* 状态指示：当存在溢出图标时，胶囊内显示图标数量微标（如 `tray.full.fill`）。

### Level 2：Extended Menu Bar (扩展菜单栏)
* 鼠标进入刘海区域并停留超过 100~150ms 时平滑展开（单行横向滑动展示）。
* **展示内容**：按 `windowID` 截取的高清实时像素位图。
* **交互反馈**：点击图标通过 `CGEvent` 派发点击；失败给予轻量 Shake 抖动与触觉提示。
* **离开收起**：鼠标离开灵动岛后延迟 300ms 自动收回为 Compact 态。

### Level 3：Settings (偏好设置窗口)
* 独立窗口：
  * 开机自启 (`SMAppService`)
  * 展开/收起延迟灵敏度滑块
  * 忽略/隐藏特定 App
  * 权限检查与诊断

---

## 3. 技术栈与架构选型

* **开发语言**：Swift 5.9+ / Swift 6.0
* **模块架构**：`NotchRailKit`（核心业务库）+ `NotchRail`（可执行 App 容器）
* **UI 框架**：SwiftUI + AppKit (`IslandPanel`: `.screenSaver` 级非激活 NSPanel)
* **系统底层**：
  * `Bridging`：SkyLight 私有 API (`CGSGetProcessMenuBarWindowList`, `CGSGetScreenRectForWindow`)
  * `CoreGraphics`：`CGWindowListCreateImageFromArray`、`CGEvent.postToPid`
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
│       │   └── AppDelegate.swift             # Agent 模式与服务生命周期管理
│       │
│       ├── Bridging/
│       │   └── Bridging.swift                # SkyLight CGS 私有 API 桥接层
│       │
│       ├── Window/
│       │   ├── IslandPanel.swift             # 穿透所有 Space、全透明、无阴影 NSPanel
│       │   └── IslandWindowCoordinator.swift # 窗口 frame 锚定与多屏迁移调度
│       │
│       ├── Island/
│       │   ├── IslandRootView.swift          # 灵动岛根容器
│       │   ├── CompactIslandView.swift       # 常驻紧凑态胶囊
│       │   ├── ExtendedMenuBarView.swift     # 展开态单行滑动菜单栏
│       │   ├── IslandIconCell.swift          # 单个图标单元格与 Shake 动效
│       │   ├── IslandBackground.swift        # 统一 Notch 造型底座与微光描边
│       │   ├── IslandStateMachine.swift      # 悬停防抖与展开/收起状态机
│       │   └── ShakeEffect.swift             # 错误抖动 GeometryEffect
│       │
│       ├── MenuBar/
│       │   ├── MenuBarItem.swift             # 实体模型 (以 CGWindowID 为主键)
│       │   ├── MenuBarSnapshot.swift         # 菜单栏快照聚合
│       │   ├── MenuBarWindowScanner.swift    # 基于 SkyLight 的高效窗口枚举器
│       │   ├── MenuBarItemClicker.swift      # 基于 CGEvent postToPid 的原生点击器
│       │   ├── OverflowCalculator.swift      # 几何碰撞溢出计算器 (纯函数)
│       │   ├── IconResolver.swift            # 三级图标解析降级管道
│       │   └── MenuBarSyncCoordinator.swift  # 工作区事件与心跳同步协调器
│       │
│       ├── Screen/
│       │   ├── ScreenManager.swift           # 多显示器测量与当前焦点屏管理
│       │   ├── NotchGeometry.swift           # 屏幕与刘海几何值对象
│       │   └── MouseMonitor.swift            # 全局鼠标跨屏追踪
│       │
│       ├── Permissions/
│       │   ├── PermissionManager.swift       # 辅助功能 + 屏幕录制权限检测
│       │   ├── PermissionGuideView.swift     # 权限引导与系统设置跳转面板
│       │   └── PermissionWindowCoordinator.swift
│       │
│       ├── Persistence/
│       │   ├── PreferenceStore.swift         # 响应式持久化配置中心
│       │   └── UserPreferences.swift         # 偏好数据结构
│       │
│       ├── Settings/
│       │   ├── SettingsView.swift            # 偏好设置窗口视图
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
        └── ScreenManagerTests.swift
```

---

## 5. 重构分阶段实施计划与状态

| 阶段 | 核心任务 | 交付物 / 状态 |
| :--- | :--- | :--- |
| **S0：可行性 Spike** | 验证 SkyLight 窗口枚举、按 `windowID` 截取遮挡图标与 `postToPid` 点击 | ✅ **实测通过** |
| **S1：枚举与判定重构** | 落地 `Bridging` + `MenuBarWindowScanner`，接入 `OverflowCalculator` | ✅ **已闭环** |
| **S2：图像与点击重构** | `IconResolver` 改按 `windowID` 截取实时位图，`MenuBarItemClicker` 合成原生点击 | ✅ **已闭环** |
| **S3：清理与权限** | 删除 AX 相关废弃代码，补充屏幕录制权限检查与引导 | ✅ **已闭环** |
| **S4：多屏与回归** | 全屏幕统一刘海造型、跨屏迁移展开态保留、单行横向排布 | ✅ **已闭环** |
