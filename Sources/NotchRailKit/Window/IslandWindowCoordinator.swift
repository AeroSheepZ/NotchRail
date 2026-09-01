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
    private var lastActiveDisplayID: CGDirectDisplayID?
    
    private init() {
        // 监听当前屏幕几何变更（含多屏切换），平滑迁移视口锚点
        ScreenManager.shared.$currentGeometry
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)
            
        // 监听偏好变动（多屏模式、空状态隐藏等）
        NotificationCenter.default.publisher(for: .preferencesChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)
            
        // 监听菜单栏快照刷新（检查溢出项数量）
        NotificationCenter.default.publisher(for: .menuBarSnapshotUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)
            
        // 监听状态机展开/收起变化
        IslandStateMachine.shared.$currentState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
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
        self.lastActiveDisplayID = geometry.displayID
        
        // 启动全局鼠标跨屏焦点追踪
        MouseMonitor.shared.startMonitoring()
        
        applyDisplayAndVisibilityRules()
    }
    
    /// 计算覆盖灵动岛全展开区域的稳定透明视口区域
    private func calculateViewportBounds(for geometry: NotchGeometry) -> CGRect {
        let viewportWidth = min(geometry.screenFrame.width * 0.90, 860.0)
        let viewportHeight: CGFloat = 110.0
        let viewportX = geometry.screenFrame.minX + (geometry.screenFrame.width - viewportWidth) / 2.0
        let viewportY = geometry.screenFrame.maxY - viewportHeight
        return CGRect(x: viewportX, y: viewportY, width: viewportWidth, height: viewportHeight)
    }
    
    /// 综合应用多显示器策略与 0 溢出自动隐藏规则
    public func applyDisplayAndVisibilityRules() {
        guard let panel = self.panel else { return }
        
        let prefs = PreferenceStore.shared.preferences
        let currentGeom = ScreenManager.shared.currentGeometry
        let mainGeom = ScreenManager.shared.primaryGeometry
        
        // 1. 判断多显示器策略
        let effectiveGeom: NotchGeometry
        var shouldHideForExternal = false
        
        switch prefs.externalDisplayMode {
        case .followFocusedScreen:
            effectiveGeom = currentGeom
        case .mainScreenOnly:
            effectiveGeom = mainGeom
        case .disabled:
            if currentGeom.displayID != mainGeom.displayID && !currentGeom.hasPhysicalNotch {
                shouldHideForExternal = true
            }
            effectiveGeom = currentGeom
        }
        
        if shouldHideForExternal {
            panel.orderOut(nil)
            return
        }
        
        // 2. 检查目标屏幕多屏预热快照
        let targetSnapshot = MenuBarSyncCoordinator.shared.snapshot(for: effectiveGeom.displayID)
            ?? MenuBarSyncCoordinator.shared.latestSnapshot
        let hasNoOverflow = (targetSnapshot?.overflowCount ?? 0) == 0
        let isScreenSwitching = (lastActiveDisplayID != nil && lastActiveDisplayID != effectiveGeom.displayID)
        self.lastActiveDisplayID = effectiveGeom.displayID
        
        // 3. 仅在切屏至无溢出屏幕且开启自动隐藏时，重置收起展开态（不阻断在同屏的主动展开）
        if isScreenSwitching && prefs.hideWhenNoOverflow && hasNoOverflow {
            if IslandStateMachine.shared.currentState.isExpanded {
                IslandStateMachine.shared.triggerCollapse()
            }
        }
        
        let isExpanded = IslandStateMachine.shared.currentState.isExpanded
        let shouldHideForNoOverflow = prefs.hideWhenNoOverflow && hasNoOverflow && !isExpanded
        
        let targetViewport = calculateViewportBounds(for: effectiveGeom)
        
        if shouldHideForNoOverflow {
            panel.ignoresMouseEvents = true
            // 切屏时先在原屏立即置 0 透明度，再迁移坐标，彻底杜绝闪烁残影
            if isScreenSwitching {
                panel.alphaValue = 0.0
                if panel.frame != targetViewport {
                    panel.setFrame(targetViewport, display: true)
                }
            } else {
                if panel.frame != targetViewport {
                    panel.setFrame(targetViewport, display: true)
                }
                if panel.alphaValue > 0.0 {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.20
                        panel.animator().alphaValue = 0.0
                    }
                } else {
                    panel.alphaValue = 0.0
                }
            }
        } else {
            panel.ignoresMouseEvents = false
            if panel.frame != targetViewport {
                panel.setFrame(targetViewport, display: true)
            }
            panel.orderFrontRegardless()
            if panel.alphaValue < 1.0 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.20
                    panel.animator().alphaValue = 1.0
                }
            } else {
                panel.alphaValue = 1.0
            }
        }
    }
}
