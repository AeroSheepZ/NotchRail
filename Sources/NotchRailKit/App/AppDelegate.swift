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
    
    /// 启动 NotchRail 主核心服务
    private func startMainServices() {
        print("🚀 [NotchRail] 启动灵动岛吸顶常驻窗口与菜单栏自动同步服务...")
        IslandWindowCoordinator.shared.start()
        MenuBarSyncCoordinator.shared.start()
        StatusItemManager.shared.start()
    }
}
