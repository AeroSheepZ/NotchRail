import SwiftUI
import AppKit

/// 全局自定义快捷键录制组件 (macOS 原生 HIG 键帽录制胶囊)
public struct HotKeyRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    var isEnabled: Bool
    
    @State private var isRecording: Bool = false
    @State private var monitor: Any? = nil
    @State private var isHovering: Bool = false
    
    public init(
        keyCode: Binding<UInt32>,
        modifiers: Binding<UInt32>,
        isEnabled: Bool = true
    ) {
        self._keyCode = keyCode
        self._modifiers = modifiers
        self.isEnabled = isEnabled
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // 录制键帽按钮
            Button(action: toggleRecording) {
                HStack(spacing: 6) {
                    if isRecording {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                        Text("请按下快捷键组合...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentColor)
                    } else {
                        Image(systemName: "keyboard")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(isEnabled ? .secondary : Color.secondary.opacity(0.4))
                        
                        Text(HotKeyDisplayHelper.displayString(modifiers: modifiers, keyCode: keyCode))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(isEnabled ? .primary : Color.secondary.opacity(0.4))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(backgroundFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(borderStroke, lineWidth: isRecording ? 1.5 : 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .onHover { hovering in
                isHovering = hovering && isEnabled
            }
            
            // 恢复默认快捷键按钮 (⌥ ~)
            if isEnabled && (keyCode != UserPreferences.DEFAULT_HOTKEY_CODE || modifiers != UserPreferences.DEFAULT_HOTKEY_MODIFIERS) {
                Button(action: resetToDefault) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(
                            Circle()
                                .fill(Color(NSColor.quaternaryLabelColor))
                        )
                }
                .buttonStyle(.plain)
                .help("恢复默认快捷键 (⌥ ~)")
            }
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    // MARK: - 样式辅助
    
    private var backgroundFill: Color {
        if !isEnabled {
            return Color(NSColor.controlBackgroundColor).opacity(0.4)
        }
        if isRecording {
            return Color.accentColor.opacity(0.12)
        }
        if isHovering {
            return Color(NSColor.controlBackgroundColor)
        }
        return Color(NSColor.controlBackgroundColor).opacity(0.7)
    }
    
    private var borderStroke: Color {
        if isRecording {
            return Color.accentColor
        }
        if !isEnabled {
            return Color(NSColor.separatorColor).opacity(0.3)
        }
        if isHovering {
            return Color(NSColor.separatorColor).opacity(0.8)
        }
        return Color(NSColor.separatorColor).opacity(0.4)
    }
    
    // MARK: - 录制交互逻辑
    
    private func toggleRecording() {
        guard isEnabled else { return }
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        stopRecording()
        isRecording = true
        
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 按 Esc 取消录制（具名常量杜绝魔数）
            if UInt32(event.keyCode) == MacVirtualKeyCode.kVK_Escape {
                stopRecording()
                return nil
            }
            
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let carbonMods = HotKeyDisplayHelper.carbonModifiers(from: flags)
            
            // 必须包含至少一个修饰键，且不是单纯修饰键按下
            guard carbonMods != 0 else {
                // 没有修饰键时，拦截普通按键防止打字混乱，但不保存
                NSSound.beep()
                return nil
            }
            
            // 成功捕获按键组合：原子更新，杜绝先更键码再更修饰键引发的中间态注册
            let newKeyCode = UInt32(event.keyCode)
            PreferenceStore.shared.updateHotKey(keyCode: newKeyCode, modifiers: carbonMods)
            self.keyCode = newKeyCode
            self.modifiers = carbonMods
            self.stopRecording()
            
            return nil
        }
    }
    
    private func stopRecording() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
    
    private func resetToDefault() {
        stopRecording()
        PreferenceStore.shared.updateHotKey(
            keyCode: UserPreferences.DEFAULT_HOTKEY_CODE,
            modifiers: UserPreferences.DEFAULT_HOTKEY_MODIFIERS
        )
        keyCode = UserPreferences.DEFAULT_HOTKEY_CODE
        modifiers = UserPreferences.DEFAULT_HOTKEY_MODIFIERS
    }
}
