import Foundation
import AppKit
import Carbon
import Combine

/// 全局热键调度服务（基于 Carbon RegisterEventHotKey，零后台轮询，零能耗）
@MainActor
public final class GlobalHotKeyManager: ObservableObject {
    public static let shared = GlobalHotKeyManager()
    
    /// 热键标识签名: 'NRHK' (NotchRail HotKey)
    private static let HOTKEY_SIGNATURE: OSType = 0x4E52484B
    private static let HOTKEY_ID: UInt32 = 1
    
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false
    
    private var registeredKeyCode: UInt32?
    private var registeredModifiers: UInt32?
    
    private init() {}
    
    /// 启动全局快捷键监听服务并绑定偏好流
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        
        installCarbonEventHandler()
        syncWithPreferences()
        
        // 响应偏好变更，动态热重载快捷键
        NotificationCenter.default.publisher(for: .preferencesChanged)
            .sink { [weak self] _ in
                self?.syncWithPreferences()
            }
            .store(in: &cancellables)
    }
    
    /// 停止全局快捷键监听并注销系统注册
    public func stop() {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        unregisterHotKey()
        removeCarbonEventHandler()
    }
    
    /// 根据当前用户偏好注册或注销快捷键
    public func syncWithPreferences() {
        let prefs = PreferenceStore.shared.preferences
        guard prefs.hotKeyEnabled else {
            unregisterHotKey()
            return
        }
        
        if hotKeyRef != nil,
           registeredKeyCode == prefs.hotKeyCode,
           registeredModifiers == prefs.hotKeyModifiers {
            return
        }
        
        unregisterHotKey()
        registerHotKey(keyCode: prefs.hotKeyCode, modifiers: prefs.hotKeyModifiers)
    }
    
    // MARK: - Carbon 底层事件绑定
    
    private func installCarbonEventHandler() {
        guard eventHandlerRef == nil else { return }
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handler: EventHandlerUPP = { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if status == noErr,
               hotKeyID.signature == GlobalHotKeyManager.HOTKEY_SIGNATURE,
               hotKeyID.id == GlobalHotKeyManager.HOTKEY_ID {
                DispatchQueue.main.async {
                    IslandWindowCoordinator.shared.handleGlobalHotKeyToggle()
                }
            }
            return noErr
        }
        
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        
        if status != noErr {
            print("❌ [NotchRail] Carbon InstallEventHandler 注册失败，状态码: \(status)")
        }
    }
    
    private func removeCarbonEventHandler() {
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
    
    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(
            signature: Self.HOTKEY_SIGNATURE,
            id: Self.HOTKEY_ID
        )
        
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            registeredKeyCode = keyCode
            registeredModifiers = modifiers
        } else {
            registeredKeyCode = nil
            registeredModifiers = nil
            print("⚠️ [NotchRail] 全局热键 RegisterEventHotKey 失败: keyCode=\(keyCode), modifiers=\(modifiers), 错误码: \(status)")
        }
    }
    
    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            registeredKeyCode = nil
            registeredModifiers = nil
        }
    }
}
