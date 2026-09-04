# 0001. 三方状态项归属采用 AX 空间几何坐标映射

macOS 14 (Sonoma) 与 macOS 15 (Sequoia) 在多显示器和控制中心架构中，将绝大多数第三方状态栏窗口（Layer 25）的属主进程直接归属于 `ControlCenter.app`（`Item-0`），导致单纯依据 WindowServer 的 `kCGWindowOwnerPID` 无法解析真实应用身份与 Bundle ID。

我们决定通过 `MenuBarAXResolver` 采集前台与后台运行应用的 `AXExtrasMenuBar` 物理屏幕坐标，并与 WindowServer 窗口列表在 X 轴上进行 $\le 6\text{pt}$ 容差匹配；当出现贴邻紧邻双图标歧义时，按 X 轴物理升序执行双向拓扑序号对齐；当 AX 不可用或无匹配时执行 Fail-Fast 阻断，严禁将未识别项伪造归属给 ControlCenter。

此举彻底消除了对系统虚假属主的依赖，保证了应用身份与 Bundle ID 100% 真实还原，同时避免了全量遍历 AX 树带来的 1.5s 级 IPC 超时风险。
