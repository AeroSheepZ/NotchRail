import Foundation
import SwiftUI
import Combine

/// 灵动岛生命周期状态
public enum IslandDisplayState: String, Equatable, Sendable {
    case compact       // 紧凑常驻胶囊态
    case hoverPending  // 鼠标进入感应区，防抖判定中 (120ms)
    case extended      // 展开扩展菜单栏态
    case collapsing    // 鼠标移出，收起宽限期判定中 (300ms)
    
    /// 当前是否处于展开或正在收起的可见状态
    public var isExpanded: Bool {
        return self == .extended || self == .collapsing
    }
}

/// 灵动岛展开/收起状态机控制器
@MainActor
public final class IslandStateMachine: ObservableObject {
    public static let shared = IslandStateMachine()
    
    @Published public private(set) var currentState: IslandDisplayState = .compact
    @Published public private(set) var activeOverflowCount: Int = 1
    
    public var hoverExpandDelay: TimeInterval = IslandTheme.Timing.HOVER_EXPAND_DELAY
    public var collapseDelay: TimeInterval = IslandTheme.Timing.COLLAPSE_DELAY
    
    private var debounceTimer: Timer?
    private var collapseTimer: Timer?
    
    public init() {}
    
    /// 鼠标移入灵动岛热区
    public func handleMouseEnter(overflowCount: Int = 0) {
        collapseTimer?.invalidate()
        collapseTimer = nil
        
        self.activeOverflowCount = overflowCount
        
        switch currentState {
        case .compact:
            // 进入 hoverPending 状态并启动 60ms 极速防抖计时器
            currentState = .hoverPending
            debounceTimer = Timer.scheduledTimer(withTimeInterval: hoverExpandDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.triggerExpand(overflowCount: overflowCount)
                }
            }
            
        case .collapsing:
            // 宽限期内鼠标重新移入，取消收起并恢复展开态
            currentState = .extended
            
        case .hoverPending, .extended:
            break
        }
    }
    
    /// 鼠标移出灵动岛热区
    public func handleMouseLeave() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        
        switch currentState {
        case .hoverPending:
            // 快速划过：未达到防抖时间即离开，直接恢复 compact
            currentState = .compact
            
        case .extended:
            // 启动收起宽限期计时器
            currentState = .collapsing
            collapseTimer = Timer.scheduledTimer(withTimeInterval: collapseDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.triggerCollapse()
                }
            }
            
        case .compact, .collapsing:
            break
        }
    }
    
    /// 显式触发展开
    public func triggerExpand(overflowCount: Int = 1) {
        debounceTimer?.invalidate()
        debounceTimer = nil
        self.activeOverflowCount = overflowCount
        guard currentState != .extended else { return }
        currentState = .extended
    }
    
    /// 显式触发收起
    public func triggerCollapse() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        guard currentState != .compact else { return }
        currentState = .compact
    }
}
