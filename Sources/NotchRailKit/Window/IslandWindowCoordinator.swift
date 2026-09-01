import Foundation
import AppKit
import SwiftUI
import Combine

/// 协调 IslandPanel 窗口的创建、布局锚定与显示隐藏及跨屏动态迁移
/// 采用 boring.notch 黄金视口架构：窗口常驻稳定透明视口，流体形变全部由 SwiftUI GPU 渲染，彻底消除 OS 窗口跳动
@MainActor
public final class IslandWindowCoordinator: ObservableObject {
    public static let shared = IslandWindowCoordinator()
    
    private var panel: IslandPanel?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // 监听当前屏幕几何变更（含多屏切换），平滑迁移视口锚点
        ScreenManager.shared.$currentGeometry
            .sink { [weak self] newGeometry in
                self?.handleGeometryChanged(newGeometry)
            }
            .store(in: &cancellables)
    }
    
    /// 初始化并挂载灵动岛窗口，启动多屏追踪
    public func start() {
        if panel != nil { return }
        
        let geometry = ScreenManager.shared.currentGeometry
        let viewportBounds = calculateViewportBounds(for: geometry)
        
        let panel = IslandPanel(contentRect: viewportBounds)
        let rootView = IslandRootView()
        let hostingView = NSHostingView(rootView: rootView)
        
        // 强制图层背景完全透明，防止 macOS 渲染默认灰色直角背景
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        
        panel.contentView = hostingView
        panel.setFrame(viewportBounds, display: true)
        
        self.panel = panel
        panel.orderFrontRegardless()
        
        // 启动全局鼠标跨屏焦点追踪
        MouseMonitor.shared.startMonitoring()
    }
    
    /// 计算覆盖灵动岛全展开区域的稳定透明视口区域
    private func calculateViewportBounds(for geometry: NotchGeometry) -> CGRect {
        let viewportWidth = min(geometry.screenFrame.width * 0.90, 860.0)
        let viewportHeight: CGFloat = 110.0
        let viewportX = geometry.screenFrame.minX + (geometry.screenFrame.width - viewportWidth) / 2.0
        let viewportY = geometry.screenFrame.maxY - viewportHeight
        return CGRect(x: viewportX, y: viewportY, width: viewportWidth, height: viewportHeight)
    }
    
    /// 调整灵动岛窗口物理区域（仅在屏幕物理参数改变或跨屏时调用）
    public func setWindowFrame(_ frame: CGRect, animate: Bool = false) {
        guard let panel = self.panel else { return }
        panel.setFrame(frame, display: true)
    }
    
    /// 响应屏幕几何变更或多屏焦点迁移
    private func handleGeometryChanged(_ geometry: NotchGeometry) {
        guard let panel = self.panel else { return }
        let targetViewport = calculateViewportBounds(for: geometry)
        
        panel.setFrame(targetViewport, display: true)
        panel.orderFrontRegardless()
        panel.contentView?.needsDisplay = true
    }
    
    /// 隐藏窗口
    public func hide() {
        panel?.orderOut(nil)
    }
    
    /// 重新显示窗口
    public func show() {
        panel?.orderFrontRegardless()
    }
}
