import Foundation
import AppKit
import SwiftUI

/// 负责权限引导窗口的呈现、生命周期与自动关闭调度
@MainActor
public final class PermissionWindowCoordinator {
    public static let shared = PermissionWindowCoordinator()
    
    private var window: NSWindow?
    
    private init() {}
    
    /// 显示权限引导窗口并开始双权限轮询（辅助功能 + 屏幕录制）
    public func showGuideWindow(onGranted: @escaping @MainActor () -> Void) {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let guideView = PermissionGuideView(
            onDismiss: { [weak self] in
                self?.dismissGuideWindow()
            },
            onSkipScreenCapture: { [weak self] in
                // 跳过屏幕录制：记录跳过标记（下次不再弹），辅助功能已授权则直接进入应用
                Task { @MainActor in
                    guard PermissionManager.shared.checkAccessibility(prompt: false) else { return }
                    PreferenceStore.shared.update { $0.skipScreenCapturePrompt = true }
                    self?.dismissGuideWindow()
                    onGranted()
                }
            }
        )
        
        let hostingController = NSHostingController(rootView: guideView)
        
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.title = "NotchRail 权限设置"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.center()
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        
        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // 轮询两个权限，全部授权后自动平滑关闭
        PermissionManager.shared.startPolling(
            onAccessibilityGranted: nil,
            onAllGranted: { [weak self] in
                self?.dismissGuideWindow()
                onGranted()
            }
        )
    }
    
    /// 关闭引导窗口
    public func dismissGuideWindow() {
        guard let window = self.window else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                window.orderOut(nil)
                window.alphaValue = 1.0
                self?.window = nil
            }
        })
    }
}
