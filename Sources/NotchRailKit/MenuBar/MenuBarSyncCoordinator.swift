import Foundation
import AppKit
import Combine

extension Notification.Name {
    public static let menuBarSnapshotUpdated = Notification.Name("NotchRail.MenuBarSnapshotUpdated")
}

/// 负责监听系统工作区事件、调度多屏极速扫描并发布全量就绪（数据+图标）快照
@MainActor
public final class MenuBarSyncCoordinator: ObservableObject {
    public static let shared = MenuBarSyncCoordinator()
    
    @Published public private(set) var latestSnapshot: MenuBarSnapshot?
    @Published public private(set) var allDiscoveredItems: [MenuBarItem] = []
    @Published public private(set) var isScanning: Bool = false
    
    private var discoveredItemsMap: [String: MenuBarItem] = [:]
    private var snapshotsByDisplay: [CGDirectDisplayID: MenuBarSnapshot] = [:]
    
    private var debounceTimer: Timer?
    private var heartbeatTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var pendingResync: Bool = false
    
    private init() {
        setupSystemObservers()
    }
    
    /// 获取指定屏幕的最新预热快照
    public func snapshot(for displayID: CGDirectDisplayID) -> MenuBarSnapshot? {
        return snapshotsByDisplay[displayID]
    }
    
    /// 启动工作区监听与自动同步
    public func start() {
        stop()
        
        // 1. 立即执行一次全屏极速扫描与预热
        scheduleSync(immediate: true)
        
        // 2. 启动 5.0s 空闲退避心跳
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleSync(immediate: false)
            }
        }
    }
    
    /// 停止同步
    public func stop() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    /// 安排一次扫描任务（支持 100ms 敏捷防抖）
    public func scheduleSync(immediate: Bool = false) {
        debounceTimer?.invalidate()
        debounceTimer = nil
        
        if immediate {
            performSync()
        } else {
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.performSync()
                }
            }
        }
    }
    
    /// 执行后台扫描、多屏预热与图标同步解析
    private func performSync() {
        guard !isScanning else {
            pendingResync = true
            return
        }
        isScanning = true
        pendingResync = false
        
        let currentGeom = ScreenManager.shared.currentGeometry
        let allGeometries = ScreenManager.shared.allGeometries
        let ignoredIDs = Set(PreferenceStore.shared.preferences.ignoredBundleIDs)
        
        Task {
            // 1. 极速扫描当前活动屏幕
            let currentItems = await MenuBarWindowScanner.shared.scanMenuBarItems(for: currentGeom)
            let currentSnapshot = OverflowCalculator.resolve(items: currentItems, geometry: currentGeom, ignoredBundleIDs: ignoredIDs)
            
            // 2. 立即同步预热当前屏幕的溢出图标（确保发布快照时第 0 帧即可呈现真实图标，消除加载占位）
            if !currentSnapshot.overflowItems.isEmpty {
                await IconResolver.shared.resolveIcons(for: currentSnapshot.overflowItems)
            }
            
            // 3. 并行预热其他连接屏幕
            var otherSnapshots: [CGDirectDisplayID: MenuBarSnapshot] = [:]
            for otherGeom in allGeometries where otherGeom.displayID != currentGeom.displayID {
                let otherItems = await MenuBarWindowScanner.shared.scanMenuBarItems(for: otherGeom)
                let otherSnap = OverflowCalculator.resolve(items: otherItems, geometry: otherGeom, ignoredBundleIDs: ignoredIDs)
                if !otherSnap.overflowItems.isEmpty {
                    await IconResolver.shared.resolveIcons(for: otherSnap.overflowItems)
                }
                otherSnapshots[otherGeom.displayID] = otherSnap
            }
            
            await MainActor.run {
                // 4. 汇总所有活动屏幕发现的实时应用至全局注册池（原子替换，剔除已退出的应用）
                var newDiscoveredMap: [String: MenuBarItem] = [:]
                for item in currentSnapshot.allItems {
                    let key = item.bundleIdentifier ?? item.title ?? "win.\(item.windowID)"
                    newDiscoveredMap[key] = item
                }
                for (_, otherSnap) in otherSnapshots {
                    for item in otherSnap.allItems {
                        let key = item.bundleIdentifier ?? item.title ?? "win.\(item.windowID)"
                        if newDiscoveredMap[key] == nil {
                            newDiscoveredMap[key] = item
                        }
                    }
                }
                self.discoveredItemsMap = newDiscoveredMap
                self.allDiscoveredItems = Array(newDiscoveredMap.values).sorted { ($0.title ?? "") < ($1.title ?? "") }
                
                // 5. 更新多屏快照池缓存
                self.snapshotsByDisplay[currentSnapshot.displayID] = currentSnapshot
                for (dispID, snap) in otherSnapshots {
                    self.snapshotsByDisplay[dispID] = snap
                }
                
                // 6. 发布当前活动屏幕快照
                if currentSnapshot.displayID == ScreenManager.shared.currentGeometry.displayID {
                    self.latestSnapshot = currentSnapshot
                    NotificationCenter.default.post(name: .menuBarSnapshotUpdated, object: currentSnapshot)
                }
                
                self.isScanning = false
                
                if self.pendingResync {
                    self.performSync()
                }
            }
        }
    }
    
    /// 注册系统通知观察者
    private func setupSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        
        // 监听应用启动与退出
        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)
        
        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)
        
        // 监听应用隐藏与取消隐藏
        center.publisher(for: NSWorkspace.didHideApplicationNotification)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)
        
        center.publisher(for: NSWorkspace.didUnhideApplicationNotification)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)
        
        // 监听屏幕几何与焦点屏幕变更
        NotificationCenter.default.publisher(for: .activeDisplayChanged)
            .sink { [weak self] _ in self?.scheduleSync(immediate: true) }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .notchGeometryChanged)
            .sink { [weak self] _ in self?.scheduleSync(immediate: true) }
            .store(in: &cancellables)
        
        // 监听权限授予事件
        NotificationCenter.default.publisher(for: .permissionStatusChanged)
            .sink { [weak self] notif in
                if let granted = notif.object as? Bool, granted {
                    self?.scheduleSync(immediate: true)
                }
            }
            .store(in: &cancellables)
        
        // 监听偏好配置变更事件
        NotificationCenter.default.publisher(for: .preferencesChanged)
            .sink { [weak self] _ in self?.scheduleSync(immediate: true) }
            .store(in: &cancellables)
    }
}
