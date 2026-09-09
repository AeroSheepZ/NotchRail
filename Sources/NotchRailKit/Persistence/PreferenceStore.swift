import Foundation
import Combine

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
    
    // MARK: - 忽略 / 黑名单项管理
    
    /// 检查特定 Bundle ID 或持久化键是否被隐藏
    public func isItemHidden(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return preferences.ignoredBundleIDs.contains(trimmed)
    }
    
    /// 快捷隐藏特定应用（加入黑名单）
    public func hideItem(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        update { prefs in
            if !prefs.ignoredBundleIDs.contains(trimmed) {
                prefs.ignoredBundleIDs.append(trimmed)
            }
        }
    }
    
    /// 取消隐藏特定应用（移出黑名单）
    public func unhideItem(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        update { prefs in
            prefs.ignoredBundleIDs.removeAll { $0 == trimmed }
        }
    }
    
    /// 切换忽略特定 Bundle ID 或键
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
        hideItem(bundleID)
    }
    
    /// 清空所有黑名单忽略应用
    public func clearAllIgnored() {
        update { prefs in
            prefs.ignoredBundleIDs.removeAll()
        }
    }
    
    // MARK: - 自定义排序管理
    
    /// 更新自定义排序列表
    public func setCustomItemOrder(_ order: [String]) {
        update { prefs in
            prefs.customItemOrder = order
        }
    }
    
    /// 重置自定义排序（恢复按原生扫描与几何物理空间排布）
    public func resetCustomItemOrder() {
        update { prefs in
            prefs.customItemOrder.removeAll()
        }
    }
    
    /// 将目标项目置顶（移到最前）
    public func moveItemToTop(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        update { prefs in
            var order = prefs.customItemOrder
            order.removeAll { $0 == trimmed }
            order.insert(trimmed, at: 0)
            prefs.customItemOrder = order
        }
    }
    
    /// 调整两个相邻位置或在列表中移动
    public func moveCustomItem(fromOffsets: IndexSet, toOffset: Int) {
        update { prefs in
            prefs.customItemOrder.move(fromOffsets: fromOffsets, toOffset: toOffset)
        }
    }
}
