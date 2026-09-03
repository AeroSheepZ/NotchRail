import Foundation
import AppKit
import ApplicationServices

/// 原生全屏 Space 判定探测器
/// 直接读取前台应用窗口的系统标准 AXFullScreen 属性，无冗余降级
public enum FullScreenDetector {
    
    /// 直接查询指定显示器当前是否处于原生全屏 Space
    public static func isFullScreen(on screen: NSScreen) -> Bool {
        // 1. 系统级菜单栏自动隐藏
        if screen.visibleFrame.maxY >= screen.frame.maxY - 1.0 {
            return true
        }
        
        // 2. 直接查询前台应用主窗口的 AXFullScreen 原生属性
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != "com.apple.finder" else {
            return false
        }
        
        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) != .success {
            AXUIElementCopyAttributeValue(appRef, kAXMainWindowAttribute as CFString, &windowRef)
        }
        guard let win = windowRef, CFGetTypeID(win) == AXUIElementGetTypeID() else {
            return false
        }
        let winElement = unsafeDowncast(win, to: AXUIElement.self)
        
        var isFullScreenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(winElement, "AXFullScreen" as CFString, &isFullScreenRef) == .success,
              let isFullScreen = isFullScreenRef as? Bool, isFullScreen else {
            return false
        }
        
        // 3. 校验该全屏窗口是否位于当前显示器物理区域
        // 关键：AX 窗口坐标与 CGDisplayBounds 均为 CoreGraphics 坐标系（原点在主屏左上角，Y 向下），避免 AppKit 坐标系倒置导致外接屏判定失败
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(winElement, kAXPositionAttribute as CFString, &posRef) == .success,
           AXUIElementCopyAttributeValue(winElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let pos = posRef, CFGetTypeID(pos) == AXValueGetTypeID(),
           let size = sizeRef, CFGetTypeID(size) == AXValueGetTypeID() {
            var point = CGPoint.zero
            var sizeVal = CGSize.zero
            AXValueGetValue(unsafeDowncast(pos, to: AXValue.self), .cgPoint, &point)
            AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &sizeVal)
            let winFrame = CGRect(origin: point, size: sizeVal)
            
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            let cgBounds = CGDisplayBounds(displayID)
            return winFrame.intersects(cgBounds)
        }
        
        // 未能确定全屏窗口相交于本屏幕时，严格返回 false，保障多屏物理隔离
        return false
    }
}
