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
    @Published public private(set) var isPrewarming: Bool = false
    
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
    
    /// 获取指定屏幕的有效快照（单屏物理隔离，严禁跨屏借用兜底 AGENTS.md 2.1）
    public func effectiveSnapshot(for displayID: CGDirectDisplayID) -> MenuBarSnapshot? {
        return snapshotsByDisplay[displayID]
    }
    
    /// 启动工作区监听与自动同步
    public func start() {
        stop()
        
        // 1. 立即执行一次全屏极速扫描与预热（展示完整加载动画）
        scheduleSync(immediate: true, showProgress: true)
        
        // 2. 启动 2.5s 静默心跳（仅在非扫描空闲期触发动态数值轻量刷新，绝不推挤重扫队列）
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.isScanning else { return }
                self.scheduleSync(immediate: false, showProgress: false)
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
    public func scheduleSync(immediate: Bool = false, showProgress: Bool = false) {
        debounceTimer?.invalidate()
        debounceTimer = nil
        
        if immediate {
            performSync(showProgress: showProgress)
        } else {
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.performSync(showProgress: showProgress)
                }
            }
        }
    }
    
    /// 执行后台扫描、多屏预热与图标同步解析
    private func performSync(showProgress: Bool = false) {
        let currentGeom = ScreenManager.shared.currentGeometry
        guard !isScanning else {
            if showProgress {
                pendingResync = true
            }
            return
        }
        isScanning = true
        if showProgress || snapshotsByDisplay[currentGeom.displayID] == nil {
            isPrewarming = true
        }
        pendingResync = false
        let startTime = Date()
        
        let allGeometries = ScreenManager.shared.allGeometries
        let ignoredIDs = Set(PreferenceStore.shared.preferences.ignoredBundleIDs)
        
        Task {
            // 1. 极速扫描当前活动屏幕
            let currentItems = await MenuBarWindowScanner.shared.scanMenuBarItems(for: currentGeom)
            let currentSnapshot = OverflowCalculator.resolve(items: currentItems, geometry: currentGeom, ignoredBundleIDs: ignoredIDs)
            
            // 2. 立即同步预热当前屏幕全部图标（确保发布快照时第 0 帧即可呈现真实图标，消除加载占位）
            if !currentSnapshot.allItems.isEmpty {
                await IconResolver.shared.resolveIcons(for: currentSnapshot.allItems)
            }
            
            // 3. 立即原子发布当前活动屏幕快照，杜绝快照与图标状态发布时间差
            await MainActor.run {
                self.snapshotsByDisplay[currentSnapshot.displayID] = currentSnapshot
                if currentSnapshot.displayID == ScreenManager.shared.currentGeometry.displayID {
                    self.latestSnapshot = currentSnapshot
                    NotificationCenter.default.post(name: .menuBarSnapshotUpdated, object: currentSnapshot)
                }
            }
            
            // 4. 并行预热其他连接屏幕（仅在初次未扫描或显式重扫时执行，日常切屏与心跳绝不重复截取副屏）
            var otherSnapshots: [CGDirectDisplayID: MenuBarSnapshot] = [:]
            let hasUnwarmedDisplays = allGeometries.contains { $0.displayID != currentGeom.displayID && self.snapshotsByDisplay[$0.displayID] == nil }
            if showProgress || hasUnwarmedDisplays {
                for otherGeom in allGeometries where otherGeom.displayID != currentGeom.displayID {
                    if showProgress || self.snapshotsByDisplay[otherGeom.displayID] == nil {
                        let otherItems = await MenuBarWindowScanner.shared.scanMenuBarItems(for: otherGeom)
                        let otherSnap = OverflowCalculator.resolve(items: otherItems, geometry: otherGeom, ignoredBundleIDs: ignoredIDs)
                        if !otherSnap.allItems.isEmpty {
                            await IconResolver.shared.resolveIcons(for: otherSnap.allItems)
                        }
                        otherSnapshots[otherGeom.displayID] = otherSnap
                    }
                }
            }
            
            // 若开启了加载进度动画，保证至少维持 500ms 完整旋转周期，避免右耳翼闪退抽搐
            let elapsed = Date().timeIntervalSince(startTime)
            if showProgress && elapsed < 0.50 {
                let remainingNanos = UInt64((0.50 - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: remainingNanos)
            }
            
            await MainActor.run {
                // 5. 汇总所有活动屏幕发现的实时应用至全局注册池（原子替换，剔除已退出的应用）
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
                
                // 6. 更新副屏快照池缓存
                for (dispID, snap) in otherSnapshots {
                    self.snapshotsByDisplay[dispID] = snap
                }
                
                self.isPrewarming = false
                self.isScanning = false
                
                if self.pendingResync {
                    self.pendingResync = false
                    self.performSync(showProgress: false)
                }
            }
        }
    }
    
    /// 注册系统通知观察者
    private func setupSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        
        // 监听应用启动与退出（排除自身）
        let ownPID = getpid()
        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notif in
                if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier == ownPID {
                    return
                }
                self?.scheduleSync()
            }
            .store(in: &cancellables)
        
        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notif in
                if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier == ownPID {
                    return
                }
                self?.scheduleSync()
            }
            .store(in: &cancellables)
        
        // 监听应用隐藏与取消隐藏
        center.publisher(for: NSWorkspace.didHideApplicationNotification)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)
        
        center.publisher(for: NSWorkspace.didUnhideApplicationNotification)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)
        
        // 监听屏幕几何与焦点屏幕变更：切屏跟随由 UI 视口 0ms 直出，若目标屏幕无快照才执行静默补充预热
        NotificationCenter.default.publisher(for: .activeDisplayChanged)
            .sink { [weak self] notif in
                guard let self = self else { return }
                if let geom = notif.object as? NotchGeometry,
                   self.snapshotsByDisplay[geom.displayID] == nil {
                    self.scheduleSync(immediate: true, showProgress: false)
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .notchGeometryChanged)
            .sink { [weak self] _ in self?.scheduleSync(immediate: true, showProgress: false) }
            .store(in: &cancellables)
        
        // 监听权限授予事件
        NotificationCenter.default.publisher(for: .permissionStatusChanged)
            .sink { [weak self] notif in
                if let granted = notif.object as? Bool, granted {
                    self?.scheduleSync(immediate: true, showProgress: false)
                }
            }
            .store(in: &cancellables)
        
        // 监听偏好配置变更事件
        NotificationCenter.default.publisher(for: .preferencesChanged)
            .sink { [weak self] _ in self?.scheduleSync(immediate: true, showProgress: false) }
            .store(in: &cancellables)
    }
}
