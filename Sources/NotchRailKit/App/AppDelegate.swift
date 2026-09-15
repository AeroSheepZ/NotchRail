import Foundation
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Spike 诊断模式的标记文件路径（经 `open` 启动时唯一可用的触发通道）
    private static let SPIKE_FLAG_PATH = "/tmp/notchrail-spike.flag"

    /// 是否请求进入 Spike 诊断模式（命令行参数优先，其次标记文件）
    private static var isSpikeRequested: Bool {
        CommandLine.arguments.contains("--spike")
            || CommandLine.arguments.contains("-s")
            || FileManager.default.fileExists(atPath: SPIKE_FLAG_PATH)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置应用为 Accessory 模式 (LSUIElement / 无 Dock 图标)
        NSApp.setActivationPolicy(.accessory)
        
        // 判断是否为 CLI Spike 诊断模式
        //
        // 除命令行参数外，另支持**标记文件**触发：经 LaunchServices（`open`）启动时无法传递
        // 命令行参数，而 `open` 是唯一能让应用以**自身签名身份**运行、从而继承其 TCC 授权
        // （辅助功能 / 屏幕录制）的路径 —— 直接从 shell 执行 bundle 内二进制时，
        // 责任进程是终端，应用自身的授权不会生效，诊断会全部退化为「未授权」。
        if Self.isSpikeRequested {
            Task {
                await SpikeRunner.runDiagnostics()
                exit(0)
            }
            return
        }

        setupMainMenu()
        
        // 检查辅助功能 / 屏幕录制权限：任一未授权（且未跳过过屏幕录制引导）则进入引导
        let isGranted = PermissionManager.shared.checkAccessibility(prompt: false)
        let scGranted = PermissionManager.shared.checkScreenCapture(prompt: false)
        let skipPrompted = PreferenceStore.shared.preferences.skipScreenCapturePrompt
        if !isGranted || (!scGranted && !skipPrompted) {
            PermissionWindowCoordinator.shared.showGuideWindow { [weak self] in
                // 授权完成后清除跳过标记（若之前跳过，现在已授权则不再跳过提示）
                PreferenceStore.shared.update { $0.skipScreenCapturePrompt = false }
                self?.startMainServices()
            }
        } else {
            self.startMainServices()
        }
    }
    
    /// 设置标准 macOS 应用菜单（保证即使隐藏托盘图标，⌘, 与 ⌘Q 依然生效）
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appMenu = NSMenu(title: "NotchRail")
        let prefsItem = NSMenuItem(title: "偏好设置...", action: #selector(handleOpenPreferences), keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(prefsItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出 NotchRail", action: #selector(handleQuitApp), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
    
    @objc private func handleOpenPreferences() {
        SettingsWindowCoordinator.shared.showSettings()
    }
    
    @objc private func handleQuitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    /// 启动 NotchRail 主核心服务
    private func startMainServices() {
        print("🚀 [NotchRail] 启动灵动岛吸顶常驻窗口与菜单栏自动同步服务...")
        IslandWindowCoordinator.shared.start()
        MenuBarSyncCoordinator.shared.start()
        StatusItemManager.shared.start()
    }
}
