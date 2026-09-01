import Foundation
import Combine

extension Notification.Name {
    public static let preferencesChanged = Notification.Name("NotchRail.PreferencesChanged")
}

/// 负责用户偏好持久化存取与响应式广播
@MainActor
public final class PreferenceStore: ObservableObject {
    public static let shared = PreferenceStore()
    
    private let storageKey = "com.notchrail.NotchRail.preferences"
    private let userDefaults: UserDefaults
    
    @Published public var preferences: UserPreferences {
        didSet {
            save()
            applyPreferences(preferences)
            NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
        }
    }
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            self.preferences = decoded
        } else {
            self.preferences = UserPreferences()
        }
        
        applyPreferences(self.preferences)
    }
    
    /// 保存偏好至 UserDefaults
    private func save() {
        if let encoded = try? JSONEncoder().encode(preferences) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
    
    /// 更新偏好并自动持久化
    public func update(_ transform: (inout UserPreferences) -> Void) {
        var current = preferences
        transform(&current)
        self.preferences = current
    }
    
    /// 将配置实时应用到状态机与协调器
    private func applyPreferences(_ prefs: UserPreferences) {
        IslandStateMachine.shared.hoverExpandDelay = prefs.hoverExpandDelayMs / 1000.0
        IslandStateMachine.shared.collapseDelay = prefs.collapseDelayMs / 1000.0
    }
    
    /// 切换忽略特定 Bundle ID
    public func toggleIgnored(bundleID: String) {
        update { prefs in
            if let index = prefs.ignoredBundleIDs.firstIndex(of: bundleID) {
                prefs.ignoredBundleIDs.remove(at: index)
            } else {
                prefs.ignoredBundleIDs.append(bundleID)
            }
        }
        MenuBarSyncCoordinator.shared.scheduleSync(immediate: true)
    }
}
