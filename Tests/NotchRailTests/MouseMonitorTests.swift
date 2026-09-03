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
        
        // 1. 顶边缘 3.0pt 默认阈值判定（Y >= 1114）
        let touchTop = CGPoint(x: 300, y: 1116)
        XCTAssertTrue(geom.isPointInTopEdgeHotZone(touchTop))
        
        let touchTop1pt = CGPoint(x: 300, y: 1115.5)
        XCTAssertTrue(geom.isPointInTopEdgeHotZone(touchTop1pt))
        
        let touchTop3pt = CGPoint(x: 300, y: 1114)
        XCTAssertTrue(geom.isPointInTopEdgeHotZone(touchTop3pt))
        
        // 2. 距离顶部大于 3.0pt 判定（Y = 1113 < 1114）
        let below3pt = CGPoint(x: 300, y: 1113)
        XCTAssertFalse(geom.isPointInTopEdgeHotZone(below3pt))
        
        // 3. 严格防误触：距离顶部大于 3.0pt（例如 Y=1100 < 1114）即使在刘海中下部水平区间亦不误唤醒
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
}
