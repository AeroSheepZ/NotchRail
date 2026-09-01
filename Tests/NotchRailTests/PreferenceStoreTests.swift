import Foundation
@testable import NotchRailKit

@MainActor
final class PreferenceStoreTests: XCTestCase {
    
    func testPreferenceStorePersistenceAndDefaults() {
        let suiteName = "com.notchrail.test.suite.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        
        let store = PreferenceStore(userDefaults: defaults)
        XCTAssertEqual(store.preferences.triggerMode, .hover)
        XCTAssertEqual(store.preferences.externalDisplayMode, .followFocusedScreen)
        XCTAssertTrue(store.preferences.autoCollapseOnClick)
        XCTAssertTrue(store.preferences.enableHapticFeedback)
        XCTAssertFalse(store.preferences.hideWhenNoOverflow)
        XCTAssertTrue(store.preferences.showMenuBarIcon)
        XCTAssertEqual(store.preferences.hoverExpandDelayMs, 120.0)
        XCTAssertEqual(store.preferences.collapseDelayMs, 300.0)
        XCTAssertTrue(store.preferences.ignoredBundleIDs.isEmpty)
        
        // 更新并验证
        store.update { prefs in
            prefs.triggerMode = .click
            prefs.externalDisplayMode = .mainScreenOnly
            prefs.hoverExpandDelayMs = 160.0
            prefs.ignoredBundleIDs.append("com.test.bundle")
        }
        XCTAssertEqual(store.preferences.triggerMode, .click)
        XCTAssertEqual(store.preferences.externalDisplayMode, .mainScreenOnly)
        XCTAssertEqual(store.preferences.hoverExpandDelayMs, 160.0)
        
        // 重载并验证持久化
        let reloadedStore = PreferenceStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.preferences.triggerMode, .click)
        XCTAssertEqual(reloadedStore.preferences.externalDisplayMode, .mainScreenOnly)
        XCTAssertEqual(reloadedStore.preferences.hoverExpandDelayMs, 160.0)
        XCTAssertTrue(reloadedStore.preferences.ignoredBundleIDs.contains("com.test.bundle"))
    }
    
    func testBackwardCompatibleJSONDecoding() throws {
        // 模拟 v0.0.1 仅含有部分字段的旧版 JSON
        let legacyJSON = """
        {
            "ignoredBundleIDs": ["com.legacy.app"],
            "hoverExpandDelayMs": 100.0,
            "collapseDelayMs": 250.0,
            "launchAtLogin": true
        }
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacyJSON)
        XCTAssertEqual(decoded.ignoredBundleIDs, ["com.legacy.app"])
        XCTAssertEqual(decoded.hoverExpandDelayMs, 100.0)
        XCTAssertEqual(decoded.collapseDelayMs, 250.0)
        XCTAssertTrue(decoded.launchAtLogin)
        // 验证自动补充的安全默认值
        XCTAssertEqual(decoded.triggerMode, .hover)
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
            prefs.ignoredBundleIDs = ["com.app.one", "com.app.two"]
        }
        
        XCTAssertEqual(store.preferences.triggerMode, .click)
        XCTAssertEqual(store.preferences.ignoredBundleIDs.count, 2)
        
        store.resetToDefaults()
        
        XCTAssertEqual(store.preferences.triggerMode, .hover)
        XCTAssertEqual(store.preferences.externalDisplayMode, .followFocusedScreen)
        XCTAssertTrue(store.preferences.ignoredBundleIDs.isEmpty)
        XCTAssertEqual(store.preferences.hoverExpandDelayMs, IslandTheme.Timing.HOVER_EXPAND_DELAY * 1000.0)
        XCTAssertEqual(store.preferences.collapseDelayMs, IslandTheme.Timing.COLLAPSE_DELAY * 1000.0)
    }
    
    func testBlacklistHelpers() {
        let suiteName = "com.notchrail.test.blacklist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        
        let store = PreferenceStore(userDefaults: defaults)
        store.addIgnored(bundleID: "com.apple.Music")
        XCTAssertTrue(store.preferences.ignoredBundleIDs.contains("com.apple.Music"))
        
        // 重复添加不重复
        store.addIgnored(bundleID: "com.apple.Music")
        XCTAssertEqual(store.preferences.ignoredBundleIDs.filter { $0 == "com.apple.Music" }.count, 1)
        
        // 切换移除
        store.toggleIgnored(bundleID: "com.apple.Music")
        XCTAssertFalse(store.preferences.ignoredBundleIDs.contains("com.apple.Music"))
        
        // 批量添加后清空
        store.addIgnored(bundleID: "com.app.1")
        store.addIgnored(bundleID: "com.app.2")
        XCTAssertEqual(store.preferences.ignoredBundleIDs.count, 2)
        store.clearAllIgnored()
        XCTAssertTrue(store.preferences.ignoredBundleIDs.isEmpty)
    }
}
