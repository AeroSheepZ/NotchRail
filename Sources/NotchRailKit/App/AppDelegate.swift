import Foundation
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置应用为 Accessory 模式 (LSUIElement / 无 Dock 图标)
        NSApp.setActivationPolicy(.accessory)
        
        // 判断是否为 CLI Spike 诊断模式
        if CommandLine.arguments.contains("--spike") || CommandLine.arguments.contains("-s") {
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
