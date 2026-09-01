import Foundation
import AppKit
import Combine

extension Notification.Name {
    public static let menuBarSnapshotUpdated = Notification.Name("NotchRail.MenuBarSnapshotUpdated")
}

/// 负责监听系统工作区事件、调度后台 AX 扫描并发布菜单栏最新快照
@MainActor
public final class MenuBarSyncCoordinator: ObservableObject {
    public static let shared = MenuBarSyncCoordinator()
    
    @Published public private(set) var latestSnapshot: MenuBarSnapshot?
    @Published public private(set) var isScanning: Bool = false
    
    private var debounceTimer: Timer?
    private var heartbeatTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// 扫描进行期间收到的新同步请求（如跨屏切换）暂存于此，完成后立即补扫，
    /// 避免 `isScanning` 互斥导致事件被静默丢弃、快照长期停留在上一屏幕。
    private var pendingResync: Bool = false
    
    private init() {
        setupSystemObservers()
    }
    
    /// 启动工作区监听与自动同步
    public func start() {
        stop()
        
        // 1. 立即执行一次初始扫描
        scheduleSync(immediate: true)
        
        // 2. 启动 5.0s 空闲低频退避心跳，仅在系统无事件通知时作为保底对齐，极低 CPU 消耗
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
    
    /// 安排一次扫描任务（支持 200ms 防抖）
    public func scheduleSync(immediate: Bool = false) {
        debounceTimer?.invalidate()
        debounceTimer = nil
        
        if immediate {
            performSync()
        } else {
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.performSync()
                }
            }
        }
    }
    
    /// 执行后台扫描与快照计算
    private func performSync() {
        // 已有扫描在进行：暂存请求，等当前扫描结束后立即补扫，
        // 防止跨屏/应用启停等事件在互斥期间被丢弃。
        guard !isScanning else {
            pendingResync = true
            return
        }
        isScanning = true
        pendingResync = false
        
        let geometry = ScreenManager.shared.currentGeometry
        let ignoredIDs = Set(PreferenceStore.shared.preferences.ignoredBundleIDs)
        
        Task {
            let items = await MenuBarWindowScanner.shared.scanMenuBarItems(for: geometry)
            let snapshot = OverflowCalculator.resolve(items: items, geometry: geometry, ignoredBundleIDs: ignoredIDs)
            
            await MainActor.run {
                // 仅当本次扫描对应的屏幕仍是当前活动屏幕时才更新快照；
                // 跨屏瞬间启动的"旧屏幕扫描"晚到时直接丢弃，防止旧数据覆盖新屏幕。
                if snapshot.displayID == ScreenManager.shared.currentGeometry.displayID {
                    self.latestSnapshot = snapshot
                    NotificationCenter.default.post(name: .menuBarSnapshotUpdated, object: snapshot)
                }
                self.isScanning = false
                
                // 扫描期间有新的同步请求 → 立即补扫（串行执行，保证最终快照属于当前屏幕）
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
