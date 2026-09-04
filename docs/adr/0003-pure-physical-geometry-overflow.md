# 0003. 基于物理 X 坐标纯几何判定溢出并坚决废弃 isOnScreen

### 背景
macOS 在切换 Space、进入全屏应用或折叠菜单栏时，WindowServer 会将所有 Layer 25 的菜单栏窗口标记为 `isOnScreen == false`。如果溢出判定逻辑依赖 `!item.isOnScreen`，会导致切换 Space 的瞬间整个菜单栏被误判为“全量溢出”，引起灵动岛内图标剧烈闪烁或错误堆叠。

### 决议
在 `OverflowCalculator` 中彻底废弃对 WindowServer `isOnScreen` 状态的任何依赖。判定 `MenuBarItem` 是否溢出的唯一判定依据是物理几何 X 轴坐标：
1. 项的左边界侵入刘海右边缘过渡区（`frame.minX < notchRightEdge + 24pt`）；
2. 项的右边界超出当前物理屏幕右边界（`frame.maxX > screenMaxX + 5pt`）；
3. 项超出屏幕左边界（`frame.maxX < screenMinX`）。

### 理由与权衡
此规则是纯函数物理几何判定，杜绝了系统 Space/全屏状态突变引发的瞬态误判；刘海右侧保留 24pt 安全过渡距离，确保贴近物理刘海右侧边缘圆角弧度时不会产生视觉重叠。
