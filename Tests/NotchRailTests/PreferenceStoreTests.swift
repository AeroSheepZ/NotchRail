import Foundation
@testable import NotchRailKit

@MainActor
final class PreferenceStoreTests: XCTestCase {
    
    func testPreferenceStorePersistence() {
        let suiteName = "com.notchrail.test.suite"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        
        let store = PreferenceStore(userDefaults: defaults)
        XCTAssertEqual(store.preferences.hoverExpandDelayMs, 60.0)
        XCTAssertEqual(store.preferences.collapseDelayMs, 220.0)
        XCTAssertTrue(store.preferences.ignoredBundleIDs.isEmpty)
        
        // 更新并验证
        store.update { prefs in
            prefs.hoverExpandDelayMs = 160.0
            prefs.ignoredBundleIDs.append("com.test.bundle")
        }
        XCTAssertEqual(store.preferences.hoverExpandDelayMs, 160.0)
        
        // 重载并验证持久化
        let reloadedStore = PreferenceStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.preferences.hoverExpandDelayMs, 160.0)
        XCTAssertTrue(reloadedStore.preferences.ignoredBundleIDs.contains("com.test.bundle"))
    }
}
