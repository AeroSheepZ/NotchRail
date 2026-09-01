import Foundation
import CoreGraphics
import AppKit
@testable import NotchRailKit

@MainActor
final class ScreenManagerTests: XCTestCase {
    
    func testVirtualNotchGeometryCalculation() {
        let extScreenFrame = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        let extVisibleFrame = CGRect(x: 0, y: 0, width: 3840, height: 2136)
        let extNotchRect = CGRect(x: (3840 - 160) / 2, y: 2160 - 34, width: 160, height: 34)
        
        let extGeometry = NotchGeometry(
            displayID: 2,
            displayName: "External 4K Display",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 2.0,
            screenFrame: extScreenFrame,
            visibleFrame: extVisibleFrame,
            safeAreaInsets: NSEdgeInsets(),
            physicalNotchRect: extNotchRect,
            compactBounds: CGRect(x: 1786, y: 2160 - 34, width: 240, height: 34),
            extendedBounds: CGRect(x: (3840 - 720) / 2, y: 2160 - 84, width: 720, height: 84),
            statusBarHeight: 24
        )
        
        XCTAssertFalse(extGeometry.hasPhysicalNotch)
        XCTAssertEqual(extGeometry.physicalNotchRect.origin.x, 1840)
        XCTAssertEqual(extGeometry.compactBounds.origin.x, 1786)
        
        // 动态展开宽度测试
        XCTAssertEqual(extGeometry.dynamicExtendedBounds(for: 0).width, 360)
        XCTAssertEqual(extGeometry.dynamicExtendedBounds(for: 3).width, 248)
        XCTAssertEqual(extGeometry.dynamicExtendedBounds(for: 10).width, 500)
    }
}
