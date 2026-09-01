import Foundation
import Combine

extension Notification.Name {
    public static let preferencesChanged = Notification.Name("NotchRail.PreferencesChanged")
}

/// 负责用户偏好持久化存取与响应式广播（单一职责数据层）
@MainActor
public final class PreferenceStore: ObservableObject {
    public static let shared = PreferenceStore()
    
    private let storageKey = "com.notchrail.NotchRail.preferences"
    private let userDefaults: UserDefaults
    
    @Published public var preferences: UserPreferences {
        didSet {
            save()
            NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
        }
    }
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey) {
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
            userDefaults.set(encoded, forKey: storageKey)
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
    
    /// 切换忽略特定 Bundle ID
    public func toggleIgnored(bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        update { prefs in
            if let index = prefs.ignoredBundleIDs.firstIndex(of: trimmed) {
                prefs.ignoredBundleIDs.remove(at: index)
            } else {
                prefs.ignoredBundleIDs.append(trimmed)
            }
        }
    }
    
    /// 手动添加忽略特定 Bundle ID
    public func addIgnored(bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        update { prefs in
            if !prefs.ignoredBundleIDs.contains(trimmed) {
                prefs.ignoredBundleIDs.append(trimmed)
            }
        }
    }
    
    /// 清空所有黑名单忽略应用
    public func clearAllIgnored() {
        update { prefs in
            prefs.ignoredBundleIDs.removeAll()
        }
    }
}
