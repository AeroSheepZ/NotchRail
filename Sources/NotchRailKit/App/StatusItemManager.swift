import Foundation
import AppKit
import Combine

/// 负责管理 macOS 系统状态栏中的常驻小托盘图标与快捷菜单
@MainActor
public final class StatusItemManager: NSObject, NSMenuDelegate, ObservableObject {
    public static let shared = StatusItemManager()
    
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    
    override private init() {
        super.init()
    }
    
    /// 启动状态项监控
    public func start() {
        updateStatusItemVisibility()
        
        NotificationCenter.default.publisher(for: .preferencesChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemVisibility()
            }
            .store(in: &cancellables)
    }
    
    /// 根据用户偏好动态挂载或移除系统状态项
    public func updateStatusItemVisibility() {
        let isEnabled = PreferenceStore.shared.preferences.showMenuBarIcon
        
        if isEnabled {
            if statusItem == nil {
                setupStatusItem()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }
    
    /// 初始化状态项与菜单
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            if let img = NSImage(systemSymbolName: "tray.full.fill", accessibilityDescription: "NotchRail")?
                .withSymbolConfiguration(config) {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "NR"
            }
            button.toolTip = "NotchRail 扩展菜单栏"
        }
        
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
    }
    
    // MARK: - NSMenuDelegate
    
    /// 当前焦点屏对应的灵动岛状态机（无归属屏幕时返回 nil）
    ///
    /// 托盘菜单一律作用于**用户当前所在的屏幕**，绝不隐式绑定某一块屏（旧实现固定操作主屏状态机）。
    private var focusedStateMachine: IslandStateMachine? {
        IslandWindowCoordinator.shared.stateMachine(for: ScreenManager.shared.currentGeometry.displayID)
    }
    
    /// 当前焦点屏是否因「无遮挡图标时自动隐藏紧凑胶囊」而处于完全静默态
    ///
    /// 该档语义为「0 溢出即完全不出现」（ADR 0015 决议 3），托盘菜单这条显式唤出路径同样必须让位，
    /// 否则「任何形式都无法唤出」不成立。
    private var isFocusedScreenSilencedByNoOverflow: Bool {
        let displayID = ScreenManager.shared.currentGeometry.displayID
        let overflowCount = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: displayID)?.overflowCount ?? 0
        return PreferenceStore.shared.preferences.hideWhenNoOverflow && overflowCount == 0
    }
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        let isExpanded = focusedStateMachine?.currentState.isExpanded ?? false
        let toggleTitle = isExpanded ? "收起灵动岛" : "展开灵动岛"
        
        // 1. 灵动岛开关（静默态下禁掉「展开」方向，并说明原因）
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(handleToggleIsland), keyEquivalent: "")
        toggleItem.target = self
        if !isExpanded && isFocusedScreenSilencedByNoOverflow {
            toggleItem.isEnabled = false
            toggleItem.toolTip = "已开启「无遮挡图标时自动隐藏紧凑胶囊」，当前屏无溢出期间灵动岛完全静默"
        }
        menu.addItem(toggleItem)
        
        // 2. 重新扫描
        let rescanItem = NSMenuItem(title: "重新扫描菜单栏", action: #selector(handleRescan), keyEquivalent: "")
        rescanItem.target = self
        menu.addItem(rescanItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. 偏好设置
        let prefsItem = NSMenuItem(title: "偏好设置...", action: #selector(handleOpenPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. 退出 NotchRail
        let quitItem = NSMenuItem(title: "退出 NotchRail", action: #selector(handleQuitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    // MARK: - Menu Actions
    
    @objc private func handleToggleIsland() {
        focusedStateMachine?.toggleExpandCollapse()
    }
    
    @objc private func handleRescan() {
        MenuBarSyncCoordinator.shared.scheduleSync(immediate: true)
    }
    
    @objc private func handleOpenPreferences() {
        SettingsWindowCoordinator.shared.showSettings()
    }
    
    @objc private func handleQuitApp() {
        NSApplication.shared.terminate(nil)
    }
}
