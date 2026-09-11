import Foundation
@testable import NotchRailKit

@MainActor
final class PreferenceStoreTests: XCTestCase {
    
    func testPreferenceStorePersistenceAndDefaults() {
        let suiteName = "com.notchrail.test.suite.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        
        let store = PreferenceStore(userDefaults: defaults)
        XCTAssertEqual(store.preferences.triggerMode, .hoverAndClick)
        XCTAssertEqual(store.preferences.externalDisplayMode, .followFocusedScreen)
        XCTAssertTrue(store.preferences.autoCollapseOnClick)
        XCTAssertTrue(store.preferences.enableHapticFeedback)
        XCTAssertFalse(store.preferences.hideWhenNoOverflow)
        XCTAssertTrue(store.preferences.showMenuBarIcon)
        XCTAssertEqual(store.preferences.hoverExpandDelayMs, 120.0)
        XCTAssertEqual(store.preferences.collapseDelayMs, 300.0)
        
        // 更新并验证
        store.update { prefs in
            prefs.triggerMode = .click
            prefs.externalDisplayMode = .mainScreenOnly
            prefs.hoverExpandDelayMs = 160.0
        }
        XCTAssertEqual(store.preferences.triggerMode, .click)
        XCTAssertEqual(store.preferences.externalDisplayMode, .mainScreenOnly)
        XCTAssertEqual(store.preferences.hoverExpandDelayMs, 160.0)
        
        // 重载并验证持久化
        let reloadedStore = PreferenceStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.preferences.triggerMode, .click)
        XCTAssertEqual(reloadedStore.preferences.externalDisplayMode, .mainScreenOnly)
        XCTAssertEqual(reloadedStore.preferences.hoverExpandDelayMs, 160.0)
    }
    
    func testBackwardCompatibleJSONDecoding() throws {
        // 模拟 v0.0.1 仅含有部分字段的旧版 JSON
        let legacyJSON = """
        {
            "hoverExpandDelayMs": 100.0,
            "collapseDelayMs": 250.0,
            "launchAtLogin": true
        }
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacyJSON)
        XCTAssertEqual(decoded.hoverExpandDelayMs, 100.0)
        XCTAssertEqual(decoded.collapseDelayMs, 250.0)
        XCTAssertTrue(decoded.launchAtLogin)
        // 验证自动补充的安全默认值
        XCTAssertEqual(decoded.triggerMode, .hoverAndClick)
        XCTAssertEqual(decoded.externalDisplayMode, .followFocusedScreen)
        XCTAssertTrue(decoded.autoCollapseOnClick)
        XCTAssertTrue(decoded.enableHapticFeedback)
        XCTAssertFalse(decoded.hideWhenNoOverflow)
        XCTAssertTrue(decoded.showMenuBarIcon)
    }
    
    func testResetToDefaults() {
        let suiteName = "com.notchrail.test.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        
        let store = PreferenceStore(userDefaults: defaults)
        store.update { prefs in
            prefs.triggerMode = .click
            prefs.externalDisplayMode = .disabled
            prefs.hoverExpandDelayMs = 250.0
        }
        
        XCTAssertEqual(store.preferences.triggerMode, .click)
        XCTAssertEqual(store.preferences.hoverExpandDelayMs, 250.0)
        
        store.resetToDefaults()
        
        XCTAssertEqual(store.preferences.triggerMode, .hoverAndClick)
        XCTAssertEqual(store.preferences.externalDisplayMode, .followFocusedScreen)
        XCTAssertEqual(store.preferences.hoverExpandDelayMs, IslandTheme.Timing.HOVER_EXPAND_DELAY * 1000.0)
        XCTAssertEqual(store.preferences.collapseDelayMs, IslandTheme.Timing.COLLAPSE_DELAY * 1000.0)
    }
    
    func testCustomItemOrderManagement() {
        let suiteName = "com.notchrail.test.order.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        
        let store = PreferenceStore(userDefaults: defaults)
        XCTAssertTrue(store.preferences.customItemOrder.isEmpty)
        
        // 1. 设置自定义排序
        store.setCustomItemOrder(["com.app.first", "com.app.second", "com.app.third"])
        XCTAssertEqual(store.preferences.customItemOrder, ["com.app.first", "com.app.second", "com.app.third"])
        
        // 2. 重新排序
        store.setCustomItemOrder(["com.app.third", "com.app.first", "com.app.second"])
        XCTAssertEqual(store.preferences.customItemOrder, ["com.app.third", "com.app.first", "com.app.second"])
        
        // 3. 重置自定义排序
        store.resetCustomItemOrder()
        XCTAssertTrue(store.preferences.customItemOrder.isEmpty)
        
        // 4. 持久化重载验证
        store.setCustomItemOrder(["com.app.x", "com.app.y"])
        let reloadedStore = PreferenceStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.preferences.customItemOrder, ["com.app.x", "com.app.y"])
    }
}
