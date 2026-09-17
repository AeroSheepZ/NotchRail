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
    
    /// 智能心跳三档能耗调度的时序常量（本模块时序数值唯一来源，文档一律以常量名引用）
    public enum SmartHeartbeat {
        /// 警戒就绪态（armed）的预热超时自愈保护时长
        public static let PREWARM_TIMEOUT_SECONDS: TimeInterval = 3.0
        /// 展开活动态（active）的心跳周期，保障动态网速/时钟刷新
        public static let ACTIVE_INTERVAL_SECONDS: TimeInterval = 2.0
        /// 收起后的宽限冷却时长，随后彻底销毁心跳定时器回归休眠
        public static let COLLAPSE_COOLDOWN_SECONDS: TimeInterval = 1.5
        /// 扫描调度的敏捷防抖延迟
        public static let SCAN_DEBOUNCE_SECONDS: TimeInterval = 0.10
    }
    
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var isPrewarming: Bool = false
    
    /// 各屏独立快照池（按 displayID 隔离，严禁跨屏借用兜底 AGENTS.md §2.1）
    private var snapshotsByDisplay: [CGDirectDisplayID: MenuBarSnapshot] = [:]
    
    /// 心跳按需运行状态
    public enum HeartbeatState: Equatable, Sendable {
        case dormant   // 完全休眠态：心跳定时器彻底置 nil，0.0% CPU 占用
        case armed     // 警戒就绪态：光标靠近顶部热区，单次轻量增量预热完成
        case active    // 展开活动态：灵动岛处于展开或收起缓冲中，运行 SmartHeartbeat.ACTIVE_INTERVAL_SECONDS 周期心跳保障动态网速/时钟刷新
    }
    
    @Published public private(set) var heartbeatState: HeartbeatState = .dormant
    
    private var debounceTimer: Timer?
    private var heartbeatTimer: Timer?
    private var heartbeatCooldownTimer: Timer?
    private var prewarmTimeoutTimer: Timer?
    private var expandedDisplayIDs: Set<CGDirectDisplayID> = []
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
        
        // 2. 默认进入休眠态，心跳定时器彻底置 nil，杜绝后台死循环轮询发热 (Issue #51)
        heartbeatState = .dormant
    }
    
    /// 停止同步
    public func stop() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        heartbeatCooldownTimer?.invalidate()
        heartbeatCooldownTimer = nil
        prewarmTimeoutTimer?.invalidate()
        prewarmTimeoutTimer = nil
        expandedDisplayIDs.removeAll()
        heartbeatState = .dormant
    }
    
    /// 指定屏幕当前是否处于展开态（按屏独立判定，杜绝任一屏展开即让全屏全量重捕获）
    public func isExpanded(displayID: CGDirectDisplayID) -> Bool {
        expandedDisplayIDs.contains(displayID)
    }
    
    /// 设置特定显示器的灵动岛展开状态并聚合多屏心跳调度
    public func setExpansionState(isExpanded: Bool, for displayID: CGDirectDisplayID) {
        if isExpanded {
            expandedDisplayIDs.insert(displayID)
            // 展开第 0 帧：若该屏幕溢出项已在专属快照中，立即触发一次定向直出/就绪解析，杜绝 2.0s 心跳等待真空期
            if let snap = snapshotsByDisplay[displayID], !snap.overflowItems.isEmpty {
                Task {
                    await IconResolver.shared.resolveIcons(
                        for: snap.overflowItems,
                        displayID: displayID,
                        forceRefresh: false
                    )
                }
            }
            activateHeartbeat()
        } else {
            expandedDisplayIDs.remove(displayID)
            if expandedDisplayIDs.isEmpty {
                deactivateHeartbeat()
            }
        }
    }
    
    /// 光标靠近顶部热区时唤醒警戒就绪态，执行单次静默增量预热（带 SmartHeartbeat.PREWARM_TIMEOUT_SECONDS 超时自愈保护）
    public func armPrewarm() {
        guard heartbeatState == .dormant else { return }
        heartbeatState = .armed
        if !isScanning {
            scheduleSync(immediate: false, showProgress: false)
        }
        
        prewarmTimeoutTimer?.invalidate()
        prewarmTimeoutTimer = Timer.scheduledTimer(withTimeInterval: SmartHeartbeat.PREWARM_TIMEOUT_SECONDS, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.heartbeatState == .armed else { return }
                self.heartbeatState = .dormant
                self.prewarmTimeoutTimer = nil
            }
        }
    }
    
    /// 光标远离顶部深区时立即撤销预热警戒态
    public func disarmPrewarm() {
        guard heartbeatState == .armed else { return }
        prewarmTimeoutTimer?.invalidate()
        prewarmTimeoutTimer = nil
        heartbeatState = .dormant
    }
    
    /// 灵动岛展开时激活心跳定时器（周期见 SmartHeartbeat.ACTIVE_INTERVAL_SECONDS，刷新动态数值项）
    public func activateHeartbeat() {
        prewarmTimeoutTimer?.invalidate()
        prewarmTimeoutTimer = nil
        heartbeatCooldownTimer?.invalidate()
        heartbeatCooldownTimer = nil
        
        guard heartbeatState != .active else { return }
        heartbeatState = .active
        
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: SmartHeartbeat.ACTIVE_INTERVAL_SECONDS, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.isScanning else { return }
                self.scheduleSync(immediate: false, showProgress: false)
            }
        }
    }
    
    /// 灵动岛收起后进入 SmartHeartbeat.COLLAPSE_COOLDOWN_SECONDS 宽限冷却，随后彻底销毁心跳定时器回归 dormant 休眠
    public func deactivateHeartbeat() {
        guard heartbeatState == .active else { return }
        
        heartbeatCooldownTimer?.invalidate()
        heartbeatCooldownTimer = Timer.scheduledTimer(withTimeInterval: SmartHeartbeat.COLLAPSE_COOLDOWN_SECONDS, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.heartbeatState == .active else { return }
                // 仅当所有屏幕均收起时才真正休眠
                guard self.expandedDisplayIDs.isEmpty else { return }
                self.heartbeatTimer?.invalidate()
                self.heartbeatTimer = nil
                self.heartbeatCooldownTimer = nil
                self.heartbeatState = .dormant
            }
        }
    }
    
    /// 安排一次扫描任务（支持 SmartHeartbeat.SCAN_DEBOUNCE_SECONDS 敏捷防抖）
    public func scheduleSync(immediate: Bool = false, showProgress: Bool = false) {
        debounceTimer?.invalidate()
        debounceTimer = nil
        
        if immediate {
            performSync(showProgress: showProgress)
        } else {
            debounceTimer = Timer.scheduledTimer(withTimeInterval: SmartHeartbeat.SCAN_DEBOUNCE_SECONDS, repeats: false) { [weak self] _ in
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
        if showProgress {
            isPrewarming = true
        }
        pendingResync = false
        let startTime = Date()
        
        let allGeometries = ScreenManager.shared.allGeometries
        let currentCustomOrder = PreferenceStore.shared.customItemOrder(for: currentGeom.displayID)
        
        Task {
            // 1. 极速扫描当前活动屏幕并计算物理几何溢出（~5ms 瞬时完成）
            let currentItems = await MenuBarWindowScanner.shared.scanMenuBarItems(for: currentGeom)
            let currentSnapshot = OverflowCalculator.resolve(
                items: currentItems,
                geometry: currentGeom,
                customItemOrder: currentCustomOrder
            )
            
            // 2. 优先解析灵动岛内展示的溢出项（受 Cache-Hit Bypass 保护，已有项 0ms 跳过；显式重扫全量刷新）
            let overflowed = currentSnapshot.overflowItems
            if !overflowed.isEmpty {
                await IconResolver.shared.resolveIcons(
                    for: overflowed,
                    displayID: currentSnapshot.displayID,
                    forceRefresh: showProgress
                )
            }
            
            // 3. 立即原子发布当前屏幕快照（此时灵动岛内的溢出项图标已 100% 准备就绪，展开即见真实图标，0 等待！）
            await MainActor.run {
                // 按屏无差别广播：快照自身携带 displayID，由订阅方按本屏过滤，
                // 杜绝「仅焦点屏才刷新」导致非焦点屏 UI 停滞
                self.snapshotsByDisplay[currentSnapshot.displayID] = currentSnapshot
                NotificationCenter.default.post(name: .menuBarSnapshotUpdated, object: currentSnapshot)
                self.isPrewarming = false
            }
            
            // 4. 后台解析剩余原生可见项（供偏好设置面板完整显示）
            // 在初次启动、显式全量扫描(showProgress == true)时对当前活动屏所有项建立真实位图缓存；
            // 日常心跳时对未进入本屏缓存或倍率低于本屏物理倍率的项定向补解。
            let screenScale = currentGeom.scaleFactor
            let unbufferedVisible = currentSnapshot.allItems.filter { item in
                if showProgress { return true }
                guard let scale = IconResolver.shared.cachedScale(for: item) else { return true }
                return scale + 0.01 < screenScale
            }
            if !unbufferedVisible.isEmpty {
                await IconResolver.shared.resolveIcons(
                    for: unbufferedVisible,
                    displayID: currentSnapshot.displayID,
                    forceRefresh: showProgress
                )
            }
            
            // 5. 并行预热其他连接屏幕（仅在初次未扫描、显式重扫、或灵动岛展开时刷新动态数值项）
            var otherSnapshots: [CGDirectDisplayID: MenuBarSnapshot] = [:]
            let hasUnwarmedDisplays = allGeometries.contains { $0.displayID != currentGeom.displayID && self.snapshotsByDisplay[$0.displayID] == nil }
            if showProgress || hasUnwarmedDisplays || !self.expandedDisplayIDs.isEmpty {
                for otherGeom in allGeometries where otherGeom.displayID != currentGeom.displayID {
                    let needsSync = showProgress || self.snapshotsByDisplay[otherGeom.displayID] == nil || self.expandedDisplayIDs.contains(otherGeom.displayID)
                    if needsSync {
                        let otherItems = await MenuBarWindowScanner.shared.scanMenuBarItems(for: otherGeom)
                        let otherCustomOrder = PreferenceStore.shared.customItemOrder(for: otherGeom.displayID)
                        let otherSnap = OverflowCalculator.resolve(
                            items: otherItems,
                            geometry: otherGeom,
                            customItemOrder: otherCustomOrder
                        )
                        if !otherSnap.overflowItems.isEmpty {
                            await IconResolver.shared.resolveIcons(
                                for: otherSnap.overflowItems,
                                displayID: otherGeom.displayID,
                                forceRefresh: showProgress
                            )
                        }
                        otherSnapshots[otherGeom.displayID] = otherSnap
                    }
                }
            }
            
            // 若开启了加载进度动画，保证至少维持 300ms 完整周期避免视觉突变
            let elapsed = Date().timeIntervalSince(startTime)
            if showProgress && elapsed < 0.30 {
                let remainingNanos = UInt64((0.30 - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: remainingNanos)
            }
            
            await MainActor.run {
                // 5. 更新各屏快照池缓存并原子广播各屏专属更新（快照自带 displayID，订阅方按本屏过滤）
                for (dispID, snap) in otherSnapshots {
                    self.snapshotsByDisplay[dispID] = snap
                    NotificationCenter.default.post(name: .menuBarSnapshotUpdated, object: snap)
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
    
    /// 仅对物理几何或前台 App 菜单碰撞变化重新计算溢出项，绝不调用扫描或截图管线 (AGENTS.md 2.4)
    private func recalculateOverflowForGeometryChange(_ geom: NotchGeometry) {
        guard let existingSnapshot = snapshotsByDisplay[geom.displayID] else { return }
        let customOrder = PreferenceStore.shared.customItemOrder(for: geom.displayID)
        let updatedSnapshot = OverflowCalculator.resolve(
            items: existingSnapshot.allItems,
            geometry: geom,
            customItemOrder: customOrder
        )
        self.snapshotsByDisplay[geom.displayID] = updatedSnapshot
        // 按屏无差别广播：仅该屏的订阅方会据 displayID 采纳本次更新
        NotificationCenter.default.post(name: .menuBarSnapshotUpdated, object: updatedSnapshot)
    }
    
    /// 注册系统通知观察者
    private func setupSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        
        // 监听应用启动与退出（排除自身）
        let ownPID = getpid()
        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notif in
                guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ownPID else {
                    return
                }
                Task {
                    await MenuBarAXResolver.shared.handleAppLaunched(app: app)
                }
                self?.scheduleSync()
            }
            .store(in: &cancellables)
        
        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notif in
                guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ownPID else {
                    return
                }
                Task {
                    await MenuBarAXResolver.shared.handleAppTerminated(pid: app.processIdentifier)
                }
                self?.scheduleSync()
            }
            .store(in: &cancellables)
        
        // 监听应用整体隐藏与取消隐藏（⌘H 应用级隐藏，与状态项显隐无关）
        center.publisher(for: NSWorkspace.didHideApplicationNotification)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)
        
        center.publisher(for: NSWorkspace.didUnhideApplicationNotification)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)
        
        // 监听屏幕焦点变更：切屏跟随由 UI 视口 0ms 读取本地独立快照直出，绝不在切屏时派发截图任务
        NotificationCenter.default.publisher(for: .activeDisplayChanged)
            .sink { [weak self] notif in
                guard let self = self else { return }
                if let geom = notif.object as? NotchGeometry,
                   let existingSnapshot = self.snapshotsByDisplay[geom.displayID] {
                    NotificationCenter.default.post(name: .menuBarSnapshotUpdated, object: existingSnapshot)
                }
            }
            .store(in: &cancellables)
        
        // 监听屏幕几何与菜单栏碰撞阈值变更：纯几何重新计算溢出项，0ms 无感响应，绝不重新截图
        NotificationCenter.default.publisher(for: .notchGeometryChanged)
            .sink { [weak self] notif in
                guard let self = self else { return }
                if let geom = notif.object as? NotchGeometry {
                    self.recalculateOverflowForGeometryChange(geom)
                }
            }
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
