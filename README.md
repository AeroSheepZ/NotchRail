# NotchRail 🏝️

> **把被 MacBook 刘海挤走的菜单栏，优雅延伸到灵动岛。**
> 
> *An extended, non-invasive menu bar mirror for MacBook notch & external displays.*

[![Release](https://img.shields.io/github/v/release/AeroSheepZ/NotchRail?color=blue&label=Release)](https://github.com/AeroSheepZ/NotchRail/releases)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B-orange.svg)](https://www.apple.com/macos/)
[![Language](https://img.shields.io/badge/Language-Swift%205.9%2B-brightgreen.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

---

## 📖 背景痛点

配备硬件刘海的 MacBook 极大压缩了顶部状态菜单栏的横向显示空间。当打开较多状态栏常驻工具（开发客户端、云同步、通信工具、系统监控等）时，超出刘海右缘的图标会被 macOS 强制推入屏幕外或直接被刘海物理遮挡，导致用户**看不见、点不到、无法接收状态变化通知**。

**NotchRail** 采用纯粹的**非侵入式镜像架构**：不注入私有布局、不插入占位符 Spacer、不干扰原生菜单栏，直接在刘海正下方提供一个优雅伸缩的扩展灵动岛，将所有被遮挡的图标无感重现与交互。

---

## ✨ 核心特性

- 🚀 **微秒级极速扫描 (< 20ms)**：通过 macOS SkyLight 窗口系统与后台非阻塞异步辅助功能架构，毫秒级精准扫描状态栏窗口层级（`kCGStatusWindowLevel`），零 UI 卡顿。
- 🪄 **内容驱动动态自适应耳翼 (Dynamic Wings)**：
  - **0 溢出基准态**：紧凑态宽度严格 1:1 贴合硬件刘海物理尺寸（179pt），两端零多余外展；
  - **有溢出态**：左侧动态平滑长出耳翼（Left Wing），黄色计数徽标完整呈现于可用发光屏幕区，彻底告别物理黑胶遮挡；
  - **右侧平齐**：右侧与刘海右缘保持 0 延展平齐，绝不遮挡原生 Wi-Fi、电池等状态栏图标。
- 🎨 **像素级高保真镜像与第 0 帧秒开**：多层级图标解析（Window Capture → Bundle Icon → SF Symbol）。后台与快照原子化同步预热，展开灵动岛瞬间**第 0 帧直接呈现高清真实图标**，去除多余常态线框与内边距挤压，还原原生通透观感。
- ⚡ **原生事件精准穿透路由**：点击灵动岛内的图标时，通过合成底层 `CGEvent` 精确分发至目标窗口与进程（`postToPid`），原生唤起原应用的下拉菜单。
- 🛡️ **双重硬件级事件穿透 (彻底根除透明遮挡)**：采用稳固吸顶视口 + 全局 `MouseMonitor` 动态事件穿透（`ignoresMouseEvents`），紧凑态仅在刘海与耳翼有效区域认领鼠标，下方及两侧透明区域 100% 物理直通底层应用（Chrome 标签栏、书签栏、网页操作毫秒级直通）。
- 🕹️ **多模式触发与物理弹性动效**：
  - **多通道触发方式**：支持「鼠标悬停（默认）」、「仅点击展开」、「悬停或点击」三种交互通道；
  - **防误触时序**：120ms 移入意图识别（快速划过不误触）+ 300ms 离开缓冲（Grace Period）；
  - 遵循 Apple 物理弹簧阻尼动画曲线，宛如原生系统组件。
- 🌌 **全屏沉浸协同与顶边缘碰顶唤醒**：在全屏应用（Xcode、全屏视频、幻灯片、游戏等）下自动隐退视口（`alpha = 0` 且 100% 物理穿透，零遮挡）；当光标碰触屏幕顶边缘（2pt）时随系统菜单栏平滑淡入，移出后平滑隐退，兼顾极简沉浸与随时唤出。
- 🖥️ **多显示器聚焦自适应与零溢出隐藏**：
  - 支持多屏协同，灵动岛智能跟随当前聚焦屏幕（`followFocusedScreen`）、仅主屏模式（`mainScreenOnly`）或外接屏禁用；
  - **零溢出自动隐藏**：原生菜单栏无遮挡时自动隐藏胶囊，跨屏迁移先隐后迁，物理消除闪烁。
- 📱 **极简应用管理面板与现代化 UI**：全面重构应用管理卡片质感，自适应长方形/正方形图标容器，双档清晰状态徽标（`岛内展示 (溢出)` / `原生可见`），去除非必要的黑名单配置。
- 🛠️ **全新现代化设置中心 (Settings)**：
  - **常规**：触发方式、点击自动收起、触觉震动反馈、无溢出自动隐藏、多屏策略、托盘图标、开机自启与退出控制；
  - **悬停与动效**：防抖与宽限时延精细滑块调节（50–300ms / 150–600ms）；
  - **应用管理**：全局活动应用快照同步对齐、模糊搜索、状态栏实时镜像状态与一键重扫；
  - **关于与诊断**：辅助功能与屏幕录制权限实时检测、一键重扫与状态刷新。
- 📥 **系统菜单栏常驻托盘 (`tray.full.fill`)**：提供一键开关灵动岛、重新扫描、偏好设置 (⌘,) 和退出 (⌘Q)。
- 🔒 **100% 纯本地运行与隐私保护**：无任何网络通信、无第三方遥测追踪，代码完全开源。

---

## 🛠️ 系统要求

- **操作系统**：macOS 14.0 (Sonoma) 或更高版本（已完美适配 macOS 15 Sequoia）
- **硬件架构**：Apple Silicon (M1/M2/M3/M4 系列) 及 Intel 芯片机型

---

## 📥 下载与安装

### 方式一：直接下载安装包（推荐）

1. 前往 [GitHub Releases](https://github.com/AeroSheepZ/NotchRail/releases/latest) 下载最新发布的 `.dmg` 或 `.zip` 分发包。
2. 打开下载的 `.dmg` 镜像，将 **NotchRail** 拖入 **Applications (应用程序)** 文件夹。
3. 在「应用程序」中启动 NotchRail。

> **提示**：首次打开如遇 macOS Gatekeeper 提示未签名开发者：
> 请前往「系统设置」→「隐私与安全性」→ 滑动至底部点击「仍要打开」。

### 方式二：从源码编译构建

```bash
# 1. 克隆仓库
git clone https://github.com/AeroSheepZ/NotchRail.git
cd NotchRail

# 2. 编译并打包 App / DMG / ZIP
bash scripts/build_app.sh

# 3. 运行 App
open build/NotchRail.app
```

---

## 🔐 权限说明

为了提供完整的状态栏捕获与点击交互体验，NotchRail 需要以下两项系统权限：

| 权限项 | 对应系统 API | 用途说明 |
| :--- | :--- | :--- |
| **辅助功能 (Accessibility)** | `AXIsProcessTrusted` / `CGEvent` | 用于将用户在灵动岛上的点击事件精准派发给对应目标应用 |
| **屏幕录制 (Screen Recording)** | `CGWindowListCreateImageFromArray` | 用于捕获被刘海物理遮挡的菜单栏图标实时像素（仅本地内存捕获） |

*首次启动时，应用会弹出权限指引面板协助您一键开启。可在「设置」→「关于与诊断」中随时查看与刷新授权状态。*

---

## 🧩 架构设计

NotchRail 采用双 Target 模块化设计：

```
NotchRail/
├── Sources/
│   ├── NotchRailKit/               # 核心框架库
│   │   ├── App/                    # AppDelegate 与 StatusItemManager 托盘管理
│   │   ├── Bridging/               # SkyLight 底层私有 C 接口与窗口桥接
│   │   ├── MenuBar/                # 状态栏扫描 (16ms)、溢出判定、异步 AX 与点击分发
│   │   ├── Island/                 # 灵动岛 SwiftUI 视图、物理弹簧动画与状态机
│   │   ├── Screen/                 # 屏幕几何尺寸、多屏焦点追踪与物理刘海检测
│   │   ├── Window/                 # 悬浮 NSPanel 层级管理 (.screenSaver 视口架构)
│   │   ├── Persistence/            # UserPreferences 模型与 PreferenceStore 持久化
│   │   ├── Permissions/            # TCC 权限检测与引导
│   │   └── Settings/               # 4 栏现代化设置中心视图与开机自启
│   └── NotchRail/                  # 宿主 App 可执行文件入口
├── Tests/                          # 全量状态机、偏好持久化、多屏与溢出算法单元测试
└── scripts/                        # 构建、打包与全套诊断自测脚本
```

---

## 🤝 参与贡献

欢迎提交 Issue 与 Pull Request！

1. Fork 本项目
2. 创建您的特性分支 (`git checkout -b feat/amazing-feature`)
3. 提交您的更改 (`git commit -m 'feat: 添加了某项特性'`)
4. 推送到分支 (`git push origin feat/amazing-feature`)
5. 提交 Pull Request

---

## 📄 开源协议 (License)

本项目采用 **[GNU General Public License v3.0 (GPL-3.0)](LICENSE)** 协议开源。

- ✅ **自由使用与共享**：任何人均可自由运行、学习、修改与分发本软件；
- 🔄 **强互惠与开源传染性 (Strong Copyleft)**：任何包含、修改或链接本项目代码的派生软件，在分发时必须无条件以同等的 GPL-3.0 协议开源其全部源代码；
- 💼 **商业双重许可 (Dual-Licensing)**：若需闭源嵌入、商业集成或专属定制授权，请联系作者获取独立商业授权。
