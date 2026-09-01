import Foundation
import SwiftUI
import Combine

/// 灵动岛生命周期状态
public enum IslandDisplayState: String, Equatable, Sendable {
    case compact       // 紧凑常驻胶囊态
    case hoverPending  // 鼠标进入感应区，防抖判定中
    case extended      // 展开扩展菜单栏态
    case collapsing    // 鼠标移出，收起宽限期判定中
    
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
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        self.applyPreferences(PreferenceStore.shared.preferences)
        
        NotificationCenter.default.publisher(for: .preferencesChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                if let prefs = notif.object as? UserPreferences {
                    self?.applyPreferences(prefs)
                }
            }
            .store(in: &cancellables)
    }
    
    private func applyPreferences(_ prefs: UserPreferences) {
        self.hoverExpandDelay = prefs.hoverExpandDelayMs / 1000.0
        self.collapseDelay = prefs.collapseDelayMs / 1000.0
    }
    
    /// 鼠标移入灵动岛热区
    public func handleMouseEnter(overflowCount: Int = 0) {
        collapseTimer?.invalidate()
        collapseTimer = nil
        
        self.activeOverflowCount = overflowCount
        
        let triggerMode = PreferenceStore.shared.preferences.triggerMode
        // 若为「仅点击」模式，悬停不触发展开防抖计时
        guard triggerMode != .click else { return }
        
        switch currentState {
        case .compact:
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
        
        let triggerMode = PreferenceStore.shared.preferences.triggerMode
        
        switch currentState {
        case .hoverPending:
            // 快速划过：未达到防抖时间即离开，直接恢复 compact
            currentState = .compact
            
        case .extended:
            // 若为「仅点击」模式，鼠标离开不自动收起，保持常开直至点击收起或点击图标
            if triggerMode == .click {
                return
            }
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
    
    /// 切换展开/收起状态（用于胶囊点击或外部快捷调用）
    public func toggleExpandCollapse(overflowCount: Int = 1) {
        debounceTimer?.invalidate()
        debounceTimer = nil
        collapseTimer?.invalidate()
        collapseTimer = nil
        
        if currentState.isExpanded {
            triggerCollapse()
        } else {
            triggerExpand(overflowCount: overflowCount)
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
