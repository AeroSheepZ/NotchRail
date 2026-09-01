import Foundation
import AppKit
import SwiftUI

/// 负责独立 Settings 偏好设置窗口的呈现与生命周期
@MainActor
public final class SettingsWindowCoordinator {
    public static let shared = SettingsWindowCoordinator()
    
    private var window: NSWindow?
    
    private init() {}
    
    /// 显示偏好设置窗口
    public func showSettings() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        panel.title = "NotchRail 偏好设置"
        panel.center()
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        
        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// 关闭设置窗口
    public func closeSettings() {
        window?.close()
        window = nil
    }
}
