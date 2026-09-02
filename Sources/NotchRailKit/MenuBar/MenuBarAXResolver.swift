import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

public enum MenuBarAXResolver {

    /// 针对特定 PID（如控制中心）解析其子菜单项语义名称，严格进程隔离
    public static func resolveName(forPID pid: pid_t, frame: CGRect, tolerance: CGFloat = 32) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(pid)
        guard
            let extras = attribute(element, kAXExtrasMenuBarAttribute),
            let children = attribute(extras as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
        else {
            return nil
        }
        
        var best: (name: String, distance: CGFloat)?
        for child in children {
            guard let position = position(of: child) else { continue }
            let distance = abs(position.x - frame.minX)
            if distance < tolerance, best == nil || distance < best!.distance {
                let title = attribute(child, kAXTitleAttribute) as? String
                let description = attribute(child, kAXDescriptionAttribute) as? String
                let name = (title?.isEmpty == false ? title : nil) ?? (description?.isEmpty == false ? description : nil)
                if let validName = name, !validName.isEmpty {
                    best = (validName, distance)
                }
            }
        }
        return best?.name
    }

    // MARK: - Private

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func position(of element: AXUIElement) -> CGPoint? {
        guard
            let value = attribute(element, kAXPositionAttribute),
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }
}
