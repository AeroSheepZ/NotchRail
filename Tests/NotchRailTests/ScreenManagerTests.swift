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
        XCTAssertEqual(extGeometry.dynamicExtendedBounds(for: 3).width, 356)
        XCTAssertEqual(extGeometry.dynamicExtendedBounds(for: 10).width, 500)
    }
    
    func testMultiDisplayOffsetCoordinates() {
        let offsetScreenFrame = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
        let offsetNotchRect = CGRect(x: 2560 + (2560 - 160) / 2, y: 1440 - 34, width: 160, height: 34)
        let offsetGeometry = NotchGeometry(
            displayID: 3,
            displayName: "Secondary Screen",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 1.0,
            screenFrame: offsetScreenFrame,
            visibleFrame: offsetScreenFrame,
            safeAreaInsets: NSEdgeInsets(),
            physicalNotchRect: offsetNotchRect,
            compactBounds: CGRect(x: 2560 + 1200, y: 1404, width: 172, height: 36),
            extendedBounds: CGRect(x: 2560 + 920, y: 1356, width: 720, height: 84),
            statusBarHeight: 24
        )
        
        XCTAssertEqual(offsetGeometry.displayID, 3)
        XCTAssertFalse(offsetGeometry.isBuiltIn)
        XCTAssertEqual(offsetGeometry.physicalNotchRect.minX, 3760)
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
        
        // 副屏普通桌面：保留 24pt 菜单栏高度
        let secondaryDesktop = NotchGeometry(
            displayID: 2,
            displayName: "External 4K Monitor",
            isBuiltIn: false,
            hasPhysicalNotch: false,
            scaleFactor: 2.0,
            screenFrame: CGRect(x: 1728, y: 0, width: 3840, height: 2160),
            visibleFrame: CGRect(x: 1728, y: 0, width: 3840, height: 2136),
            physicalNotchRect: CGRect(x: 1728 + 1840, y: 2126, width: 160, height: 34),
            compactBounds: CGRect(x: 1728 + 1840, y: 2126, width: 160, height: 34),
            extendedBounds: CGRect(x: 1728 + 1560, y: 2076, width: 720, height: 84),
            statusBarHeight: 24,
            isFullScreenSpace: false
        )
        
        XCTAssertTrue(primaryFullScreen.isFullScreenSpace)
        XCTAssertFalse(secondaryDesktop.isFullScreenSpace)
    }
}
