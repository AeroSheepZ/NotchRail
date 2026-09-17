import Foundation
import CoreGraphics
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
            prefs.externalDisplayMode = .mainScreenOnly
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
    
    /// 历史第三档（原始编码 disabled）必须**显式迁移**为 .mainScreenOnly
    ///
    /// 该档已随 ADR 0015 删除。若只靠 `ExternalDisplayMode(rawValue:)` 兜底，查不到会静默落回
    /// `.followFocusedScreen` —— 那等于把曾选「仅主屏」的用户悄悄切换到多屏独立模式（语义漂移）。
    /// 同时验证：历史 JSON 中已删除的偏好键必须被无害忽略，不得导致解码失败。
    func testLegacyThirdCaseMigratesToMainScreenOnly() throws {
        let legacyJSON = """
        {
            "externalDisplayMode": "disabled",
            "autoCollapseOnClick": false,
            "triggerMode": "hover"
        }
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacyJSON)
        XCTAssertEqual(decoded.externalDisplayMode, .mainScreenOnly)
        XCTAssertEqual(decoded.triggerMode, .hover)
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

    /// 验证多显示器按屏独立分区存储与重置隔离性（ADR 0014 决议 1）
    func testPerDisplayCustomItemOrderIsolation() {
        let suiteName = "com.notchrail.test.multidisplay.order.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        
        let store = PreferenceStore(userDefaults: defaults)
        let display1: CGDirectDisplayID = 1001
        let display2: CGDirectDisplayID = 1002
        
        store.setCustomItemOrder(["com.app.disp1"], for: display1)
        store.setCustomItemOrder(["com.app.disp2"], for: display2)
        
        XCTAssertEqual(store.customItemOrder(for: display1), ["com.app.disp1"])
        XCTAssertEqual(store.customItemOrder(for: display2), ["com.app.disp2"])
        
        // 重置 display1 绝不影响 display2
        store.resetCustomItemOrder(for: display1)
        XCTAssertTrue(store.customItemOrder(for: display1).isEmpty)
        XCTAssertEqual(store.customItemOrder(for: display2), ["com.app.disp2"])
        
        // 持久化重载验证
        let reloadedStore = PreferenceStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.customItemOrder(for: display2), ["com.app.disp2"])
    }

    /// 验证跨屏同步开关生效（ADR 0014 决议 2）
    func testSyncItemOrderAcrossDisplays() {
        let suiteName = "com.notchrail.test.sync.order.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        
        let store = PreferenceStore(userDefaults: defaults)
        let display1: CGDirectDisplayID = 2001
        let display2: CGDirectDisplayID = 2002
        
        store.setSyncItemOrderAcrossDisplays(true)
        XCTAssertTrue(store.preferences.syncItemOrderAcrossDisplays)
        
        store.setCustomItemOrder(["com.app.synced"], for: display1)
        XCTAssertEqual(store.customItemOrder(for: display1), ["com.app.synced"])
        XCTAssertEqual(store.customItemOrder(for: display2), ["com.app.synced"])
    }

    /// 验证旧版单数组 customItemOrder 向后兼容平滑迁移至主屏/内建屏分区
    func testLegacyCustomItemOrderMigration() throws {
        let legacyJSON = """
        {
            "customItemOrder": ["legacy.app.1", "legacy.app.2"],
            "triggerMode": "click"
        }
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacyJSON)
        XCTAssertEqual(decoded.triggerMode, .click)
        XCTAssertEqual(decoded.customItemOrder, ["legacy.app.1", "legacy.app.2"])
        XCTAssertEqual(decoded.itemOrder(for: "builtin"), ["legacy.app.1", "legacy.app.2"])
        XCTAssertFalse(decoded.syncItemOrderAcrossDisplays)
    }
}

