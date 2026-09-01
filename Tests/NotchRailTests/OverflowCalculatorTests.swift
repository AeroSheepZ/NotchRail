import Foundation
import CoreGraphics
@testable import NotchRailKit

final class OverflowCalculatorTests: XCTestCase {
    
    var mockGeometry: NotchGeometry!
    
    override func setUp() {
        super.setUp()
        // 模拟一台 1512x982 的 MacBook Pro 14寸屏幕，刘海在中间 (x: 676, width: 160, maxX: 836)
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 948)
        let notchRect = CGRect(x: 676, y: 948, width: 160, height: 34)
        
        mockGeometry = NotchGeometry(
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
    }
    
    func testItemsToTheRightOfNotchAreVisible() {
        let wifi = MenuBarItem(
            processIdentifier: 101,
            bundleIdentifier: "com.apple.controlcenter",
            title: "WiFi",
            nativeFrame: CGRect(x: 1460, y: 955, width: 30, height: 24)
        )
        let battery = MenuBarItem(
            processIdentifier: 101,
            bundleIdentifier: "com.apple.controlcenter",
            title: "Battery",
            nativeFrame: CGRect(x: 1410, y: 955, width: 40, height: 24)
        )
        
        let snapshot = OverflowCalculator.resolve(items: [wifi, battery], geometry: mockGeometry)
        
        XCTAssertEqual(snapshot.visibleItems.count, 2)
        XCTAssertEqual(snapshot.overflowItems.count, 0)
        XCTAssertEqual(snapshot.overflowCount, 0)
        XCTAssertEqual(snapshot.visibleItems[0].displayMode, .nativeVisible)
        XCTAssertEqual(snapshot.visibleItems[1].displayMode, .nativeVisible)
    }
    
    func testItemsIntersectingOrLeftOfNotchAreOverflowed() {
        let raycast = MenuBarItem(
            processIdentifier: 202,
            bundleIdentifier: "com.raycast.macos",
            title: "Raycast",
            nativeFrame: CGRect(x: 820, y: 955, width: 28, height: 24)
        )
        let dropbox = MenuBarItem(
            processIdentifier: 303,
            bundleIdentifier: "com.dropbox.client",
            title: "Dropbox",
            nativeFrame: CGRect(x: 750, y: 955, width: 28, height: 24)
        )
        let slack = MenuBarItem(
            processIdentifier: 404,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            title: "Slack",
            nativeFrame: CGRect(x: 600, y: 955, width: 28, height: 24)
        )
        
        let snapshot = OverflowCalculator.resolve(items: [raycast, dropbox, slack], geometry: mockGeometry)
        
        XCTAssertEqual(snapshot.visibleItems.count, 0)
        XCTAssertEqual(snapshot.overflowItems.count, 3)
        XCTAssertEqual(snapshot.overflowCount, 3)
        XCTAssertEqual(snapshot.overflowItems[0].displayMode, .overflowed)
        XCTAssertEqual(snapshot.overflowItems[1].displayMode, .overflowed)
        XCTAssertEqual(snapshot.overflowItems[2].displayMode, .overflowed)
    }
    
    func testIgnoredBundleIDsAreFiltered() {
        let testItem = MenuBarItem(
            processIdentifier: 505,
            bundleIdentifier: "com.hidden.item",
            title: "Hidden",
            nativeFrame: CGRect(x: 700, y: 955, width: 30, height: 24)
        )
        
        let snapshot = OverflowCalculator.resolve(
            items: [testItem],
            geometry: mockGeometry,
            ignoredBundleIDs: ["com.hidden.item"]
        )
        
        XCTAssertEqual(snapshot.overflowItems.count, 0)
        XCTAssertEqual(snapshot.overflowCount, 0)
        XCTAssertEqual(snapshot.visibleItems.count, 0)
        XCTAssertEqual(snapshot.allItems.first?.displayMode, .ignored)
    }
    
    func testNotchBoundaryPrecision() {
        let exactBorderItem = MenuBarItem(
            processIdentifier: 601,
            bundleIdentifier: "com.border.exact",
            title: "BorderExact",
            nativeFrame: CGRect(x: 836, y: 955, width: 30, height: 24)
        )
        let justInsideNotchItem = MenuBarItem(
            processIdentifier: 602,
            bundleIdentifier: "com.border.inside",
            title: "BorderInside",
            nativeFrame: CGRect(x: 835.5, y: 955, width: 30, height: 24)
        )
        let borderSnapshot = OverflowCalculator.resolve(items: [exactBorderItem, justInsideNotchItem], geometry: mockGeometry)
        XCTAssertEqual(borderSnapshot.visibleItems.count, 1)
        XCTAssertEqual(borderSnapshot.overflowItems.count, 1)
        XCTAssertEqual(borderSnapshot.overflowCount, 1)
        XCTAssertEqual(borderSnapshot.visibleItems.first?.title, "BorderExact")
        XCTAssertEqual(borderSnapshot.overflowItems.first?.title, "BorderInside")
    }
    
    func testEmptyItemsList() {
        let emptySnapshot = OverflowCalculator.resolve(items: [], geometry: mockGeometry)
        XCTAssertEqual(emptySnapshot.allItems.count, 0)
        XCTAssertEqual(emptySnapshot.overflowItems.count, 0)
        XCTAssertEqual(emptySnapshot.overflowCount, 0)
        XCTAssertEqual(emptySnapshot.visibleItems.count, 0)
    }
}
