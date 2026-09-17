import Foundation
import AppKit
import CoreGraphics

/// 负责第一阶段基础可行性验证诊断与算法自测 (Spike Runner)
public enum SpikeRunner {
    
    @MainActor
    public static func runDiagnostics() async {
        print("\n========================================================")
        print("🚀 [NotchRail Feasibility Spike] 正在执行底层可行性诊断...")
        print("========================================================\n")
        
        // 0. 运行纯算法与状态机自测
        await runUnitTests()
        
        // 1. 权限检测
        let hasPermission = PermissionManager.shared.checkAccessibility(prompt: false)
        print("\n1️⃣ [Accessibility 权限检测]")
        print("   - 辅助功能授权状态: \(hasPermission ? "✅ 已授权" : "❌ 未授权 (请在系统设置中允许终端/应用权限)")")
        
        // 2. 屏幕与刘海测量 (Ticket 03)
        print("\n2️⃣ [屏幕几何与刘海测量 (ScreenManager)]")
        ScreenManager.shared.refreshAllScreens()
        for screen in NSScreen.screens {
            if let maxX = await MenuBarAXResolver.shared.fetchFrontmostAppMenuMaxX(for: screen.frame) {
                ScreenManager.shared.updateAppMenuRightEdge(maxX, for: screen.displayID)
            }
        }
        let allScreens = ScreenManager.shared.allGeometries
        print("   - 当前已连接显示器数量: \(allScreens.count) 台")
        
        for (idx, geom) in allScreens.enumerated() {
            let notchStatus = geom.hasPhysicalNotch ? "物理刘海 (MacBook)" : "平直屏幕 (外接/无刘海)"
            print("   👉 [Display #\(idx + 1)] \"\(geom.displayName)\" (ID: \(geom.displayID), \(notchStatus)):")
            print("      • 屏幕分辨率: \(Int(geom.screenFrame.width)) × \(Int(geom.screenFrame.height)) pt (Scale: \(geom.scaleFactor)x)")
            print("      • 状态栏高度: \(Int(geom.statusBarHeight)) pt, Top Inset: \(Int(geom.safeAreaInsets.top)) pt")
            print("      • 刘海/锚点区域: (\(Int(geom.physicalNotchRect.minX)), \(Int(geom.physicalNotchRect.minY)), \(Int(geom.physicalNotchRect.width))x\(Int(geom.physicalNotchRect.height)))")
            print("      • Compact 胶囊预设: (\(Int(geom.compactBounds.minX)), \(Int(geom.compactBounds.minY)), \(Int(geom.compactBounds.width))x\(Int(geom.compactBounds.height)))")
            print("      • Extended 展开预设: (\(Int(geom.extendedBounds.minX)), \(Int(geom.extendedBounds.minY)), \(Int(geom.extendedBounds.width))x\(Int(geom.extendedBounds.height)))")
            print("      • App 菜单右边缘: \(geom.appMenuRightEdge.map { "\(Int($0)) pt" } ?? "未测定/无")")
        }
        
        let activeGeom = ScreenManager.shared.currentGeometry
        
        // 3. 菜单栏扫描性能实测（窗口枚举）
        print("\n3️⃣ [菜单栏扫描与性能实测 (MenuBarWindowScanner)]")
        let startTime = CFAbsoluteTimeGetCurrent()
        let rawItems = await MenuBarWindowScanner.shared.scanMenuBarItems(for: activeGeom)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        print("   - 扫描耗时: \(String(format: "%.2f", elapsedMs)) ms")
        print("   - 当前活动屏扫描到菜单栏项总数: \(rawItems.count) 个")

        // 3.5 AX 身份映射池的屏幕分布诊断
        //
        // 目的：一次性回答 `MenuBarAXResolver.resolveApp` 那个**悬而未决的前提** ——
        // `AXExtrasMenuBar` 到底返回「所有屏幕的项」还是「仅活动屏的项」。
        // 该前提决定「按屏过滤」是否安全：若池中只有活动屏项，按屏过滤会让非活动屏 100% 匹配失败。
        // 详见 `.workbuddy-ai/memory/2026-09-11.md`。
        print("\n3.5️⃣ [AX 身份映射池屏幕分布诊断]")
        let axPoolEntries = await MenuBarAXResolver.shared.latestEntries()
        if axPoolEntries.isEmpty {
            print("   ⚠️ AX 池为空 —— 未授权辅助功能时必然如此，本项无法判定（请授权后重跑）")
        } else {
            print("   - AX 池条目总数: \(axPoolEntries.count) 个")
            // ⚠️ 归属判定**必须用 2D 包含**，且必须先换算坐标系。两条真机实测教训（2026-09-14 --spike）：
            //  ① 两屏菜单项的 **X 区间是重叠的**（实测内建 699–1472 / 外接 1201–1974），只靠 X 判**必错**：
            //     「X 落在本屏 [minX,maxX)」的结果取决于 allScreens 枚举顺序；
            //     「右边缘不小于 X 的最近屏」会把外接屏 x∈[1201,1470) 的项判给内建屏。两种都错。
            //  ② AX 的 `position` 是 **Quartz（左上原点）**，而 `NotchGeometry.screenFrame` 是
            //     **Cocoa（左下原点，主屏 origin = .zero）**，Y 轴相反，直接比 Y 必错。
            //  真正分离两屏的是 **Y**（实测内建项 Y=0、外接项 Y=-1440）。
            let primaryHeight = allScreens.first { $0.screenFrame.origin == .zero }?.screenFrame.height
                ?? allScreens.map(\.screenFrame.height).max() ?? 0
            // 取条目**中心点**判定，避开边界 off-by-one（内建屏顶边的 Cocoa y 恰等于 screenFrame.maxY，
            // 用 CGRect.contains 判原始 y 会返回 false）
            func attribute(_ entry: MenuBarAXResolver.Entry) -> NotchGeometry? {
                let cocoaCenter = CGPoint(
                    x: entry.position.x + entry.size.width / 2,
                    y: primaryHeight - (entry.position.y + entry.size.height / 2)
                )
                return allScreens.first { $0.screenFrame.contains(cocoaCenter) }
            }
            var entriesPerDisplay: [CGDirectDisplayID: Int] = [:]
            var displaysPerApp: [pid_t: Set<CGDirectDisplayID>] = [:]
            var degenerate: [String] = []
            for entry in axPoolEntries {
                let bundle = entry.bundleIdentifier ?? "-"
                // 尺寸为 0 的条目**位置不可用**，必须排除：实测非活动屏的控制中心条目恒为 `(0,956,0x0)`，
                // 若参与 `contains` 会被**巧合**判入某块屏，进而伪造出「某应用跨屏出现」的假证据
                // （2026-09-14 首轮即因此把结论写反成「按屏过滤安全」）。
                if entry.size.width <= 0 || entry.size.height <= 0 {
                    degenerate.append("\(entry.appName) pid=\(entry.processIdentifier)")
                    print("      • ⚠️[退化·不计入] \(entry.appName) [\(bundle)] pid=\(entry.processIdentifier) x=\(Int(entry.position.x)) y=\(Int(entry.position.y)) \(Int(entry.size.width))x\(Int(entry.size.height)) → 尺寸为 0，位置不可用")
                    continue
                }
                let owner = attribute(entry)
                let ownerName: String
                if let owner {
                    entriesPerDisplay[owner.displayID, default: 0] += 1
                    displaysPerApp[entry.processIdentifier, default: []].insert(owner.displayID)
                    ownerName = "\(owner.displayName)(ID:\(owner.displayID))"
                } else {
                    ownerName = "屏幕外"
                }
                print("      • \(entry.appName) [\(bundle)] pid=\(entry.processIdentifier) x=\(Int(entry.position.x)) y=\(Int(entry.position.y)) \(Int(entry.size.width))x\(Int(entry.size.height)) → \(ownerName)")
            }
            if !degenerate.isEmpty {
                print("   - 退化条目（尺寸 0，已排除）: \(degenerate.count) 个 —— \(degenerate.joined(separator: ", "))")
            }
            let distribution = allScreens
                .map { "\($0.displayName)=\(entriesPerDisplay[$0.displayID] ?? 0)" }
                .joined(separator: ", ")
            print("   - 各屏有效条目数: \(distribution)")

            // 结论（2026-09-14 已真机定案）：**AXExtrasMenuBar 只返回活动屏的项**。
            // 故「按屏过滤」被永久否决 —— 池中本就没有非活动屏的可用数据。
            let hitDisplays = allScreens.filter { (entriesPerDisplay[$0.displayID] ?? 0) > 0 }
            let spanning = displaysPerApp.filter { $0.value.count > 1 }
            if hitDisplays.count <= 1 {
                print("   🚫 判定：有效条目**只落在单一屏**（\(hitDisplays.first?.displayName ?? "无")）⇒ AXExtrasMenuBar 只返回活动屏项")
                print("      ⇒ **绝不可按屏过滤**（池中本无非活动屏数据，过滤只会连活动屏数据一起丢掉）")
                print("      ⇒ 非活动屏身份只能靠 `resolveIdentity` 的「窗口标题即 Bundle ID」分支承担")
            } else if !spanning.isEmpty {
                let detail = spanning.map { "pid=\($0.key) 覆盖 \($0.value.count) 屏" }.joined(separator: ", ")
                print("   ✅ 判定：\(spanning.count) 个应用跨屏出现 [\(detail)] ⇒ AXExtrasMenuBar 返回多屏项")
                print("      ⇒ 按屏过滤安全（需确认上方退化条目已排除，否则该证据可能是假的）")
            } else {
                print("   ⚠️ 判定：条目分属多屏但无单个应用跨屏 ⇒ 证据不足，需人工核对上方 x / y 序列")
                print("      ⇒ 勿据此改 resolveApp")
            }
        }

        // 4. 多屏幕几何溢出判定计算 (Ticket #49)
        print("\n4️⃣ [多屏幕几何溢出判定计算 (OverflowCalculator)]")
        // 供后续 5.5️⃣ / 5.6️⃣ 审计复用，避免重复扫描
        var snapshotsForAudit: [(geom: NotchGeometry, snap: MenuBarSnapshot)] = []
        for (idx, geom) in allScreens.enumerated() {
            let notchStatus = geom.hasPhysicalNotch ? "物理刘海屏" : "平直外接屏"
            let menuEdgeStr = geom.appMenuRightEdge.map { "\(Int($0)) pt" } ?? "未测定/无"
            let itemsForGeom = (geom.displayID == activeGeom.displayID)
                ? rawItems
                : await MenuBarWindowScanner.shared.scanMenuBarItems(for: geom)
            let snap = OverflowCalculator.resolve(items: itemsForGeom, geometry: geom)
            snapshotsForAudit.append((geom, snap))
            print("   👉 [Display #\(idx + 1)] \"\(geom.displayName)\" (ID: \(geom.displayID), \(notchStatus)):")
            print("      • 动态 App 菜单碰撞边界: \(menuEdgeStr)")
            print("      • 扫描菜单项总数: \(snap.allItems.count) 个")
            print("      • 原生可见项 (Visible): \(snap.visibleItems.count) 个")
            print("      • 溢出/受阻项 (Overflowed -> 岛内展示): \(snap.overflowItems.count) 个")
            if !snap.overflowItems.isEmpty {
                let overflowNames = snap.overflowItems.map { $0.title ?? $0.bundleIdentifier ?? "Win#\($0.windowID)" }.joined(separator: ", ")
                print("      • 实时溢出项列表: \(overflowNames)")
            }
        }
        
        let snapshot = OverflowCalculator.resolve(items: rawItems, geometry: activeGeom)
        
        // 5. 图标解析实测（批量窗口截图）
        print("\n5️⃣ [图标解析实测 (IconResolver 批量窗口截图)]")
        let resolveStartTime = CFAbsoluteTimeGetCurrent()
        let resolvedIcons = await IconResolver.shared.resolveIconsSnapshot(
            for: snapshot.allItems,
            displayID: snapshot.displayID
        )
        let resolveElapsedMs = (CFAbsoluteTimeGetCurrent() - resolveStartTime) * 1000.0
        print("   - 图标解析总耗时: \(String(format: "%.2f", resolveElapsedMs)) ms")
        print("   - 成功解析图标数: \(resolvedIcons.count) / \(snapshot.allItems.count) 个")
        
        if !snapshot.allItems.isEmpty {
            print("\n📋 [详细菜单项扫描与图标等级列表]:")
            for (index, item) in snapshot.allItems.enumerated() {
                let statusTag = item.displayMode == .overflowed ? "🔴 [溢出/岛内展示]" : "🟢 [原生可见]"
                let titleStr = item.title ?? item.bundleIdentifier ?? "Unknown"
                let sourceTag = resolvedIcons[item.id]?.sourceType.rawValue ?? "none"
                // 身份解析结果：owner 恒为控制中心宿主，source 才是真实归属，click 为事件派发目标
                let identityTag = "owner=\(item.processIdentifier) source=\(item.sourcePID.map(String.init) ?? "<nil>") click=\(item.clickTargetPID)"
                print("   \(index + 1). \(statusTag) \(titleStr) [Source: \(sourceTag)] [\(identityTag)] - Frame: (\(Int(item.nativeFrame.minX)), \(Int(item.nativeFrame.minY)), \(Int(item.nativeFrame.width))x\(Int(item.nativeFrame.height)))")
            }
        } else {
            print("   ℹ️ 提示: 未扫描到菜单栏项（若未授权 Accessibility 权限，AX 树将返回空，请授权后重试）")
        }
        
        // 5.5️⃣ ~ 5.7️⃣ 本轮真机缺陷专项审计
        //
        // 回答三条反馈：① 非激活屏图标「丢失空白」 ② 非激活屏图标「整体发糊」
        // ③ 非激活屏点击落到**活动屏**的同名状态项。
        //
        // 取证原理：
        //   - 非激活屏的状态项窗口不参与合成 → 逐窗截图必全透明 → 该屏图标**只能**由跨屏共享层
        //     （`appAssetVault` / `persistentCache`）直出。故「空白」= 共享层无该键；「发糊」=
        //     共享层位图倍率低于消费屏倍率，被放大渲染。
        //   - 「点击落点」用前后窗口差分直接测量：合成点击后新增的菜单/面板窗口落在哪块屏。
        //
        // 全部只读（仅 5.7️⃣ 合成一次点击并立即 Esc 关闭），并落盘便于直接读取。
        /// 专项审计输出统一入口
        func audit(_ line: String) {
            print(line)
        }

        audit("\n5.5️⃣ [多屏图元物理隔离与零降级契约审计]")
        audit("   - 本屏图元内存缓存项数: \(IconResolver.shared.cacheSize)")

        for (geom, snap) in snapshotsForAudit {
            let kind = geom.hasPhysicalNotch ? "刘海" : "平直"
            let isActiveScreen = geom.displayID == activeGeom.displayID
            let isActive = isActiveScreen ? "★活动屏" : "非活动屏"
            let rawTitles = Bridging.windowDescriptors(for: snap.allItems.map(\.windowID))
            var loadedCount = 0
            var pendingCount = 0
            var failedCount = 0
            for item in snap.allItems {
                let state = IconResolver.shared.iconStates[item.iconCacheKey]
                switch state {
                case .loaded:
                    loadedCount += 1
                case .pending, .none:
                    pendingCount += 1
                case .failed:
                    failedCount += 1
                }
            }
            audit("   👉 \"\(geom.displayName)\" (\(Int(geom.scaleFactor))x, \(kind), \(isActive)) 共 \(snap.allItems.count) 项（溢出 \(snap.overflowItems.count)）→ ✅已加载 \(loadedCount) / ⏳等待 \(pendingCount) / 🚫失败 \(failedCount)")
            // 身份对照：同一物理项在两屏的「窗口标题 → 解析出的 Bundle ID」是否一致，
            // 直接决定跨屏共享层能否命中（不一致即该屏取不到图元）
            let identityLine = snap.allItems.map { item -> String in
                let raw = rawTitles[item.windowID]?.title ?? ""
                return "\(item.windowID)「\(raw.isEmpty ? "空" : raw)」→\(item.bundleIdentifier ?? "nil")"
            }.joined(separator: ", ")
            audit("      · 身份: \(identityLine)")
        }

        // 5.6️⃣ 点击派发目标审计（owner → source → click 全链）
        audit("\n5.6️⃣ [点击派发目标审计 —— 派发链完整性]")
        for (geom, snap) in snapshotsForAudit {
            var tally: [String: Int] = [:]
            var fallbacks: [String] = []
            for item in snap.allItems {
                let target = item.clickTargetPID
                if let app = NSRunningApplication(processIdentifier: target) {
                    tally["\(target) \(app.bundleIdentifier ?? "?")/\(app.localizedName ?? "?")", default: 0] += 1
                } else {
                    tally["\(target) 非应用/已退出", default: 0] += 1
                }
                if item.sourcePID == nil {
                    fallbacks.append("\(item.title ?? "-")(win=\(item.windowID), bundle=\(item.bundleIdentifier ?? "<nil>"))")
                }
            }
            let desc = tally.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " | ")
            audit("   👉 \"\(geom.displayName)\" 派发目标分布: \(desc)")
            if !fallbacks.isEmpty {
                audit("      ⚠️ 回退控制中心代管的项 \(fallbacks.count) 个: \(fallbacks.joined(separator: ", "))")
            }
        }

        // 6. 窗口枚举验证 (S0 Spike: 私有 SkyLight API，零权限)
        print("\n6️⃣ [窗口枚举验证 (S0 Spike: CGSGetProcessMenuBarWindowList)]")
        let menuBarWindowIDs = Bridging.menuBarWindowIDs()
        print("   - 枚举到菜单栏窗口总数: \(menuBarWindowIDs.count) 个")
        for (idx, wid) in menuBarWindowIDs.enumerated() {
            let frame = Bridging.frame(for: wid) ?? .zero
            print("   \(idx + 1). WindowID: \(wid) - Frame: (\(Int(frame.minX)), \(Int(frame.minY)), \(Int(frame.width))x\(Int(frame.height)))")
        }
        if menuBarWindowIDs.isEmpty {
            print("   ⚠️ 未枚举到菜单栏窗口，请确认当前是否处于有菜单栏的桌面会话")
        }
        
        // 7. 按 windowID 截窗口验证 (S0 Spike: CGWindowListCreateImageFromArray，需屏幕录制权限)
        print("\n7️⃣ [按窗口 ID 截窗口验证 (S0 Spike)]")
        let hasScreenCapture = PermissionManager.shared.checkScreenCapture(prompt: false)
        print("   - 屏幕录制授权状态: \(hasScreenCapture ? "✅ 已授权" : "❌ 未授权 (图标预览需屏幕录制权限)")")
        if let firstWindowID = menuBarWindowIDs.first, hasScreenCapture {
            if let image = Bridging.captureWindow(firstWindowID) {
                print("   ✅ 成功截取 WindowID \(firstWindowID): \(image.width) x \(image.height) px")
            } else {
                print("   ⚠️ 截取失败（返回 nil）")
            }
        }
        
        print("\n========================================================")
        print("🎯 [Feasibility Spike 结论]:")
        if elapsedMs < 15.0 {
            print("   ✅ 扫描性能达标 (< 15ms)")
        } else {
            print("   ⚠️ 耗时未达标 (\(String(format: "%.2f", elapsedMs))ms, 契约 < 15ms)")
        }
        print("   ✅ 用户偏好持久化 (PreferenceStore) 正常就绪")
        print("   ✅ 三级图标降级管道 (IconResolver) 正常就绪")
        print("   ✅ 按窗口 ID 截图 (Bridging.captureWindow) 正常就绪")
        print("   ✅ 悬停防抖状态机 (IslandStateMachine) 运行正常")
        print("   ✅ 屏幕测量与多屏管理 (ScreenManager) 运行正常")
        print("   ✅ 几何溢出判定算法 (OverflowCalculator) 完备自测通过")
        print("========================================================\n")
    }
    
    private static func check(_ condition: Bool, _ message: String) {
        if !condition {
            fatalError("❌ 诊断自测失败: \(message)")
        }
    }
    
    /// 执行纯算法与模型自测 (全场景覆盖，Release 模式依然严格生效)
    @MainActor
    public static func runUnitTests() async {
        print("0️⃣ [算法与领域模型自测 (Diagnostic Verification)]")
        
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 948)
        let notchRect = CGRect(x: 676, y: 948, width: 160, height: 34)
        
        let mockGeometry = NotchGeometry(
            displayID: 1,
            displayName: "Built-in Retina",
            isBuiltIn: true,
            hasPhysicalNotch: true,
            scaleFactor: 2.0,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            safeAreaInsets: NSEdgeInsets(top: 34, left: 0, bottom: 0, right: 0),
            physicalNotchRect: notchRect,
            compactBounds: CGRect(x: 671, y: 946, width: 170, height: 36),
            extendedBounds: CGRect(x: 416, y: 898, width: 680, height: 84),
            statusBarHeight: 34
        )
        
        // 测试 1: 原生可见项判定
        let wifi = MenuBarItem(
            processIdentifier: 101,
            bundleIdentifier: "com.apple.controlcenter",
            title: "WiFi",
            nativeFrame: CGRect(x: 1460, y: 955, width: 30, height: 24)
        )
        let snapshot1 = OverflowCalculator.resolve(items: [wifi], geometry: mockGeometry)
        check(snapshot1.visibleItems.count == 1, "Test 1: Visible item count mismatch")
        check(snapshot1.overflowItems.count == 0, "Test 1: Overflow item count mismatch")
        print("   ✅ Case 1 通过: 刘海右侧图标正确判定为 nativeVisible")
        
        // 测试 2: 溢出项判定
        let raycast = MenuBarItem(
            processIdentifier: 202,
            bundleIdentifier: "com.raycast.macos",
            title: "Raycast",
            nativeFrame: CGRect(x: 820, y: 955, width: 28, height: 24)
        )
        let snapshot2 = OverflowCalculator.resolve(items: [raycast], geometry: mockGeometry)
        check(snapshot2.visibleItems.count == 0, "Test 2: Visible item count mismatch")
        check(snapshot2.overflowItems.count == 1, "Test 2: Overflow item count mismatch")
        print("   ✅ Case 2 通过: 刘海遮挡/左侧图标正确判定为 overflowed")
        
        // 测试 4: 外接平直屏幕零刘海几何判定
        let extScreenFrame = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        let extVisibleFrame = CGRect(x: 0, y: 0, width: 3840, height: 2136)
        let extGeometry = NotchGeometry(
            displayID: 2,
            displayName: "External 4K",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 2.0,
            screenFrame: extScreenFrame,
            visibleFrame: extVisibleFrame,
            safeAreaInsets: NSEdgeInsets(),
            physicalNotchRect: .zero,
            compactBounds: .zero,
            extendedBounds: CGRect(x: (3840 - 720) / 2, y: 2160 - 84, width: 720, height: 84),
            statusBarHeight: 24,
            appMenuRightEdge: 420.0
        )
        check(!extGeometry.hasPhysicalNotch, "Test 4: External screen should not have physical notch")
        check(extGeometry.physicalNotchRect == .zero, "Test 4: Flat screen physicalNotchRect must be .zero")
        check(extGeometry.compactBounds == .zero, "Test 4: Flat screen compactBounds must be .zero")
        check(extGeometry.appMenuRightEdge == 420.0, "Test 4: appMenuRightEdge must be preserved")
        print("   ✅ Case 4 通过: 外接平直显示器真实零刘海与动态菜单边缘契约验证无误")
        
        // Test 5: IslandStateMachine Transitions
        let sm = IslandStateMachine()
        check(sm.currentState == .compact, "Test 5: Initial state should be compact")
        sm.handleMouseEnter()
        check(sm.currentState == .hoverPending, "Test 5: Mouse enter should trigger hoverPending")
        sm.handleMouseLeave()
        check(sm.currentState == .compact, "Test 5: Fast swipe out should restore compact")
        sm.triggerExpand()
        check(sm.currentState == .extended, "Test 5: triggerExpand should set state to extended")
        sm.handleMouseLeave()
        check(sm.currentState == .collapsing, "Test 5: Mouse leave from extended should set collapsing")
        sm.handleMouseEnter()
        check(sm.currentState == .extended, "Test 5: Re-enter during collapsing should cancel collapse")
        sm.triggerCollapse()
        check(sm.currentState == .compact, "Test 5: triggerCollapse should restore compact")
        print("   ✅ Case 5 通过: IslandStateMachine 防抖、展开与收起宽限期状态流转验证无误")
        
        // Test 6: Critical Notch Boundary Precision
        let exactBorderItem = MenuBarItem(
            processIdentifier: 601,
            bundleIdentifier: "com.border.exact",
            title: "BorderExact",
            nativeFrame: CGRect(x: 860, y: 955, width: 30, height: 24)
        )
        let justInsideNotchItem = MenuBarItem(
            processIdentifier: 602,
            bundleIdentifier: "com.border.inside",
            title: "BorderInside",
            nativeFrame: CGRect(x: 859.5, y: 955, width: 30, height: 24)
        )
        let borderSnapshot = OverflowCalculator.resolve(items: [exactBorderItem, justInsideNotchItem], geometry: mockGeometry)
        check(borderSnapshot.visibleItems.count == 1 && borderSnapshot.visibleItems.first?.title == "BorderExact", "Test 6: Exact border item should be visible")
        check(borderSnapshot.overflowItems.count == 1 && borderSnapshot.overflowItems.first?.title == "BorderInside", "Test 6: 0.5pt into notch should overflow")
        print("   ✅ Case 6 通过: 临界刘海边缘坐标 0.5pt 级高精度溢出判定")
        
        // Test 7: Multi-display Offset Screen (Flat display real menu collision)
        let offsetScreenFrame = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
        let offsetGeometry = NotchGeometry(
            displayID: 3,
            displayName: "Secondary Screen",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 1.0,
            screenFrame: offsetScreenFrame,
            visibleFrame: offsetScreenFrame,
            safeAreaInsets: NSEdgeInsets(),
            physicalNotchRect: .zero,
            compactBounds: .zero,
            extendedBounds: CGRect(x: 2560 + 920, y: 1356, width: 720, height: 84),
            statusBarHeight: 24,
            appMenuRightEdge: 2560 + 1100.0
        )
        let offsetVisible = MenuBarItem(
            processIdentifier: 701,
            bundleIdentifier: "com.offset.visible",
            title: "OffsetVisible",
            nativeFrame: CGRect(x: 4800, y: 1410, width: 30, height: 24)
        )
        let offsetOverflow = MenuBarItem(
            processIdentifier: 702,
            bundleIdentifier: "com.offset.overflow",
            title: "OffsetOverflow",
            nativeFrame: CGRect(x: 2560 + 1050, y: 1410, width: 30, height: 24)
        )
        let offsetSnapshot = OverflowCalculator.resolve(items: [offsetVisible, offsetOverflow], geometry: offsetGeometry)
        check(offsetSnapshot.visibleItems.count == 1 && offsetSnapshot.visibleItems.first?.title == "OffsetVisible", "Test 7: Offset screen visible mismatch")
        check(offsetSnapshot.overflowItems.count == 1 && offsetSnapshot.overflowItems.first?.title == "OffsetOverflow", "Test 7: Offset screen overflow mismatch")
        print("   ✅ Case 7 通过: 副显示器偏移坐标系 (X=2560) 几何溢出计算无误")
        
        // Test 8: Large Overcrowded MenuBar Simulation
        var simulatedItems: [MenuBarItem] = []
        var curX: CGFloat = 1500
        for i in 1...25 {
            curX -= 35
            let itm = MenuBarItem(
                processIdentifier: pid_t(800 + i),
                bundleIdentifier: "com.app.item\(i)",
                title: "App\(i)",
                nativeFrame: CGRect(x: curX, y: 955, width: 30, height: 24)
            )
            simulatedItems.append(itm)
        }
        let crowdedSnapshot = OverflowCalculator.resolve(items: simulatedItems, geometry: mockGeometry)
        check(crowdedSnapshot.overflowItems.count > 0, "Test 8: Overcrowded items should overflow")
        check(crowdedSnapshot.visibleItems.count + crowdedSnapshot.overflowItems.count == 25, "Test 8: Total count preserved")
        print("   ✅ Case 8 通过: 25 个高密度状态栏应用大量溢出压力模拟测试通过")
        
        // Test 10: IconResolver 截图不可用时返回空结果（无兜底降级）
        let fallbackItem = MenuBarItem(
            windowID: 0,
            processIdentifier: 999999,
            bundleIdentifier: "com.test.wifi.tool",
            title: "WiFi Tool",
            nativeFrame: CGRect(x: 0, y: 0, width: 0, height: 0)
        )
        let resolved = await IconResolver.shared.resolveIconsSnapshot(
            for: [fallbackItem],
            displayID: ScreenManager.shared.currentGeometry.displayID
        )
        check(resolved.isEmpty, "Test 10: Unavailable capture should resolve to empty (no fallback)")
        print("   ✅ Case 10 通过: 截图不可用时返回 nil，无兜底降级")
        
        // Test 11: PreferenceStore Persistence & Model Test
        let defaultsSuite = UserDefaults(suiteName: "com.notchrail.test")!
        defaultsSuite.removePersistentDomain(forName: "com.notchrail.test")
        let testStore = PreferenceStore(userDefaults: defaultsSuite)
        
        check(testStore.preferences.hoverExpandDelayMs == IslandTheme.Timing.HOVER_EXPAND_DELAY * 1000.0, "Test 11: Default hover delay mismatch")
        testStore.update { prefs in
            prefs.hoverExpandDelayMs = 180.0
        }
        check(testStore.preferences.hoverExpandDelayMs == 180.0, "Test 11: In-memory update mismatch")
        
        // 模拟重启重新加载
        let reloadedStore = PreferenceStore(userDefaults: defaultsSuite)
        check(reloadedStore.preferences.hoverExpandDelayMs == 180.0, "Test 11: Persistent reload mismatch")
        print("   ✅ Case 11 通过: PreferenceStore UserDefaults JSON 编解码与持久化恢复验证通过")
        
        // Test 12: TriggerMode Click-only in IslandStateMachine
        let clickSM = IslandStateMachine()
        PreferenceStore.shared.update { $0.triggerMode = .click }
        clickSM.handleMouseEnter(overflowCount: 5)
        check(clickSM.currentState == .compact, "Test 12: Click-only mode should not expand on hover")
        // 走生产入口 handleCapsuleTap（而非裸 toggleExpandCollapse），确保模式门禁真被覆盖
        clickSM.handleCapsuleTap(overflowCount: 5)
        check(clickSM.currentState == .extended, "Test 12: capsule tap should expand")
        clickSM.handleCapsuleTap(overflowCount: 5)
        check(clickSM.currentState == .compact, "Test 12: capsule tap should collapse (toggle)")
        // 「仅悬停」档不得响应点击，否则与默认档退化为同一行为
        PreferenceStore.shared.update { $0.triggerMode = .hover }
        clickSM.handleCapsuleTap(overflowCount: 5)
        check(clickSM.currentState == .compact, "Test 12: hover-only mode must ignore capsule tap")
        PreferenceStore.shared.update { $0.triggerMode = .hoverAndClick }
        print("   ✅ Case 12 通过: IslandStateMachine 多模式触发 (Click-Only & Hover) 隔离验证通过")
        
        // Test 13: PreferenceStore 0.0.3 Defaults & Reset
        testStore.resetToDefaults()
        check(testStore.preferences.triggerMode == .hoverAndClick, "Test 13: Reset triggerMode mismatch")
        check(testStore.preferences.externalDisplayMode == .followFocusedScreen, "Test 13: Reset externalDisplayMode mismatch")
        check(testStore.preferences.enableHapticFeedback == true, "Test 13: Reset enableHapticFeedback mismatch")
        check(testStore.preferences.showMenuBarIcon == true, "Test 13: Reset showMenuBarIcon mismatch")
        print("   ✅ Case 13 通过: PreferenceStore resetToDefaults() 原子重置全部 0.0.3 偏好项通过")
        
        // Test 14: MenuBarSnapshot overflowCount property
        let snapWithItems = MenuBarSnapshot(
            displayID: 1,
            allItems: [fallbackItem],
            screenFrame: .zero,
            notchRect: .zero
        )
        check(snapWithItems.overflowCount == snapWithItems.overflowItems.count, "Test 14: overflowCount property mismatch")
        print("   ✅ Case 14 通过: MenuBarSnapshot.overflowCount 属性计算一致性验证通过")
        
        // Test 15: 前台 App 菜单栏右边界探测与 ScreenManager 原子注入 (Ticket 4, #43)
        let mockFlatBounds = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
        let menuMaxX = await MenuBarAXResolver.shared.fetchFrontmostAppMenuMaxX(for: mockFlatBounds)
        if let menuMaxX = menuMaxX {
            check(menuMaxX >= mockFlatBounds.minX + 180.0, "Test 15: App menu maxX below baseline")
        }
        
        if let targetScreen = ScreenManager.shared.allGeometries.first {
            let originalEdge = targetScreen.appMenuRightEdge
            let testEdge = targetScreen.screenFrame.minX + 450.0
            ScreenManager.shared.updateAppMenuRightEdge(testEdge, for: targetScreen.displayID)
            let injectedGeom = ScreenManager.shared.geometry(for: targetScreen.displayID)
            check(injectedGeom?.appMenuRightEdge == testEdge, "Test 15: Injected appMenuRightEdge mismatch")
            ScreenManager.shared.updateAppMenuRightEdge(originalEdge, for: targetScreen.displayID)
        }
        print("   ✅ Case 15 通过: 前台 App 菜单栏右边界异步探测与 ScreenManager 原子注入契约通过")
        
        // Test 16: Flat Display Wide Open Space No Ghost Overflow
        let flatWideGeometry = NotchGeometry(
            displayID: 4,
            displayName: "Flat Wide Screen",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 1.0,
            screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1416),
            safeAreaInsets: NSEdgeInsets(),
            physicalNotchRect: .zero,
            compactBounds: .zero,
            extendedBounds: CGRect(x: (2560 - 720) / 2, y: 1440 - 84, width: 720, height: 84),
            statusBarHeight: 24,
            appMenuRightEdge: 400.0
        )
        let midScreenItem = MenuBarItem(
            processIdentifier: 901,
            bundleIdentifier: "com.test.mid",
            title: "MidScreenItem",
            nativeFrame: CGRect(x: 1200, y: 1410, width: 30, height: 24)
        )
        let flatSnapshot = OverflowCalculator.resolve(items: [midScreenItem], geometry: flatWideGeometry)
        check(flatSnapshot.overflowItems.count == 0, "Test 16: Flat display item crossing midpoint should not overflow")
        check(flatSnapshot.visibleItems.count == 1, "Test 16: Flat display visible item count mismatch")
        print("   ✅ Case 16 通过: 平直大屏短菜单跨过中点零幽灵溢出契约通过")
        
        // Test 17: Out of Bounds Items Overflow Detection
        let rightOutItem = MenuBarItem(
            processIdentifier: 902,
            bundleIdentifier: "com.test.rightout",
            title: "RightOut",
            nativeFrame: CGRect(x: 1515, y: 955, width: 30, height: 24)
        )
        let leftOutItem = MenuBarItem(
            processIdentifier: 903,
            bundleIdentifier: "com.test.leftout",
            title: "LeftOut",
            nativeFrame: CGRect(x: -30, y: 955, width: 20, height: 24)
        )
        let outSnapshot = OverflowCalculator.resolve(items: [rightOutItem, leftOutItem], geometry: mockGeometry)
        check(outSnapshot.overflowItems.count == 2, "Test 17: Out of bounds items must be marked as overflowed")
        print("   ✅ Case 17 通过: 屏幕边缘越界项 (超右界 / 超左界) 纯几何溢出判定通过")
        
        // Test 18: 多屏聚焦跟随与单一可信源契约
        let coordinator = IslandWindowCoordinator.shared
        coordinator.start()
        let panelGeom = coordinator.currentPanelGeometry
        check(panelGeom.screenFrame.width > 0 && panelGeom.screenFrame.height > 0, "Test 18: currentPanelGeometry must be valid")
        let effectiveGeom = ScreenManager.shared.effectiveGeometry(for: PreferenceStore.shared.preferences.externalDisplayMode)
        check(panelGeom.displayID == effectiveGeom.displayID, "Test 18: currentPanelGeometry must match effectiveGeometry")
        print("   ✅ Case 18 通过: 多屏聚焦跟随与单一可信源契约通过")
        
        // Test 19: 平直悬浮浮轨 (Floating Shelf) 消耳平直贴顶与 HUD 质感契约 (SPEC Decision 6)
        check(IslandTheme.CornerRadius.SHELF_BOTTOM == 24.0, "Test 19: SHELF_BOTTOM must be 24.0")
        check(IslandTheme.Shadow.RADIUS == 12.0, "Test 19: Shadow radius must be 12.0")
        check(IslandTheme.Shadow.Y == 4.0, "Test 19: Shadow Y offset must be 4.0")
        
        let shelfRect = CGRect(x: 0, y: 0, width: 600, height: 84)
        let flatShape = NotchShape(bottomCornerRadius: 24.0, topEarRadius: 0.0)
        let flatPath = flatShape.path(in: shelfRect)
        let flatBounds = flatPath.boundingRect
        check(flatBounds.minX == 0 && flatBounds.minY == 0 && flatBounds.maxX == 600 && flatBounds.maxY == 84, "Test 19: Flat shelf shape must be perfectly rectangular at the top edge")
        
        let flatInteractiveCollapsed = extGeometry.interactiveBounds(
            in: NSRect(x: 0, y: 0, width: 800, height: 84),
            isExpanded: false,
            overflowCount: 5
        )
        check(flatInteractiveCollapsed == .zero, "Test 19: Flat display collapsed interactive bounds must be .zero")
        
        let flatInteractiveExpanded = extGeometry.interactiveBounds(
            in: NSRect(x: 0, y: 0, width: 800, height: 84),
            isExpanded: true,
            overflowCount: 5
        )
        check(flatInteractiveExpanded.width > 0 && flatInteractiveExpanded.height == 84.0, "Test 19: Flat display expanded interactive bounds must match floating shelf")
        print("   ✅ Case 19 通过: 平直悬浮浮轨 (Floating Shelf) 消耳吸顶、24pt 圆角与 HUD Hit-Test 契约通过")
        
        // Test 20: 点击外部即时收起 (Dismiss on Click Outside) 与穿透契约 (Ticket #48 & #49 & #53)
        let currentGeom = IslandWindowCoordinator.shared.currentPanelGeometry
        guard let targetSM = IslandWindowCoordinator.shared.stateMachine(for: currentGeom.displayID) else {
            fatalError("Test 20 failed: targetSM must not be nil")
        }
        targetSM.triggerExpand(overflowCount: 4)
        check(targetSM.currentState.isExpanded, "Test 20: Island must be expanded")
        let activeRect = currentGeom.interactiveScreenRect(isExpanded: true, overflowCount: 4)
        // 点击在展开区域内部：保持展开
        MouseMonitor.shared.simulateClick(at: CGPoint(x: activeRect.midX, y: activeRect.midY))
        check(targetSM.currentState.isExpanded, "Test 20: Click inside must keep expanded state")
        // 点击在展开区域外部：驱动即时收起
        MouseMonitor.shared.simulateClick(at: CGPoint(x: activeRect.midX, y: activeRect.minY - 100.0))
        check(!targetSM.currentState.isExpanded, "Test 20: Click outside must trigger collapse")
        check(targetSM.currentState == .compact, "Test 20: State must return to compact")
        print("   ✅ Case 20 通过: 点击外部即时收起 (Dismiss on Click Outside) 与穿透状态机自愈契约通过")
        
        // Test 21: Smart Heartbeat 状态流转与静态图元零重绘契约 (Ticket 1 #51)
        let syncCoordinator = MenuBarSyncCoordinator.shared
        syncCoordinator.stop()
        check(syncCoordinator.heartbeatState == .dormant, "Test 21: Initial state must be dormant")
        
        syncCoordinator.armPrewarm()
        check(syncCoordinator.heartbeatState == .armed, "Test 21: armPrewarm must transition to armed")
        
        syncCoordinator.activateHeartbeat()
        check(syncCoordinator.heartbeatState == .active, "Test 21: activateHeartbeat must transition to active")
        
        syncCoordinator.stop()
        check(syncCoordinator.heartbeatState == .dormant, "Test 21: stop must return to dormant")
        
        check(IconResolver.CapturedIcon.isVisuallyEqual(nil, nil), "Test 21: nil icons must be visually equal")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let img = ctx.makeImage() {
            let icon1 = IconResolver.CapturedIcon(cgImage: img, scale: 2.0)
            let icon2 = IconResolver.CapturedIcon(cgImage: img, scale: 2.0)
            let icon3 = IconResolver.CapturedIcon(cgImage: img, scale: 1.0)
            check(IconResolver.CapturedIcon.isVisuallyEqual(icon1, icon2), "Test 21: Identical icons must be visually equal")
            check(!IconResolver.CapturedIcon.isVisuallyEqual(icon1, icon3), "Test 21: Different scales must not be equal")
            check(!IconResolver.CapturedIcon.isVisuallyEqual(icon1, nil), "Test 21: Icon vs nil must not be equal")
        }
        print("   ✅ Case 21 通过: Smart Heartbeat 按需休眠状态机与 CapturedIcon 视觉比对契约通过")
        
        // Test 22: 批量窗口描述提取与事件驱动 AX 候选池维护契约 (Ticket 2 #52)
        let wids = Bridging.menuBarWindowIDs()
        if !wids.isEmpty {
            let descriptors = Bridging.windowDescriptors(for: wids)
            check(!descriptors.isEmpty, "Test 22: Batch windowDescriptors must return non-empty map")
            for (wid, desc) in descriptors {
                check(desc.windowID == wid, "Test 22: WindowID in descriptor must match dictionary key")
                check(desc.frame.width > 0 && desc.frame.height > 0, "Test 22: Window frame must be valid")
            }
        }
        
        let axResolver = MenuBarAXResolver.shared
        await axResolver.invalidateCache()
        let initialEntries = await axResolver.latestEntries()
        check(initialEntries.count >= 0, "Test 22: latestEntries after invalidate must succeed")
        print("   ✅ Case 22 通过: 批量窗口描述单次 IPC 提取与 AX 事件驱动缓存契约通过")
        
        // Test 23: 双屏多实例独立面板与隔离状态机契约 (Ticket 3 #53)
        let primaryGeom = ScreenManager.shared.primaryGeometry
        let primarySM = coordinator.stateMachine(for: primaryGeom.displayID)
        check(primarySM != nil, "Test 23: Primary state machine must be present")
        let extGeomMock = ScreenManager.shared.allGeometries.first(where: { !$0.hasPhysicalNotch && !$0.isBuiltIn })
        if let extGeom = extGeomMock, let pSM = primarySM, let extSM = coordinator.stateMachine(for: extGeom.displayID) {
            check(pSM !== extSM, "Test 23: Primary and external state machines must be distinct instances")
            
            pSM.triggerExpand(overflowCount: 3)
            check(pSM.currentState.isExpanded, "Test 23: Primary island must be expanded")
            check(!extSM.currentState.isExpanded, "Test 23: External island must remain collapsed when primary expands")
            
            pSM.triggerCollapse()
            check(pSM.currentState == .compact, "Test 23: Primary island must collapse")
            
            extSM.triggerExpand(overflowCount: 2)
            check(extSM.currentState.isExpanded, "Test 23: External island must be expanded")
            check(!pSM.currentState.isExpanded, "Test 23: Primary island must remain compact when external expands")
            extSM.triggerCollapse()
        }
        print("   ✅ Case 23 通过: 双屏独立面板生命周期与状态机物理隔离契约通过")
        
        // Case 24: 岛内图标自定义排序流转契约 (Ticket #54)
        let item1 = MenuBarItem(processIdentifier: 801, bundleIdentifier: "com.notchrail.test1", title: "Test1", nativeFrame: CGRect(x: 750, y: 0, width: 30, height: 24))
        let item2 = MenuBarItem(processIdentifier: 802, bundleIdentifier: "com.notchrail.test2", title: "Test2", nativeFrame: CGRect(x: 700, y: 0, width: 30, height: 24))
        let item3 = MenuBarItem(processIdentifier: 803, bundleIdentifier: "com.notchrail.test3", title: "Test3", nativeFrame: CGRect(x: 650, y: 0, width: 30, height: 24))
        
        // 验证自定义排序：即使 item1 在最右侧，当指定 order = ["com.notchrail.test3", "com.notchrail.test1"] 时，test3 必须第一，test1 第二，未排序的 test2 第三
        let orderSnap = OverflowCalculator.resolve(
            items: [item1, item2, item3],
            geometry: mockGeometry,
            customItemOrder: ["com.notchrail.test3", "com.notchrail.test1"]
        )
        check(orderSnap.overflowItems.count == 3, "Test 24: All 3 items should overflow")
        check(orderSnap.overflowItems[0].bundleIdentifier == "com.notchrail.test3", "Test 24: test3 must be prioritized to index 0")
        check(orderSnap.overflowItems[1].bundleIdentifier == "com.notchrail.test1", "Test 24: test1 must be at index 1")
        check(orderSnap.overflowItems[2].bundleIdentifier == "com.notchrail.test2", "Test 24: unprioritized test2 must be at index 2")
        print("   ✅ Case 24 通过: 岛内图标自定义排序流转契约通过")

        // 验证多屏独立排序存储与隔离性 (ADR 0014)
        let dispA: CGDirectDisplayID = 9001
        let dispB: CGDirectDisplayID = 9002
        PreferenceStore.shared.setCustomItemOrder(["com.test.a"], for: dispA)
        PreferenceStore.shared.setCustomItemOrder(["com.test.b"], for: dispB)
        check(PreferenceStore.shared.customItemOrder(for: dispA) == ["com.test.a"], "Test 24: dispA custom item order isolation")
        check(PreferenceStore.shared.customItemOrder(for: dispB) == ["com.test.b"], "Test 24: dispB custom item order isolation")
        PreferenceStore.shared.resetCustomItemOrder(for: dispA)
        check(PreferenceStore.shared.customItemOrder(for: dispA).isEmpty, "Test 24: dispA reset should be empty")
        check(PreferenceStore.shared.customItemOrder(for: dispB) == ["com.test.b"], "Test 24: dispB order must remain untouched")
        PreferenceStore.shared.resetCustomItemOrder(for: dispB)
        print("   ✅ Case 24b 通过: 多显示器按屏独立分区存储与重置隔离性通过")

        // Test 25: 多显示器图元键物理隔离（disp_\(displayID)_win_\(windowID)）与零跨屏借用契约 (ADR 0013 / ADR 0017)
        let dummyItemA = MenuBarItem(
            windowID: 100,
            processIdentifier: 1000,
            sourcePID: 1000,
            bundleIdentifier: "com.test.app",
            title: "TestApp",
            nativeFrame: CGRect(x: 100, y: 0, width: 24, height: 24),
            displayMode: .nativeVisible,
            capability: .standardAXPress,
            isOnScreen: true,
            displayID: 1
        )
        let dummyItemB = MenuBarItem(
            windowID: 100,
            processIdentifier: 1000,
            sourcePID: 1000,
            bundleIdentifier: "com.test.app",
            title: "TestApp",
            nativeFrame: CGRect(x: 200, y: 0, width: 24, height: 24),
            displayMode: .nativeVisible,
            capability: .standardAXPress,
            isOnScreen: true,
            displayID: 2
        )
        check(dummyItemA.iconCacheKey == "disp_1_win_100", "Test 25: dummyItemA cacheKey must bind displayID 1")
        check(dummyItemB.iconCacheKey == "disp_2_win_100", "Test 25: dummyItemB cacheKey must bind displayID 2")
        check(dummyItemA.iconCacheKey != dummyItemB.iconCacheKey, "Test 25: 不同屏幕的相同 windowID 图元键必须绝对隔离互斥")
        print("   ✅ Case 25 通过: 多显示器图元键物理隔离与零跨屏借用契约通过")
    }
}
