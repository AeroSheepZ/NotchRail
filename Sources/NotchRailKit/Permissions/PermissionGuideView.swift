import SwiftUI
import AppKit

/// 权限引导视图：在一个窗口内同时引导「辅助功能（必需）+ 屏幕录制（推荐）」两个权限
public struct PermissionGuideView: View {
    @ObservedObject var permissionManager = PermissionManager.shared
    /// 关闭引导窗口（两个权限都已授权时由协调器调用）
    public var onDismiss: () -> Void
    /// 用户选择跳过屏幕录制（辅助功能已授权时直接进入应用）
    public var onSkipScreenCapture: () -> Void

    public init(
        onDismiss: @escaping () -> Void = {},
        onSkipScreenCapture: @escaping () -> Void = {}
    ) {
        self.onDismiss = onDismiss
        self.onSkipScreenCapture = onSkipScreenCapture
    }

    public var body: some View {
        VStack(spacing: 16) {
            // 标题区
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "hand.raised.square.on.square.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                Text("NotchRail 需要权限")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                Text("授权后灵动岛即可常驻，检测并呈现被刘海遮挡的菜单栏图标。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            // 权限卡片 1：辅助功能（必需）
            permissionCard(
                icon: "hand.raised.square.on.square.fill",
                title: "辅助功能权限",
                requiredTag: "必需",
                desc: "检测菜单栏中被遮挡的图标，并在岛内触发原生菜单。",
                isGranted: permissionManager.isAccessibilityGranted,
                buttonTitle: "打开系统设置",
                action: { permissionManager.openSystemSettings() }
            )

            // 权限卡片 2：屏幕录制（推荐）
            permissionCard(
                icon: "rectangle.inset.filled.and.person.filled",
                title: "屏幕录制权限",
                requiredTag: "推荐",
                desc: "在岛内预览被遮挡图标的真实画面。未授权时自动降级为 App 图标，核心功能不受影响。",
                isGranted: permissionManager.isScreenCaptureGranted,
                buttonTitle: "打开屏幕录制设置",
                action: { permissionManager.openScreenCaptureSettings() }
            )

            // 等待状态
            if !permissionManager.isAccessibilityGranted || !permissionManager.isScreenCaptureGranted {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(permissionManager.isAccessibilityGranted ? "正在等待屏幕录制授权..." : "正在等待系统授权...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            // 按钮操作区
            HStack(spacing: 12) {
                Button(role: .cancel) {
                    NSApp.terminate(nil)
                } label: {
                    Text("退出")
                        .frame(minWidth: 70)
                }
                .controlSize(.large)

                if !permissionManager.isScreenCaptureGranted {
                    Button {
                        onSkipScreenCapture()
                    } label: {
                        Text("跳过屏幕录制")
                            .frame(minWidth: 110)
                    }
                    .controlSize(.large)
                }
            }
        }
        .padding(24)
        .frame(width: 470)
        .onAppear {
            if !permissionManager.isScreenCaptureGranted {
                permissionManager.requestScreenCapturePermission()
            }
        }
    }

    /// 单个权限卡片：状态徽标 + 说明 + 打开设置按钮
    private func permissionCard(
        icon: String,
        title: String,
        requiredTag: String,
        desc: String,
        isGranted: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(isGranted ? .green : .secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Text(requiredTag)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundColor(isGranted ? .green : .orange)
                    .clipShape(Capsule())

                Spacer()

                // 授权状态
                HStack(spacing: 4) {
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(isGranted ? .green : .orange)
                    Text(isGranted ? "已授权" : "未授权")
                        .font(.caption)
                        .foregroundColor(isGranted ? .green : .secondary)
                }
            }

            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)
                .padding(.leading, 26)

            if !isGranted {
                Button(action: action) {
                    Label(buttonTitle, systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.leading, 26)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isGranted ? Color.green.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}
