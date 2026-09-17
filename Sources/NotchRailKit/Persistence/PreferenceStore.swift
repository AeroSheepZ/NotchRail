import Foundation
import Combine
import CoreGraphics

extension Notification.Name {
    public static let preferencesChanged = Notification.Name("NotchRail.PreferencesChanged")
}

/// 负责用户偏好持久化存取与响应式广播（单一职责数据层）
@MainActor
public final class PreferenceStore: ObservableObject {
    public static let shared = PreferenceStore()
    
    private static let STORAGE_KEY = "com.notchrail.NotchRail.preferences"
    private let userDefaults: UserDefaults
    
    @Published public var preferences: UserPreferences {
        didSet {
            save()
            NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
        }
    }
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.STORAGE_KEY) {
            do {
                self.preferences = try JSONDecoder().decode(UserPreferences.self, from: data)
            } catch {
                print("⚠️ [NotchRail] UserPreferences 反序列化失败，恢复默认值: \(error)")
                self.preferences = UserPreferences()
            }
        } else {
            self.preferences = UserPreferences()
        }
    }
    
    /// 保存偏好至 UserDefaults
    private func save() {
        do {
            let encoded = try JSONEncoder().encode(preferences)
            userDefaults.set(encoded, forKey: Self.STORAGE_KEY)
        } catch {
            print("❌ [NotchRail] UserPreferences 序列化持久化失败: \(error)")
        }
    }
    
    /// 更新偏好并自动持久化
    public func update(_ transform: (inout UserPreferences) -> Void) {
        var current = preferences
        transform(&current)
        self.preferences = current
    }
    
    /// 重置为出厂推荐默认设置
    public func resetToDefaults() {
        self.preferences = UserPreferences()
    }
    
    // MARK: - 自定义排序管理（按屏隔离与可选跨屏同步，ADR 0014）
    
    /// 获取指定屏幕的自定义排序列表（未指定则取主屏基准屏）
    public func customItemOrder(for displayID: CGDirectDisplayID? = nil) -> [String] {
        let targetID = displayID ?? ScreenManager.shared.primaryGeometry.displayID
        let key = ScreenManager.persistentKey(for: targetID)
        return preferences.itemOrder(for: key)
    }
    
    /// 更新指定屏幕的自定义排序列表
    public func setCustomItemOrder(_ order: [String], for displayID: CGDirectDisplayID? = nil) {
        let targetID = displayID ?? ScreenManager.shared.primaryGeometry.displayID
        let key = ScreenManager.persistentKey(for: targetID)
        update { prefs in
            prefs.setItemOrder(order, for: key)
        }
    }
    
    /// 重置指定屏幕的自定义排序（恢复按原生扫描与几何物理空间排布）
    public func resetCustomItemOrder(for displayID: CGDirectDisplayID? = nil) {
        let targetID = displayID ?? ScreenManager.shared.primaryGeometry.displayID
        let key = ScreenManager.persistentKey(for: targetID)
        update { prefs in
            prefs.resetItemOrder(for: key)
        }
    }

    /// 切换是否在所有屏幕间同步排序
    public func setSyncItemOrderAcrossDisplays(_ sync: Bool) {
        update { prefs in
            prefs.syncItemOrderAcrossDisplays = sync
        }
    }
}
