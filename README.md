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

- 🚀 **窗口级零侵入扫描**：通过 macOS SkyLight 窗口系统毫秒级精准扫描状态栏窗口层级（`kCGStatusWindowLevel`），耗时 `< 2ms`，零 UI 卡顿。
- 🎨 **像素级高保真镜像**：多层级图标解析（Window Capture → Bundle Icon → SF Symbol），即使图标物理隐藏在刘海背后，也能通过 `CGWindowID` 实时截取动态变化（如上传进度、CPU占用数字、红点等）。
- ⚡ **原生事件精准穿透路由**：点击灵动岛内的图标时，通过合成底层 `CGEvent` 精确分发至目标窗口与进程（`postToPid`），原生呼出原应用的下拉菜单。
- 🪄 **悬停防误触与物理弹性动效**：
  - 120ms 意图识别：快速划过刘海不误触展开；
  - 300ms 离开缓冲（Grace Period）：鼠标轻微移出不会闪退；
  - 遵循 Apple 物理弹簧阻尼动画曲线，宛如原生系统组件。
- 🖥️ **多显示器自适应**：支持多屏协同，灵动岛跟随鼠标所在屏幕实时渲染；在外接显示器上自动呈现顶部居中原生胶囊锚点。
- 🔒 **100% 纯本地运行与隐私保护**：无任何网络通信、无第三方遥测追踪，代码完全开源。

---

## 🛠️ 系统要求

- **操作系统**：macOS 14.0 (Sonoma) 或更高版本（已适配 macOS 15 Sequoia）
- **硬件架构**：Apple Silicon (M1/M2/M3/M4 系列) 及 Intel 芯片机型

---

## 📥 下载与安装

### 方式一：直接下载安装包（推荐）

1. 前往 [GitHub Releases](https://github.com/AeroSheepZ/NotchRail/releases/latest) 下载最新版本的 `.dmg` 或 `.zip`。
2. 双击打开 `NotchRail-v0.0.1.dmg`，将 **NotchRail** 拖入 **Applications (应用程序)** 文件夹。
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

*首次启动时，应用会弹出权限指引面板协助您一键开启。*

---

## 🧩 架构设计

NotchRail 采用双 Target 模块化设计：

```
NotchRail/
├── Sources/
│   ├── NotchRailKit/               # 核心框架库
│   │   ├── Bridging/               # SkyLight 底层私有 C 接口与窗口桥接
│   │   ├── MenuBar/                # 状态栏窗口扫描、溢出判定与点击分发
│   │   ├── Island/                 # 灵动岛 SwiftUI 视图、弹簧动画与状态机
│   │   ├── Screen/                 # 屏幕几何尺寸与物理刘海边界检测
│   │   ├── Window/                 # 悬浮 NSPanel 层级管理 (.screenSaver)
│   │   ├── Permissions/            # TCC 权限检测与引导
│   │   └── Settings/               # 设置中心视图与偏好持久化
│   └── NotchRail/                  # 宿主 App 可执行文件入口
├── tests/                          # 核心状态机与几何计算单元测试
└── scripts/                        # 构建、打包与自动化脚本
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
