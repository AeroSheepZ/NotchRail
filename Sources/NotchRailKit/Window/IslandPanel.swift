import Foundation
import AppKit

/// 承载灵动岛的专用 NSPanel
/// 具备非激活、全屏 Space 穿透、吸顶居中与无边框全透明特性
public final class IslandPanel: NSPanel {
    
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // 1. 窗口外观与全透明度保证
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovable = false
        self.isMovableByWindowBackground = false
        
        // 2. 窗口层级：高于普通应用与全屏窗口，但低于安全系统警告
        self.level = .screenSaver
        
        // 3. 空间集合行为：跨所有 Spaces、全屏辅助应用、固定不参与循环
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        
        // 4. 交互与焦点策略：绝不抢占前台键盘与窗口焦点
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true
    }
    
    /// 是否允许瞬态成为 Key 窗口以配合 Focus Handoff 移交活动菜单栏 (ADR 0017 / Ticket #59)
    public var allowsTransientKey: Bool = false
    
    public override var canBecomeKey: Bool {
        return allowsTransientKey
    }
    
    public override var canBecomeMain: Bool {
        return allowsTransientKey
    }
}
