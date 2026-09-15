import Foundation
import AppKit
import SwiftUI
import Combine

/// 协调各屏 IslandPanel 的创建、布局锚定、显示隐藏与按需装载
///
/// 架构契约（多屏多轨）：
/// - 每块物理屏幕各自持有**独立的视口与状态机**，一律以 `displayID` 为键注册于本协调器；
/// - 严禁「主槽位 / 副槽位」这类写死屏数的结构；屏幕增减由 `applyDisplayAndVisibilityRules` 幂等对账处理；
/// - `panel(for:)` / `stateMachine(for:)` 未命中一律 Fail-Fast 返回 nil，**绝不跨屏借用兜底**（AGENTS.md §2.1）。
///
/// 视口层：窗口在当前目标屏幕顶部保持稳固常驻（高度为 EXTENDED_HEIGHT），展开/收起绝不改变原生窗口 Frame；
/// 平直屏规范：外接平直显示器在折叠常态下 100% 隐形透明（alpha = 0.0）且鼠标 100% 物理直通。
@MainActor
public final class IslandWindowCoordinator: ObservableObject {
    public static let shared = IslandWindowCoordinator()

    /// 视口空闲卸载宽限时长（秒）：折叠且无溢出持续该时长后卸载非主屏视口
    ///
    /// 本模块时序数值的唯一来源，文档一律以常量名引用。
    public static let PANEL_IDLE_UNLOAD_SECONDS: TimeInterval = 60.0

    /// 各屏独立视口（按 displayID 注册；主屏常驻，其余屏按需装载）
    private var panelsByDisplay: [CGDirectDisplayID: IslandPanel] = [:]

    /// 各屏独立状态机（与视口一一对应，物理隔离）
    ///
    /// 状态机是轻量对象且**常驻于所有策略允许的屏幕**：非主屏的视口可按需卸载，
    /// 但状态机必须始终可取，否则「触碰顶部热区展开」的交互链路会断在 `stateMachine(for:)` 上。
    private var machinesByDisplay: [CGDirectDisplayID: IslandStateMachine] = [:]

    /// 各屏状态机的状态变化订阅（随状态机生命周期增删）
    private var machineSubscriptions: [CGDirectDisplayID: AnyCancellable] = [:]

    /// 非主屏视口的空闲卸载宽限计时器
    private var idleUnloadTimers: [CGDirectDisplayID: Timer] = [:]

    private var cancellables = Set<AnyCancellable>()

    /// 主屏基准屏 displayID（物理刘海屏 / 内建屏；无刘海环境即系统主屏）
    private var primaryDisplayID: CGDirectDisplayID {
        ScreenManager.shared.primaryGeometry.displayID
    }

    /// 当前焦点屏幕几何
    ///
    /// **仅作焦点跟随的只读便捷访问，不代表任何一块面板** —— 面板一律经 `panel(for:)` 按屏取用。
    public var currentPanelGeometry: NotchGeometry {
        ScreenManager.shared.currentGeometry
    }

    private init() {
        // 焦点屏变更、屏幕拓扑变动、偏好变动、菜单栏快照刷新 → 统一驱动幂等对账
        ScreenManager.shared.$currentGeometry
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)

        ScreenManager.shared.$allGeometries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .preferencesChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .menuBarSnapshotUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                // 快照自带 displayID：订阅方按本屏过滤，只对来源屏重算（AGENTS.md §2.1）
                guard let snapshot = note.object as? MenuBarSnapshot else {
                    self?.applyDisplayAndVisibilityRules()
                    return
                }
                self?.applyDisplayRules(for: snapshot.displayID)
            }
            .store(in: &cancellables)
    }

    // MARK: - 按屏查询（Fail-Fast）

    /// 按 displayID 获取对应屏幕的独立状态机
    ///
    /// 未注册但屏幕存在且策略允许时惰性注册，避免调用方早于对账时序而拿到 nil；
    /// 屏幕不存在或策略不允许时返回 nil —— 严禁跨屏借用兜底。
    public func stateMachine(for displayID: CGDirectDisplayID) -> IslandStateMachine? {
        if let existing = machinesByDisplay[displayID] {
            return existing
        }
        guard let geom = ScreenManager.shared.geometry(for: displayID),
              allowsPanel(on: geom, prefs: PreferenceStore.shared.preferences) else {
            return nil
        }
        return registerMachine(for: displayID)
    }

    /// 按 displayID 获取对应屏幕的视口
    ///
    /// 未装载返回 nil —— 严禁把别的屏幕的面板回退返回（否则窗口会被锚定到错误屏幕）。
    public func panel(for displayID: CGDirectDisplayID) -> IslandPanel? {
        panelsByDisplay[displayID]
    }

    // MARK: - 生命周期

    /// 初始化并挂载多屏灵动岛面板，启动多屏追踪
    public func start() {
        applyDisplayAndVisibilityRules()
        MouseMonitor.shared.startMonitoring()
    }

    /// 动态设置指定物理窗口的鼠标事件穿透性
    public func setIgnoresMouseEvents(_ ignores: Bool, for displayID: CGDirectDisplayID? = nil) {
        guard let targetDisplayID = displayID else {
            // 未指定则同步全部已装载视口
            for panel in panelsByDisplay.values where panel.ignoresMouseEvents != ignores {
                panel.ignoresMouseEvents = ignores
            }
            return
        }
        // 指定屏幕时 Fail-Fast：无归属视口即不做任何操作，严禁误改其他屏幕的穿透状态
        if let targetPanel = panelsByDisplay[targetDisplayID], targetPanel.ignoresMouseEvents != ignores {
            targetPanel.ignoresMouseEvents = ignores
        }
    }

    /// 幂等对账：按当前屏幕拓扑与偏好，装载 / 更新 / 卸载各屏视口与状态机
    ///
    /// 本方法**不得产生任何副作用去改写全局焦点屏** —— 焦点跟随由 `MouseMonitor` 在真实用户交互处驱动，
    /// 否则会与 `ScreenManager.$currentGeometry` 的订阅构成重入环。
    public func applyDisplayAndVisibilityRules() {
        let prefs = PreferenceStore.shared.preferences
        let allGeoms = ScreenManager.shared.allGeometries
        guard !allGeoms.isEmpty else { return }

        let allowedIDs = Set(allGeoms.filter { allowsPanel(on: $0, prefs: prefs) }.map(\.displayID))

        reconcileMachines(allowedIDs: allowedIDs)
        reconcilePanels(geometries: allGeoms, allowedIDs: allowedIDs, prefs: prefs)
    }

    /// 仅对**单块屏**重算视口生命周期
    ///
    /// 供「本屏快照更新」这类只影响单屏的事件使用：快照自带 `displayID`，订阅方据此只对来源屏
    /// 重算，避免任一屏变化触发全屏对账（多屏下会被放大成连锁重排）。
    /// 状态机注册表的增删**不在此处**处理 —— 那是屏幕拓扑变化的职责，由 `$allGeometries` 订阅承担。
    private func applyDisplayRules(for displayID: CGDirectDisplayID) {
        let prefs = PreferenceStore.shared.preferences
        guard let geom = ScreenManager.shared.geometry(for: displayID),
              allowsPanel(on: geom, prefs: prefs),
              let machine = machinesByDisplay[displayID] else {
            return
        }
        updatePanelLifecycle(for: geom, stateMachine: machine, prefs: prefs)
    }

    /// 该屏幕是否允许承载灵动岛（主屏恒允许；其余屏由多显示器策略决定）
    private func allowsPanel(on geom: NotchGeometry, prefs: UserPreferences) -> Bool {
        if geom.displayID == primaryDisplayID {
            return true
        }
        return prefs.externalDisplayMode == .followFocusedScreen
    }

    // MARK: - 注册表对账

    /// 对账状态机注册表：屏幕拔出或策略不再允许时卸载，新接入的屏即时建立独立状态机
    private func reconcileMachines(allowedIDs: Set<CGDirectDisplayID>) {
        let staleIDs = machinesByDisplay.keys.filter { !allowedIDs.contains($0) }
        for id in staleIDs {
            machinesByDisplay.removeValue(forKey: id)
            machineSubscriptions.removeValue(forKey: id)?.cancel()
        }
        for id in allowedIDs {
            registerMachine(for: id)
        }
    }

    /// 建立并订阅一块屏幕的独立状态机（幂等）
    @discardableResult
    private func registerMachine(for displayID: CGDirectDisplayID) -> IslandStateMachine {
        if let existing = machinesByDisplay[displayID] {
            return existing
        }
        let machine = IslandStateMachine()
        machinesByDisplay[displayID] = machine
        machineSubscriptions[displayID] = machine.$currentState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyDisplayAndVisibilityRules()
            }
        return machine
    }

    /// 对账视口注册表：卸载不再允许的屏，并驱动保留屏的装载与可见性
    private func reconcilePanels(
        geometries: [NotchGeometry],
        allowedIDs: Set<CGDirectDisplayID>,
        prefs: UserPreferences
    ) {
        let staleIDs = panelsByDisplay.keys.filter { !allowedIDs.contains($0) }
        for id in staleIDs {
            cancelIdleUnload(for: id)
            panelsByDisplay.removeValue(forKey: id)?.orderOut(nil)
        }

        for geom in geometries where allowedIDs.contains(geom.displayID) {
            guard let machine = machinesByDisplay[geom.displayID] else { continue }
            updatePanelLifecycle(for: geom, stateMachine: machine, prefs: prefs)
        }
    }

    // MARK: - 单屏视口驱动

    /// 驱动单块屏幕视口的装载、视口锚定、透明度过渡与按需卸载
    private func updatePanelLifecycle(
        for geom: NotchGeometry,
        stateMachine machine: IslandStateMachine,
        prefs: UserPreferences
    ) {
        let isPrimary = geom.displayID == primaryDisplayID
        let snapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)
        let overflowCount = snapshot?.overflowCount ?? 0
        let isExpanded = machine.currentState.isExpanded

        // 同步该屏展开状态至心跳聚合器
        MenuBarSyncCoordinator.shared.setExpansionState(isExpanded: isExpanded, for: geom.displayID)

        // 按需装载判定：主屏常驻；非主屏仅在「展开中」或「存在溢出项」时保留视口。
        // 不满足时不立即销毁，而是先隐形并启动宽限计时器，避免焦点屏频繁切换导致反复创建销毁。
        guard isPrimary || isExpanded || overflowCount > 0 else {
            scheduleIdleUnload(for: geom.displayID)
            if let panel = panelsByDisplay[geom.displayID] {
                applyHiddenState(to: panel, viewport: calculateViewportBounds(for: geom))
            }
            return
        }
        cancelIdleUnload(for: geom.displayID)

        let panel: IslandPanel
        if let existing = panelsByDisplay[geom.displayID] {
            panel = existing
        } else {
            let created = createPanel(for: geom, stateMachine: machine)
            panelsByDisplay[geom.displayID] = created
            panel = created
        }

        let viewport = calculateViewportBounds(for: geom)
        // 主屏仅在自身为平直屏（Mac mini / 盒盖模式）时折叠隐藏；非主屏折叠态一律 100% 隐形
        let hideWhenCollapsed = isPrimary ? !geom.hasPhysicalNotch : true
        let shouldHideForNoOverflow = prefs.hideWhenNoOverflow && overflowCount == 0 && !isExpanded
        let isFullScreenHidden = machine.currentState.isFullScreenHidden ||
                                 (geom.isFullScreenSpace && !MouseMonitor.shared.isAwakenedInFullScreen)
        let isHidden = isFullScreenHidden || shouldHideForNoOverflow || (hideWhenCollapsed && !isExpanded)

        if isHidden {
            applyHiddenState(to: panel, viewport: viewport)
        } else {
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            updatePanelViewport(panel, targetViewport: viewport, targetAlpha: 1.0, duration: 0.18)
        }
    }

    /// 视口隐形且完全穿透
    private func applyHiddenState(to panel: IslandPanel, viewport: CGRect) {
        panel.ignoresMouseEvents = true
        updatePanelViewport(panel, targetViewport: viewport, targetAlpha: 0.0, duration: 0.20)
    }

    // MARK: - 视口空闲卸载

    /// 为非主屏视口安排空闲卸载：折叠且无溢出持续宽限时长后真正卸载视口（状态机保持常驻）
    private func scheduleIdleUnload(for displayID: CGDirectDisplayID) {
        guard idleUnloadTimers[displayID] == nil else { return }
        idleUnloadTimers[displayID] = Timer.scheduledTimer(
            withTimeInterval: Self.PANEL_IDLE_UNLOAD_SECONDS,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cancelIdleUnload(for: displayID)
                // 卸载前复核：宽限期内若重新需要视口则放弃卸载
                guard displayID != self.primaryDisplayID,
                      self.machinesByDisplay[displayID]?.currentState.isExpanded != true,
                      MenuBarSyncCoordinator.shared.effectiveSnapshot(for: displayID)?.overflowCount ?? 0 == 0
                else { return }
                self.panelsByDisplay.removeValue(forKey: displayID)?.orderOut(nil)
            }
        }
    }

    private func cancelIdleUnload(for displayID: CGDirectDisplayID) {
        idleUnloadTimers.removeValue(forKey: displayID)?.invalidate()
    }

    // MARK: - 视口构建与布局

    /// 创建并装载绑定指定显示器与状态机的 IslandPanel 实例
    private func createPanel(for geometry: NotchGeometry, stateMachine: IslandStateMachine) -> IslandPanel {
        let viewportBounds = calculateViewportBounds(for: geometry)
        let panel = IslandPanel(contentRect: viewportBounds)
        let rootView = IslandRootView(displayID: geometry.displayID, stateMachine: stateMachine)
        let hostingView = IslandHostingView(rootView: rootView, displayID: geometry.displayID)

        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false

        panel.contentView = hostingView
        panel.setFrame(viewportBounds, display: true)
        return panel
    }

    /// 计算覆盖灵动岛全展开区域的稳定透明视口区域（吸顶居中常驻，展开/收起永不改变 Frame）
    public func calculateViewportBounds(for geometry: NotchGeometry) -> CGRect {
        let viewportWidth = min(geometry.screenFrame.width * 0.85, 800.0)
        let viewportHeight: CGFloat = IslandTheme.Dimension.EXTENDED_HEIGHT
        let viewportX = geometry.screenFrame.minX + (geometry.screenFrame.width - viewportWidth) / 2.0
        let viewportY = geometry.screenFrame.maxY - viewportHeight
        return CGRect(x: viewportX, y: viewportY, width: viewportWidth, height: viewportHeight)
    }

    /// 统一驱动视口坐标迁移与透明度平滑过渡
    private func updatePanelViewport(
        _ panel: IslandPanel,
        targetViewport: CGRect,
        targetAlpha: CGFloat,
        duration: TimeInterval
    ) {
        if panel.frame != targetViewport {
            panel.setFrame(targetViewport, display: true)
        }
        if panel.alphaValue != targetAlpha {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                panel.animator().alphaValue = targetAlpha
            }
        }
    }

    // MARK: - 外部点击

    /// 检查点击位置是否落在当前灵动岛展开交互区域外部；若在外部且展开则收起对应屏幕面板
    public func handleOutsideClickIfNeeded(at location: CGPoint) {
        let allGeoms = ScreenManager.shared.allGeometries
        guard let geom = allGeoms.first(where: { $0.screenFrame.insetBy(dx: -2.0, dy: -2.0).contains(location) }) else {
            return
        }
        guard let machine = stateMachine(for: geom.displayID) else { return }
        guard machine.currentState.isExpanded else { return }

        let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: geom.displayID)
        let overflowCount = targetSnapshot?.overflowCount ?? machine.activeOverflowCount
        let screenRect = geom.interactiveScreenRect(isExpanded: true, overflowCount: overflowCount)
        let paddedRect = screenRect.insetBy(dx: -4, dy: -4)
        if !NSMouseInRect(location, paddedRect, false) {
            machine.triggerCollapse()
        }
    }
}
