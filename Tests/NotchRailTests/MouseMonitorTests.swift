import Foundation
import CoreGraphics
import AppKit
@testable import NotchRailKit

@MainActor
final class MouseMonitorTests: XCTestCase {
    
    func testTopEdgeHotZoneDetection() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117) // 全屏空间（可见高度贴紧屏幕物理高度）
        let geom = NotchGeometry(
            displayID: 1,
            displayName: "Main Display",
            isBuiltIn: true,
            hasPhysicalNotch: true,
            scaleFactor: 2.0,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            physicalNotchRect: CGRect(x: 774, y: 1083, width: 180, height: 34),
            compactBounds: CGRect(x: 774, y: 1083, width: 180, height: 34),
            extendedBounds: CGRect(x: 464, y: 1033, width: 800, height: 84),
            statusBarHeight: 34
        )
        
        // 1. 顶边缘 2pt 默认阈值判定（Y >= 1115）
        let touchTop = CGPoint(x: 300, y: 1116)
        XCTAssertTrue(geom.isPointInTopEdgeHotZone(touchTop))
        
        let touchTop1pt = CGPoint(x: 300, y: 1115.5)
        XCTAssertTrue(geom.isPointInTopEdgeHotZone(touchTop1pt))
        
        // 2. 距离顶部大于 2pt 判定（Y = 1114 < 1115）
        let below2pt = CGPoint(x: 300, y: 1114)
        XCTAssertFalse(geom.isPointInTopEdgeHotZone(below2pt))
        
        // 3. 严格防误触：距离顶部大于 2pt（例如 Y=1100 < 1115）即使在刘海中下部水平区间亦不误唤醒
        let belowTopThreshold = CGPoint(x: 800, y: 1100)
        XCTAssertFalse(geom.isPointInTopEdgeHotZone(belowTopThreshold))
        
        // 4. 超出水平边界判定
        let outOfLeft = CGPoint(x: -5, y: 1116)
        XCTAssertFalse(geom.isPointInTopEdgeHotZone(outOfLeft))
        
        let outOfRight = CGPoint(x: 1730, y: 1116)
        XCTAssertFalse(geom.isPointInTopEdgeHotZone(outOfRight))
    }
    
    func testMultiDisplayOffsetTopEdgeHotZone() {
        // 副屏水平偏移 (x: 2560, y: 0, width: 2560, height: 1440)
        let offsetScreenFrame = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
        let geom = NotchGeometry(
            displayID: 2,
            displayName: "Secondary 2K Display",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 1.0,
            screenFrame: offsetScreenFrame,
            visibleFrame: offsetScreenFrame,
            physicalNotchRect: CGRect(x: 2560 + 1200, y: 1406, width: 160, height: 34),
            compactBounds: CGRect(x: 2560 + 1200, y: 1406, width: 160, height: 34),
            extendedBounds: CGRect(x: 2560 + 920, y: 1356, width: 720, height: 84),
            statusBarHeight: 24
        )
        
        // 副屏顶边缘判定（Y >= 1438, X in 2560...5120）
        let touchSecondaryTop = CGPoint(x: 3000, y: 1439)
        XCTAssertTrue(geom.isPointInTopEdgeHotZone(touchSecondaryTop))
        
        let touchPrimaryCoordsOnSecondary = CGPoint(x: 500, y: 1439)
        XCTAssertFalse(geom.isPointInTopEdgeHotZone(touchPrimaryCoordsOnSecondary))
    }
    
    // MARK: - Ticket #44: 外接平直屏中央 240pt 热区与 120ms 停留意图防抖
    
    func testExternalCenterHotZoneDetection() {
        let screenFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let geom = NotchGeometry(
            displayID: 2,
            displayName: "External 2K Flat Screen",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 1.0,
            screenFrame: screenFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1416),
            physicalNotchRect: .zero,
            compactBounds: .zero,
            extendedBounds: CGRect(x: (2560 - 720) / 2, y: 1440 - 84, width: 720, height: 84),
            statusBarHeight: 24
        )
        
        let midX = geom.screenFrame.midX // 1280.0
        let topY = geom.screenFrame.maxY // 1440.0
        
        // 1. 水平中央 240pt (1160 ... 1400)，顶边缘 4pt (1436 ... 1440) 命中判定
        let exactCenter = CGPoint(x: midX, y: topY)
        XCTAssertTrue(geom.isPointInExternalCenterHotZone(exactCenter))
        
        let centerLeftEdge = CGPoint(x: midX - 120.0, y: topY - 2.0)
        XCTAssertTrue(geom.isPointInExternalCenterHotZone(centerLeftEdge))
        
        let centerRightEdge = CGPoint(x: midX + 120.0, y: topY - 3.9)
        XCTAssertTrue(geom.isPointInExternalCenterHotZone(centerRightEdge))
        
        // 2. 水平两侧防误触避让：左侧应用菜单区 (x < midX - 120) 严格不命中
        let leftAppMenuZone = CGPoint(x: midX - 121.0, y: topY - 2.0)
        XCTAssertFalse(geom.isPointInExternalCenterHotZone(leftAppMenuZone))
        
        let farLeftAppleMenu = CGPoint(x: 20.0, y: topY - 1.0)
        XCTAssertFalse(geom.isPointInExternalCenterHotZone(farLeftAppleMenu))
        
        // 3. 水平两侧防误触避让：右侧系统托盘区 (x > midX + 120) 严格不命中
        let rightTrayZone = CGPoint(x: midX + 121.0, y: topY - 2.0)
        XCTAssertFalse(geom.isPointInExternalCenterHotZone(rightTrayZone))
        
        let farRightClock = CGPoint(x: 2540.0, y: topY - 1.0)
        XCTAssertFalse(geom.isPointInExternalCenterHotZone(farRightClock))
        
        // 4. 垂直阈值防误触：距离顶边缘 > 4pt (如 1435.0 < 1436.0) 严格不命中
        let below4pt = CGPoint(x: midX, y: topY - 4.5)
        XCTAssertFalse(geom.isPointInExternalCenterHotZone(below4pt))
        
        let middleScreen = CGPoint(x: midX, y: 720.0)
        XCTAssertFalse(geom.isPointInExternalCenterHotZone(middleScreen))
    }
    
    func testMultiDisplayOffsetExternalCenterHotZone() {
        // 多显示器水平偏移 (x: 1920, y: 0, width: 2560, height: 1440)
        let offsetScreenFrame = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let geom = NotchGeometry(
            displayID: 3,
            displayName: "Secondary Offset Display",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 1.0,
            screenFrame: offsetScreenFrame,
            visibleFrame: offsetScreenFrame,
            physicalNotchRect: .zero,
            compactBounds: .zero,
            extendedBounds: CGRect(x: 1920 + 920, y: 1356, width: 720, height: 84),
            statusBarHeight: 24
        )
        
        let midX = offsetScreenFrame.midX // 1920 + 1280 = 3200.0
        let topY = offsetScreenFrame.maxY // 1440.0
        
        // 正确偏移后的中央热区命中 (3080 ... 3320)
        let offsetCenter = CGPoint(x: midX, y: topY - 2.0)
        XCTAssertTrue(geom.isPointInExternalCenterHotZone(offsetCenter))
        
        // 主屏相对坐标在副屏上严格不命中
        let primaryCenterCoords = CGPoint(x: 1280.0, y: topY - 2.0)
        XCTAssertFalse(geom.isPointInExternalCenterHotZone(primaryCenterCoords))
    }
    
    // MARK: - Ticket #45: 外接屏全屏空间避让与系统原生菜单栏协同唤醒
    
    func testExternalFullScreenCenterBarDetection() {
        let screenFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let geom = NotchGeometry(
            displayID: 2,
            displayName: "External 2K Flat Screen",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 1.0,
            screenFrame: screenFrame,
            visibleFrame: screenFrame,
            physicalNotchRect: .zero,
            compactBounds: .zero,
            extendedBounds: CGRect(x: (2560 - 720) / 2, y: 1440 - 84, width: 720, height: 84),
            statusBarHeight: 24,
            isFullScreenSpace: true
        )
        
        let midX = geom.screenFrame.midX // 1280.0
        let topY = geom.screenFrame.maxY // 1440.0
        
        // 1. 全屏下系统菜单栏滑出区域内（maxY - 24 ... maxY），水平中央 240pt 正向命中
        let centerInMenu = CGPoint(x: midX, y: topY - 12.0)
        XCTAssertTrue(geom.isPointInExternalFullScreenCenterBar(centerInMenu))
        
        let topEdgeCenter = CGPoint(x: midX, y: topY - 1.0)
        XCTAssertTrue(geom.isPointInExternalFullScreenCenterBar(topEdgeCenter))
        
        // 2. 全屏下让位原生全屏菜单栏：左侧应用菜单区 (x: 50 ... midX - 120) 严格不命中
        let fullScreenAppleMenu = CGPoint(x: 30.0, y: topY - 10.0)
        XCTAssertFalse(geom.isPointInExternalFullScreenCenterBar(fullScreenAppleMenu))
        
        let fullScreenFileMenu = CGPoint(x: 150.0, y: topY - 10.0)
        XCTAssertFalse(geom.isPointInExternalFullScreenCenterBar(fullScreenFileMenu))
        
        // 3. 全屏下让位原生系统托盘：右侧时间/WiFi (x: midX + 120 ... maxX) 严格不命中，绝不遮挡系统时钟
        let fullScreenClock = CGPoint(x: 2500.0, y: topY - 10.0)
        XCTAssertFalse(geom.isPointInExternalFullScreenCenterBar(fullScreenClock))
        
        let fullScreenControlCenter = CGPoint(x: 2400.0, y: topY - 10.0)
        XCTAssertFalse(geom.isPointInExternalFullScreenCenterBar(fullScreenControlCenter))
        
        // 4. 超出已滑出原生菜单栏高度的区域 (Y < topY - statusBarHeight) 不命中
        let belowFullScreenMenu = CGPoint(x: midX, y: topY - 30.0)
        XCTAssertFalse(geom.isPointInExternalFullScreenCenterBar(belowFullScreenMenu))
    }
    
    // MARK: - 0 溢出硬门禁与防抖定时器生命周期验证
    
    func testZeroOverflowHardGateSilence() {
        let monitor = MouseMonitor.shared
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let topY = screen.frame.maxY
        let midX = screen.frame.midX
        
        // 当 0 溢出时，即使光标持续碰触中央热区，也严格保持定时器未激活
        monitor.simulateMouseMove(at: CGPoint(x: midX, y: topY - 1.0))
        // 默认屏幕没有模拟溢出时 overflowCount 为 0
        let targetSnapshot = MenuBarSyncCoordinator.shared.effectiveSnapshot(for: screen.displayID)
        if targetSnapshot == nil || targetSnapshot?.overflowCount == 0 {
            XCTAssertFalse(monitor.isExternalDwellTimerActive)
        }
        
        // 移出屏幕范围时，定时器自动清理
        monitor.simulateMouseMove(at: CGPoint(x: -100, y: -100))
        XCTAssertFalse(monitor.isExternalDwellTimerActive)
    }
    
    // MARK: - Ticket #48: 点击外部即时收起 (Dismiss on Click Outside) 与穿透断言
    
    func testDismissOnClickOutside() {
        let stateMachine = IslandStateMachine.shared
        let monitor = MouseMonitor.shared
        
        // 1. 触发展开态 (5 个溢出项)
        stateMachine.triggerExpand(overflowCount: 5)
        XCTAssertTrue(stateMachine.currentState.isExpanded)
        
        let geom = IslandWindowCoordinator.shared.currentPanelGeometry
        let screenRect = geom.interactiveScreenRect(isExpanded: true, overflowCount: 5)
        
        // 2. 点击在展开区域内部（包含 4pt 容差 padding）：不收起
        let insidePoint = CGPoint(x: screenRect.midX, y: screenRect.midY)
        monitor.simulateClick(at: insidePoint)
        XCTAssertTrue(stateMachine.currentState.isExpanded, "点击展开区域内部不应触发展开态收起")
        
        // 3. 点击在展开区域外部（如下方 100pt 处）：即时驱动收起
        let outsidePoint = CGPoint(x: screenRect.midX, y: screenRect.minY - 100.0)
        monitor.simulateClick(at: outsidePoint)
        XCTAssertFalse(stateMachine.currentState.isExpanded, "点击展开区域外部必须立即触发收起 (Dismiss on Click Outside)")
        XCTAssertEqual(stateMachine.currentState, .compact)
    }
    
    func testIslandHostingViewHitTestPassthrough() {
        let hostingView = IslandHostingView(rootView: IslandRootView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 84)
        
        let stateMachine = IslandStateMachine.shared
        
        // 1. 未展开且外接平直屏场景下，hitTest 必须严格返回 nil（100% 物理直通）
        let extGeom = NotchGeometry(
            displayID: 99,
            displayName: "Mock Flat",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 1.0,
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056),
            physicalNotchRect: .zero,
            compactBounds: .zero,
            extendedBounds: CGRect(x: 600, y: 996, width: 720, height: 84),
            statusBarHeight: 24
        )
        
        let flatCollapsedBounds = extGeom.interactiveBounds(in: hostingView.bounds, isExpanded: false, overflowCount: 5)
        XCTAssertEqual(flatCollapsedBounds, .zero, "平直外接屏收起态交互边界必须归零")
        
        // 2. 展开态下，内容区有效，空白区直通
        stateMachine.triggerExpand(overflowCount: 5)
        let expandedBounds = IslandWindowCoordinator.shared.currentPanelGeometry.interactiveBounds(
            in: hostingView.bounds,
            isExpanded: true,
            overflowCount: 5
        )
        XCTAssertTrue(expandedBounds.width > 0 && expandedBounds.height > 0)
        
        // 清理状态
        stateMachine.triggerCollapse()
    }
    
    func testViewportLeasingSmoothReturnOnCollapse() {
        let coordinator = IslandWindowCoordinator.shared
        let stateMachine = IslandStateMachine.shared
        coordinator.start()
        
        // 验证初始常态未借调
        let primary = ScreenManager.shared.primaryGeometry
        XCTAssertFalse(coordinator.isLeasedToExternal)
        XCTAssertEqual(coordinator.currentPanelGeometry.displayID, primary.displayID)
        
        // 展开与收起周期验证
        stateMachine.triggerExpand(overflowCount: 3)
        XCTAssertTrue(stateMachine.currentState.isExpanded)
        
        // 收起
        stateMachine.triggerCollapse()
        XCTAssertFalse(stateMachine.currentState.isExpanded)
        XCTAssertEqual(stateMachine.currentState, .compact)
    }
}

