import Foundation
import CoreGraphics
import AppKit
@testable import NotchRailKit

@MainActor
final class ScreenManagerTests: XCTestCase {
    
    func testFlatDisplayZeroNotchGeometryCalculation() {
        let extScreenFrame = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        let extVisibleFrame = CGRect(x: 0, y: 0, width: 3840, height: 2136)
        
        let extGeometry = NotchGeometry(
            displayID: 2,
            displayName: "External 4K Display",
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
            appMenuRightEdge: 380.0
        )
        
        XCTAssertFalse(extGeometry.hasPhysicalNotch)
        XCTAssertEqual(extGeometry.physicalNotchRect, .zero)
        XCTAssertEqual(extGeometry.compactBounds, .zero)
        XCTAssertEqual(extGeometry.appMenuRightEdge, 380.0)
        
        // 平直屏常态 100% 隐形自洽性：无论溢出多少项，紧凑胶囊边界严格为 .zero
        XCTAssertEqual(extGeometry.dynamicCompactBounds(for: 0), .zero)
        XCTAssertEqual(extGeometry.dynamicCompactBounds(for: 5), .zero)
        XCTAssertEqual(extGeometry.interactiveBounds(in: NSRect(x: 0, y: 0, width: 3840, height: 84), isExpanded: false, overflowCount: 5), .zero)
        
        // 动态展开宽度测试（Floating Shelf 原生悬浮托轨）
        XCTAssertEqual(extGeometry.dynamicExtendedBounds(for: 0).width, 360)
        XCTAssertEqual(extGeometry.dynamicExtendedBounds(for: 3).width, 356)
        XCTAssertEqual(extGeometry.dynamicExtendedBounds(for: 10).width, 500)
    }
    
    func testMultiDisplayOffsetCoordinates() {
        let offsetScreenFrame = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
        let offsetGeometry = NotchGeometry(
            displayID: 3,
            displayName: "Secondary Flat Screen",
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
            appMenuRightEdge: 2560 + 400.0
        )
        
        XCTAssertEqual(offsetGeometry.displayID, 3)
        XCTAssertFalse(offsetGeometry.isBuiltIn)
        XCTAssertFalse(offsetGeometry.hasPhysicalNotch)
        XCTAssertEqual(offsetGeometry.physicalNotchRect, .zero)
        XCTAssertEqual(offsetGeometry.compactBounds, .zero)
        XCTAssertEqual(offsetGeometry.appMenuRightEdge, 2960.0)
    }
    
    func testFullScreenSpaceGeometricDetection() {
        // 1. 标准桌面空间
        let desktopGeometry = NotchGeometry(
            displayID: 1,
            displayName: "Desktop",
            isBuiltIn: true,
            hasPhysicalNotch: true,
            scaleFactor: 2.0,
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1083),
            physicalNotchRect: CGRect(x: 774, y: 1083, width: 180, height: 34),
            compactBounds: CGRect(x: 774, y: 1083, width: 180, height: 34),
            extendedBounds: CGRect(x: 464, y: 1033, width: 800, height: 84),
            statusBarHeight: 34,
            isFullScreenSpace: false
        )
        XCTAssertFalse(desktopGeometry.isFullScreenSpace)
        
        // 2. 全屏空间
        let fullScreenGeometry = NotchGeometry(
            displayID: 1,
            displayName: "FullScreen Space",
            isBuiltIn: true,
            hasPhysicalNotch: true,
            scaleFactor: 2.0,
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            physicalNotchRect: CGRect(x: 774, y: 1083, width: 180, height: 34),
            compactBounds: CGRect(x: 774, y: 1083, width: 180, height: 34),
            extendedBounds: CGRect(x: 464, y: 1033, width: 800, height: 84),
            statusBarHeight: 34,
            isFullScreenSpace: true
        )
        XCTAssertTrue(fullScreenGeometry.isFullScreenSpace)
    }
    
    func testMultiDisplayIndependentFullScreen() {
        // 主屏全屏：Xcode 处于全屏空间
        let primaryFullScreen = NotchGeometry(
            displayID: 1,
            displayName: "MacBook Screen",
            isBuiltIn: true,
            hasPhysicalNotch: true,
            scaleFactor: 2.0,
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            physicalNotchRect: CGRect(x: 774, y: 1083, width: 180, height: 34),
            compactBounds: CGRect(x: 774, y: 1083, width: 180, height: 34),
            extendedBounds: CGRect(x: 464, y: 1033, width: 800, height: 84),
            statusBarHeight: 34,
            isFullScreenSpace: true
        )
        
        // 副屏普通桌面：保留 24pt 菜单栏高度，平直屏幕零刘海
        let secondaryDesktop = NotchGeometry(
            displayID: 2,
            displayName: "External 4K Monitor",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 2.0,
            screenFrame: CGRect(x: 1728, y: 0, width: 3840, height: 2160),
            visibleFrame: CGRect(x: 1728, y: 0, width: 3840, height: 2136),
            physicalNotchRect: .zero,
            compactBounds: .zero,
            extendedBounds: CGRect(x: 1728 + 1560, y: 2076, width: 720, height: 84),
            statusBarHeight: 24,
            isFullScreenSpace: false
        )
        
        XCTAssertTrue(primaryFullScreen.isFullScreenSpace)
        XCTAssertFalse(secondaryDesktop.isFullScreenSpace)
        XCTAssertEqual(secondaryDesktop.physicalNotchRect, .zero)
        XCTAssertEqual(secondaryDesktop.compactBounds, .zero)
    }
    
    func testCalculateGeometryAppMenuRightEdgePassing() {
        // 测试实际屏幕或备用屏幕的几何计算与 appMenuRightEdge 传递契约
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let geomWithEdge = ScreenManager.calculateGeometry(for: screen, appMenuRightEdge: 450.0)
        
        XCTAssertEqual(geomWithEdge.appMenuRightEdge, 450.0)
        
        if !geomWithEdge.hasPhysicalNotch {
            // 平直显示器必须严格断言零刘海与零紧凑边界
            XCTAssertEqual(geomWithEdge.physicalNotchRect, .zero)
            XCTAssertEqual(geomWithEdge.compactBounds, .zero)
        } else {
            // 物理刘海机型必须保持原有刘海物理尺寸
            XCTAssertGreaterThan(geomWithEdge.physicalNotchRect.width, 0)
            XCTAssertGreaterThan(geomWithEdge.physicalNotchRect.height, 0)
        }
        
        // 测试 ScreenManager 实例缓存与更新机制
        let testDisplayID = screen.displayID
        ScreenManager.shared.updateAppMenuRightEdge(520.0, for: testDisplayID)
        let resolved = ScreenManager.shared.resolveGeometry(for: screen)
        XCTAssertEqual(resolved.appMenuRightEdge, 520.0)
        
        // 清理测试状态
        ScreenManager.shared.updateAppMenuRightEdge(nil, for: testDisplayID)
    }
    
    func testFetchFrontmostAppMenuMaxXFallbackContract() async {
        let testBounds = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let maxX = await MenuBarAXResolver.shared.fetchFrontmostAppMenuMaxX(for: testBounds)
        
        // 当前运行测试时，如果前台应用有效，应返回 >= 1920 + 180 或实际项 maxX；
        // 若前台为自身测试进程，返回 nil，均符合安全契约
        if let maxX = maxX {
            XCTAssertGreaterThanOrEqual(maxX, testBounds.minX + 180.0)
        }
    }
    
    func testScreenManagerAppMenuBoundaryAsyncUpdate() async {
        let screens = NSScreen.screens
        guard let flatScreen = screens.first(where: { $0.safeAreaInsets.top == 0 }) ?? screens.first else { return }
        
        let testDisplayID = flatScreen.displayID
        let expectedEdge = flatScreen.frame.minX + 350.0
        
        ScreenManager.shared.updateAppMenuRightEdge(expectedEdge, for: testDisplayID)
        
        // 验证 allGeometries 与 geometry(for:) 原子更新
        let geom = ScreenManager.shared.geometry(for: testDisplayID)
        XCTAssertEqual(geom?.appMenuRightEdge, expectedEdge)
        
        let allMatching = ScreenManager.shared.allGeometries.first(where: { $0.displayID == testDisplayID })
        XCTAssertEqual(allMatching?.appMenuRightEdge, expectedEdge)
        
        // 触发异步更新流程验证无崩溃
        ScreenManager.shared.updateAppMenuBoundariesAsync()
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        // 清理测试状态
        ScreenManager.shared.updateAppMenuRightEdge(nil, for: testDisplayID)
        XCTAssertNil(ScreenManager.shared.geometry(for: testDisplayID)?.appMenuRightEdge)
    }
    
    // MARK: - Ticket #46: 视口借调流转与合盖模式单一真实来源测试
    
    func testViewportLeasingCoordinatorContract() {
        let coordinator = IslandWindowCoordinator.shared
        coordinator.start()
        
        let panelGeom = coordinator.currentPanelGeometry
        XCTAssertGreaterThan(panelGeom.screenFrame.width, 0)
        XCTAssertGreaterThan(panelGeom.screenFrame.height, 0)
        
        // 常态未展开时，确认未借调
        if !IslandStateMachine.shared.currentState.isExpanded {
            XCTAssertFalse(coordinator.isLeasedToExternal)
        }
    }
    
    // MARK: - Ticket #47: 平直浮轨消耳、24pt 圆角与 HUD Hit-Test 穿透测试
    
    func testFloatingShelfStylingAndHitTest() {
        // 1. 浮轨圆角与阴影 Tokens
        XCTAssertEqual(IslandTheme.CornerRadius.SHELF_BOTTOM, 24.0)
        XCTAssertEqual(IslandTheme.Shadow.RADIUS, 16.0)
        XCTAssertEqual(IslandTheme.Shadow.X, 0.0)
        XCTAssertEqual(IslandTheme.Shadow.Y, 8.0)
        
        // 2. 消耳吸顶形状边界验证
        let shelfRect = CGRect(x: 0, y: 0, width: 600, height: 84)
        let flatShape = NotchShape(bottomCornerRadius: 24.0, topEarRadius: 0.0)
        let flatPath = flatShape.path(in: shelfRect)
        let flatBounds = flatPath.boundingRect
        XCTAssertEqual(flatBounds.minX, 0)
        XCTAssertEqual(flatBounds.minY, 0)
        XCTAssertEqual(flatBounds.maxX, 600)
        XCTAssertEqual(flatBounds.maxY, 84)
        
        // 3. 边框轮廓 NotchBorderShape topEarRadius == 0
        let borderShape = NotchBorderShape(bottomCornerRadius: 24.0, topEarRadius: 0.0)
        let borderPath = borderShape.path(in: shelfRect)
        let borderBounds = borderPath.boundingRect
        XCTAssertEqual(borderBounds.minX, 0)
        XCTAssertEqual(borderBounds.minY, 0)
        XCTAssertEqual(borderBounds.maxX, 600)
        
        // 4. 平直屏未展开常态下交互边界为 .zero，展开态下精准认领
        let extGeometry = NotchGeometry(
            displayID: 2,
            displayName: "External 4K Display",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 2.0,
            screenFrame: CGRect(x: 0, y: 0, width: 3840, height: 2160),
            visibleFrame: CGRect(x: 0, y: 0, width: 3840, height: 2136),
            physicalNotchRect: .zero,
            compactBounds: .zero,
            extendedBounds: CGRect(x: (3840 - 720) / 2, y: 2160 - 84, width: 720, height: 84),
            statusBarHeight: 24
        )
        
        let collapsedBounds = extGeometry.interactiveBounds(
            in: NSRect(x: 0, y: 0, width: 3840, height: 84),
            isExpanded: false,
            overflowCount: 5
        )
        XCTAssertEqual(collapsedBounds, .zero)
        
        let expandedBounds = extGeometry.interactiveBounds(
            in: NSRect(x: 0, y: 0, width: 3840, height: 84),
            isExpanded: true,
            overflowCount: 5
        )
        XCTAssertGreaterThan(expandedBounds.width, 0)
        XCTAssertEqual(expandedBounds.height, 84)
    }
}
