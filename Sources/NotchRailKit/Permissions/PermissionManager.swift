import Foundation
import AppKit
import ApplicationServices
import ScreenCaptureKit
import Combine

extension Notification.Name {
    public static let permissionStatusChanged = Notification.Name("NotchRail.PermissionStatusChanged")
    public static let screenCaptureStatusChanged = Notification.Name("NotchRail.ScreenCaptureStatusChanged")
}

/// 管理 Accessibility 辅助功能 / 屏幕录制权限状态、动态轮询与引导
@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()
    
    @Published public private(set) var isAccessibilityGranted: Bool = false
    @Published public private(set) var isScreenCaptureGranted: Bool = false
    
    private var pollTimer: Timer?
    /// 标记辅助功能授权是否已通知过（避免轮询重复回调）
    private var accessibilityPollNotified = false
    
    private init() {
        self.isAccessibilityGranted = AXIsProcessTrusted()
        self.isScreenCaptureGranted = CGPreflightScreenCaptureAccess()
    }
    
    /// 检查辅助功能权限
    @discardableResult
    public func checkAccessibility(prompt: Bool = false) -> Bool {
        let granted: Bool
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            granted = AXIsProcessTrustedWithOptions(options)
        } else {
            granted = AXIsProcessTrusted()
        }
        
        if granted != self.isAccessibilityGranted {
            self.isAccessibilityGranted = granted
            NotificationCenter.default.post(name: .permissionStatusChanged, object: granted)
        }
        
        return granted
    }
    
    /// 一键打开系统辅助功能设置面板
    public func openSystemSettings() {
        // macOS Ventura / Sonoma / Sequoia 辅助功能设置 DeepLink
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 检查屏幕录制权限（图标预览 / 按窗口截取所需）
    ///
    /// - Parameter prompt: 为 true 时触发系统授权（把本应用加入"屏幕录制"列表）
    @discardableResult
    public func checkScreenCapture(prompt: Bool = false) -> Bool {
        if prompt {
            requestScreenCapturePermission()
        }
        let granted = CGPreflightScreenCaptureAccess()
        if granted != self.isScreenCaptureGranted {
            self.isScreenCaptureGranted = granted
            NotificationCenter.default.post(name: .screenCaptureStatusChanged, object: granted)
        }
        return granted
    }

    /// 触发屏幕录制授权请求（多重保险，确保应用 100% 进入系统 TCC 屏幕录制列表）
    public func requestScreenCapturePermission() {
        // 1. CGRequestScreenCaptureAccess：标准 API 探测
        CGRequestScreenCaptureAccess()
        
        // 2. ScreenCaptureKit：macOS 14+ 推荐入口，直接请求可共享内容触发系统 TCC 注册
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { _, _ in }
        
        // 3. 实际执行 1x1 像素最小捕获，强制 WindowServer 与 TCC 完成进程注册
        triggerCaptureProbe()
    }

    /// 实际执行一次极小窗口捕获，强制触发系统屏幕录制 TCC 检测（把应用加入列表）
    private func triggerCaptureProbe() {
        if let windowID = Bridging.menuBarWindowIDs().first {
            _ = Bridging.captureWindow(windowID)
        }
        // 无菜单栏窗口时无需额外兜底：上方 requestScreenCapturePermission 里的
        // SCShareableContent 调用已足够触发 TCC 注册（kCGNullWindowID 传给
        // CGWindowList 截图无意义，旧代码的 CGWindowListCreateImage 兜底本就无效）
    }

    /// 一键打开系统屏幕录制设置面板
    ///
    /// 先触发屏幕录制授权检测（确保本应用被注册进系统"屏幕录制"列表），
    /// 微延时 150ms 确保系统 tccd 完成列表写入后再打开系统设置面板。
    public func openScreenCaptureSettings() {
        requestScreenCapturePermission()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    /// 开始定时轮询权限变更（在引导窗口展示期间激活）
    ///
    /// - Parameters:
    ///   - interval: 轮询间隔
    ///   - onAccessibilityGranted: 辅助功能首次授权时回调（用于 UI 状态刷新）
    ///   - onAllGranted: 辅助功能 + 屏幕录制**都已授权**时回调（触发后自动停止轮询）
    public func startPolling(
        interval: TimeInterval = 0.8,
        onAccessibilityGranted: (() -> Void)? = nil,
        onAllGranted: (() -> Void)? = nil
    ) {
        stopPolling()
        
        // 立即先检查一次
        accessibilityPollNotified = checkAccessibility(prompt: false)
        if accessibilityPollNotified {
            onAccessibilityGranted?()
        }
        if accessibilityPollNotified && checkScreenCapture(prompt: false) {
            onAllGranted?()
            return
        }
        
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let axGranted = self.checkAccessibility(prompt: false)
                let scGranted = self.checkScreenCapture(prompt: false)
                
                if axGranted && !self.accessibilityPollNotified {
                    self.accessibilityPollNotified = true
                    onAccessibilityGranted?()
                }
                if axGranted && scGranted {
                    self.stopPolling()
                    onAllGranted?()
                }
            }
        }
    }
    
    /// 停止轮询
    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        accessibilityPollNotified = false
    }
}
