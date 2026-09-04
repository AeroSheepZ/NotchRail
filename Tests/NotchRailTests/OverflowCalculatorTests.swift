import Foundation
import CoreGraphics
import AppKit
@testable import NotchRailKit

final class OverflowCalculatorTests: XCTestCase {
    
    var mockBuiltInGeometry: NotchGeometry!
    var mockFlatGeometry: NotchGeometry!
    
    override func setUp() {
        super.setUp()
        // 1. 模拟一台 1512x982 的 MacBook Pro 14寸物理刘海屏 (x: 676, width: 160, maxX: 836)
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 948)
        let notchRect = CGRect(x: 676, y: 948, width: 160, height: 34)
        
        mockBuiltInGeometry = NotchGeometry(
            displayID: 1,
            displayName: "Mock Built-in Retina",
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
        
        // 2. 模拟一台 2560x1440 外接平直大屏 (真实零刘海，消除虚拟锚点)
        let flatScreenFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let flatVisibleFrame = CGRect(x: 0, y: 0, width: 2560, height: 1416)
        mockFlatGeometry = NotchGeometry(
            displayID: 2,
            displayName: "Mock External Flat 2.5K",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 1.0,
            screenFrame: flatScreenFrame,
            visibleFrame: flatVisibleFrame,
            safeAreaInsets: NSEdgeInsets(),
            physicalNotchRect: .zero,
            compactBounds: .zero,
            extendedBounds: CGRect(x: (2560 - 720) / 2, y: 1440 - 84, width: 720, height: 84),
            statusBarHeight: 24,
            appMenuRightEdge: 400.0
        )
    }
    
    // MARK: - 场景 1: 物理刘海屏保持 24pt 容差与标准溢出基准不变
    func testPhysicalNotchDisplayBaseline() {
        // notchRightEdge = 836.0, collisionBoundary = 836 + 24 = 860.0
        let wifi = MenuBarItem(
            processIdentifier: 101,
            bundleIdentifier: "com.apple.controlcenter",
            title: "WiFi",
            nativeFrame: CGRect(x: 1460, y: 955, width: 30, height: 24)
        )
        let borderExact = MenuBarItem(
            processIdentifier: 102,
            bundleIdentifier: "com.border.exact",
            title: "BorderExact",
            nativeFrame: CGRect(x: 860, y: 955, width: 30, height: 24)
        )
        let borderInside = MenuBarItem(
            processIdentifier: 103,
            bundleIdentifier: "com.border.inside",
            title: "BorderInside",
            nativeFrame: CGRect(x: 859.5, y: 955, width: 30, height: 24)
        )
        let slack = MenuBarItem(
            processIdentifier: 104,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            title: "Slack",
            nativeFrame: CGRect(x: 600, y: 955, width: 28, height: 24)
        )
        
        let snapshot = OverflowCalculator.resolve(
            items: [wifi, borderExact, borderInside, slack],
            geometry: mockBuiltInGeometry
        )
        
        XCTAssertEqual(snapshot.visibleItems.count, 2)
        XCTAssertEqual(snapshot.overflowItems.count, 2)
        XCTAssertEqual(snapshot.overflowCount, 2)
        XCTAssertEqual(snapshot.visibleItems[0].title, "WiFi")
        XCTAssertEqual(snapshot.visibleItems[1].title, "BorderExact")
        XCTAssertEqual(snapshot.overflowItems[0].title, "BorderInside")
        XCTAssertEqual(snapshot.overflowItems[1].title, "Slack")
        XCTAssertEqual(snapshot.visibleItems[0].displayMode, .nativeVisible)
        XCTAssertEqual(snapshot.visibleItems[1].displayMode, .nativeVisible)
        XCTAssertEqual(snapshot.overflowItems[0].displayMode, .overflowed)
        XCTAssertEqual(snapshot.overflowItems[1].displayMode, .overflowed)
    }
    
    // MARK: - 场景 2: 外接平直大屏空间充裕（消除幽灵溢出）
    func testFlatDisplayWideOpenSpaceNoGhostOverflow() {
        // appMenuRightEdge = 400.0, collisionBoundary = 400 + 12 = 412.0
        // 图标跨过屏幕中点 (2560/2 = 1280pt)，例如在 1200pt, 1800pt, 2500pt
        let itemCrossCenter = MenuBarItem(
            processIdentifier: 201,
            bundleIdentifier: "com.test.crosscenter",
            title: "CrossCenter",
            nativeFrame: CGRect(x: 1200, y: 1410, width: 30, height: 24)
        )
        let itemMid = MenuBarItem(
            processIdentifier: 202,
            bundleIdentifier: "com.test.mid",
            title: "MidItem",
            nativeFrame: CGRect(x: 1800, y: 1410, width: 30, height: 24)
        )
        let itemRight = MenuBarItem(
            processIdentifier: 203,
            bundleIdentifier: "com.test.right",
            title: "RightItem",
            nativeFrame: CGRect(x: 2500, y: 1410, width: 40, height: 24)
        )
        
        let snapshot = OverflowCalculator.resolve(
            items: [itemCrossCenter, itemMid, itemRight],
            geometry: mockFlatGeometry
        )
        
        // 彻底消除假刘海导致的幽灵溢出：所有项均在 412pt 右侧且在屏幕内，0 项溢出
        XCTAssertEqual(snapshot.overflowItems.count, 0)
        XCTAssertEqual(snapshot.overflowCount, 0)
        XCTAssertEqual(snapshot.visibleItems.count, 3)
        XCTAssertEqual(snapshot.visibleItems[0].displayMode, .nativeVisible)
        XCTAssertEqual(snapshot.visibleItems[1].displayMode, .nativeVisible)
        XCTAssertEqual(snapshot.visibleItems[2].displayMode, .nativeVisible)
    }
    
    // MARK: - 场景 3: 外接平直屏长菜单碰撞（如 Xcode 菜单延伸至 1100pt）
    func testFlatDisplayXcodeMenuRealCollision() {
        let xcodeGeometry = NotchGeometry(
            displayID: 2,
            displayName: "Mock External Flat 2.5K",
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
            appMenuRightEdge: 1100.0 // 前台 Xcode 长应用菜单达 1100pt
        )
        // collisionBoundary = 1100.0 + 12.0 = 1112.0
        let itemSafeRight = MenuBarItem(
            processIdentifier: 301,
            bundleIdentifier: "com.test.safe",
            title: "SafeRight",
            nativeFrame: CGRect(x: 1800, y: 1410, width: 30, height: 24)
        )
        let itemJustClear = MenuBarItem(
            processIdentifier: 302,
            bundleIdentifier: "com.test.justclear",
            title: "JustClear",
            nativeFrame: CGRect(x: 1112, y: 1410, width: 30, height: 24)
        )
        let itemInSafetyMargin = MenuBarItem(
            processIdentifier: 303,
            bundleIdentifier: "com.test.margin",
            title: "InSafetyMargin",
            nativeFrame: CGRect(x: 1105, y: 1410, width: 30, height: 24)
        )
        let itemCoveredByMenu = MenuBarItem(
            processIdentifier: 304,
            bundleIdentifier: "com.test.covered",
            title: "CoveredByMenu",
            nativeFrame: CGRect(x: 1050, y: 1410, width: 30, height: 24)
        )
        
        let snapshot = OverflowCalculator.resolve(
            items: [itemSafeRight, itemJustClear, itemInSafetyMargin, itemCoveredByMenu],
            geometry: xcodeGeometry
        )
        
        XCTAssertEqual(snapshot.visibleItems.count, 2)
        XCTAssertEqual(snapshot.overflowItems.count, 2)
        XCTAssertEqual(snapshot.overflowCount, 2)
        XCTAssertEqual(snapshot.visibleItems[0].title, "SafeRight")
        XCTAssertEqual(snapshot.visibleItems[1].title, "JustClear")
        XCTAssertEqual(snapshot.overflowItems[0].title, "InSafetyMargin")
        XCTAssertEqual(snapshot.overflowItems[1].title, "CoveredByMenu")
        XCTAssertEqual(snapshot.visibleItems[0].displayMode, .nativeVisible)
        XCTAssertEqual(snapshot.visibleItems[1].displayMode, .nativeVisible)
        XCTAssertEqual(snapshot.overflowItems[0].displayMode, .overflowed)
        XCTAssertEqual(snapshot.overflowItems[1].displayMode, .overflowed)
    }
    
    // MARK: - 场景 4: 屏幕边界越界项判定
    func testOutOfBoundsItems() {
        // screenMaxX = 1512, screenMinX = 0, tolerance = 5.0
        let rightOutOfBounds = MenuBarItem(
            processIdentifier: 401,
            bundleIdentifier: "com.test.rightout",
            title: "RightOutOfBounds",
            nativeFrame: CGRect(x: 1510, y: 955, width: 30, height: 24) // maxX = 1540 > 1517
        )
        let leftOutOfBounds = MenuBarItem(
            processIdentifier: 402,
            bundleIdentifier: "com.test.leftout",
            title: "LeftOutOfBounds",
            nativeFrame: CGRect(x: -50, y: 955, width: 40, height: 24) // maxX = -10 < 0
        )
        let inBoundsNormal = MenuBarItem(
            processIdentifier: 403,
            bundleIdentifier: "com.test.inbounds",
            title: "InBoundsNormal",
            nativeFrame: CGRect(x: 1400, y: 955, width: 30, height: 24)
        )
        
        let snapshot = OverflowCalculator.resolve(
            items: [rightOutOfBounds, leftOutOfBounds, inBoundsNormal],
            geometry: mockBuiltInGeometry
        )
        
        XCTAssertEqual(snapshot.overflowItems.count, 2)
        XCTAssertEqual(snapshot.visibleItems.count, 1)
        XCTAssertEqual(snapshot.overflowCount, 2)
        XCTAssertEqual(snapshot.overflowItems[0].displayMode, .overflowed)
        XCTAssertEqual(snapshot.overflowItems[1].displayMode, .overflowed)
        XCTAssertEqual(snapshot.visibleItems[0].displayMode, .nativeVisible)
    }
    
    // MARK: - 场景 5: 黑名单项判定
    func testIgnoredBundleIDs() {
        let hiddenItem1 = MenuBarItem(
            processIdentifier: 501,
            bundleIdentifier: "com.hidden.one",
            title: "Hidden1",
            nativeFrame: CGRect(x: 1400, y: 955, width: 30, height: 24)
        )
        let hiddenItem2 = MenuBarItem(
            processIdentifier: 502,
            bundleIdentifier: "com.hidden.two",
            title: "Hidden2",
            nativeFrame: CGRect(x: 700, y: 955, width: 30, height: 24)
        )
        let normalItem = MenuBarItem(
            processIdentifier: 503,
            bundleIdentifier: "com.normal.item",
            title: "Normal",
            nativeFrame: CGRect(x: 1450, y: 955, width: 30, height: 24)
        )
        
        let snapshot = OverflowCalculator.resolve(
            items: [hiddenItem1, hiddenItem2, normalItem],
            geometry: mockBuiltInGeometry,
            ignoredBundleIDs: ["com.hidden.one", "com.hidden.two"]
        )
        
        XCTAssertEqual(snapshot.overflowItems.count, 0)
        XCTAssertEqual(snapshot.visibleItems.count, 1)
        XCTAssertEqual(snapshot.visibleItems.first?.title, "Normal")
        
        let ignoredItems = snapshot.allItems.filter { $0.displayMode == .ignored }
        XCTAssertEqual(ignoredItems.count, 2)
        XCTAssertEqual(ignoredItems[0].displayMode, .ignored)
        XCTAssertEqual(ignoredItems[1].displayMode, .ignored)
    }
    
    // MARK: - 边界辅助用例: 空列表稳健性
    func testEmptyItemsList() {
        let emptySnapshot = OverflowCalculator.resolve(items: [], geometry: mockBuiltInGeometry)
        XCTAssertEqual(emptySnapshot.allItems.count, 0)
        XCTAssertEqual(emptySnapshot.overflowItems.count, 0)
        XCTAssertEqual(emptySnapshot.overflowCount, 0)
        XCTAssertEqual(emptySnapshot.visibleItems.count, 0)
    }
    
    /// 执行本套件全部 5 大场景自动化测试（供 SpikeRunner 与本地测试入口直接调度）
    public static func runAllTests() {
        let suite = OverflowCalculatorTests()
        
        suite.setUp()
        suite.testPhysicalNotchDisplayBaseline()
        suite.tearDown()
        
        suite.setUp()
        suite.testFlatDisplayWideOpenSpaceNoGhostOverflow()
        suite.tearDown()
        
        suite.setUp()
        suite.testFlatDisplayXcodeMenuRealCollision()
        suite.tearDown()
        
        suite.setUp()
        suite.testOutOfBoundsItems()
        suite.tearDown()
        
        suite.setUp()
        suite.testIgnoredBundleIDs()
        suite.tearDown()
        
        suite.setUp()
        suite.testEmptyItemsList()
        suite.tearDown()
    }
}

