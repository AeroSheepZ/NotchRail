import Foundation
import AppKit
import CoreGraphics

/// 单个菜单栏图标的渐进解析状态（渲染层据此展示占位 / 真实截图 / 降级占位）
public enum IconState {
    /// 首次捕获进行中 → 渲染层显示 App 图标占位（按窗口宽高比预留位置）
    case pending
    /// 捕获成功（携带按真实倍率归一化的截图）
    case loaded(NSImage)
    /// 捕获失败（黑名单冷却中或彻底失败）→ 渲染层显示弱化占位
    case failed
}

extension IconState: Equatable {
    /// loaded 按图像实例判等（同一 NSImage 即同态），用于状态对比防误发布
    public static func == (lhs: IconState, rhs: IconState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending), (.failed, .failed):
            return true
        case let (.loaded(a), .loaded(b)):
            return a === b
        default:
            return false
        }
    }
}

/// 菜单栏项图标解析器 —— 完整的截图 → 校验 → 缓存 → 发布管线
///
/// 处理链：
/// 1. **合成截图**：一次系统调用截所有窗口，按实时 frame 裁剪（高效，实测 ~5ms/18 项）
/// 2. **scale 校验**：像素宽 / 逻辑宽反推真实捕获倍率，只信任 [1, 2, 3]±0.05，
///    防止混缩放多屏下图标错大错小
/// 3. **逐窗兜底**：合成失败 / 裁剪全透明的项回退到单窗口截图
/// 4. **视觉相等检测**：像素没变的图标不写缓存、不发布 → 不触发 SwiftUI 重渲染（流畅的关键）
/// 5. **失败黑名单**：3 次失败拉黑 30s，成功即重置，停止无效重试
/// 6. **LRU 上限 200 + 内存压力清理**（捕获足够快，无需磁盘持久化）
@MainActor
public final class IconResolver: ObservableObject {
    public static let shared = IconResolver()

    // MARK: - 公开状态

    /// 各菜单栏项的图标状态（按 iconCacheKey 索引，渲染层直接订阅）
    @Published public private(set) var iconStates: [String: IconState] = [:]

    // MARK: - 常量

    /// 内存缓存上限（LRU 驱逐）
    private nonisolated static let maxCacheSize = 200
    /// 拉黑前最大失败次数
    private nonisolated static let maxFailuresBeforeBlacklist = 3
    /// 黑名单冷却时长（秒）
    private nonisolated static let blacklistCooldownSeconds: TimeInterval = 30
    /// macOS 实际可能出现的 backing scale
    private nonisolated static let plausibleBackingScales: [CGFloat] = [1, 2, 3]
    /// scale 匹配容差
    private nonisolated static let scaleTolerance: CGFloat = 0.05

    // MARK: - 内部状态

    /// 捕获成功的图像缓存（iconCacheKey → 带真实倍率的截图）
    private var cache: [String: CapturedIcon] = [:]
    /// LRU 访问顺序（从最旧到最新）
    private var accessOrder: [String] = []
    /// 失败计数（含最后失败时间，用于冷却判定）
    private var failedCaptures: [String: FailedCapture] = [:]
    /// 内存压力监听
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    private struct FailedCapture {
        var failureCount: Int
        var lastFailureTime: Date
    }

    /// 捕获成功的图像（CGImage + 捕获时的真实倍率）
    ///
    /// scale 随图走而非假设屏幕倍率 —— 混缩放多屏下 SCK/CGWindowList
    /// 可能按非预期显示器倍率捕获，错 scale 缓存会导致图标错大错小。
    public struct CapturedIcon {
        public let cgImage: CGImage
        public let scale: CGFloat

        /// 应用 scale 后的逻辑尺寸（pt）
        public var scaledSize: CGSize {
            CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        }

        /// 转成 NSImage（尺寸 = 逻辑尺寸，宽度自适应渲染的关键）
        public var nsImage: NSImage {
            NSImage(cgImage: cgImage, size: scaledSize)
        }

        /// 两个可选图像视觉是否等价：指针相等 → 尺寸相等 → 像素数据相等
        public static func isVisuallyEqual(_ old: CapturedIcon?, _ new: CapturedIcon?) -> Bool {
            switch (old, new) {
            case (nil, nil):
                return true
            case let (old?, new?):
                if old.cgImage === new.cgImage { return true }
                guard old.scale == new.scale,
                      old.cgImage.width == new.cgImage.width,
                      old.cgImage.height == new.cgImage.height
                else { return false }
                guard let oldData = old.cgImage.dataProvider?.data,
                      let newData = new.cgImage.dataProvider?.data
                else { return false }
                return oldData == newData
            default:
                return false
            }
        }
    }

    /// 单次捕获管线的结果（按 persistentKey 索引）
    private struct CaptureResult {
        var images: [String: CapturedIcon] = [:]
        var failedKeys: Set<String> = []
    }

    // MARK: - 初始化

    private init() {
        setupMemoryPressureHandling()
    }

    deinit {
        memoryPressureSource?.cancel()
    }

    // MARK: - 主解析入口

    /// 捕获进行中标记（串行化 WindowServer 捕获，防并发批次互相干扰）
    private var isCapturing = false
    /// 捕获期间收到的新请求（如展开瞬间的快照变化），本轮结束后立即补一轮
    private var pendingRequest: [MenuBarItem]?

    /// 批量解析菜单栏项图标（渐进：先标记 pending → 后台捕获 → 只发布变化项）
    public func resolveIcons(for items: [MenuBarItem]) async {
        guard !items.isEmpty else { return }

        // 1. 首见项先标记 pending（渲染层立刻显示占位，无需等待截图）
        markPendingIfNeeded(for: items)

        // 2. 未授权屏幕录制 → 不捕获（渲染层由外部提示权限）
        guard CGPreflightScreenCaptureAccess() else { return }

        // 3. 已有捕获在进行：暂存请求，本轮结束后补一轮（与 MenuBarSyncCoordinator 同模式）
        guard !isCapturing else {
            pendingRequest = items
            return
        }
        isCapturing = true
        defer { isCapturing = false }

        var currentItems = items
        while true {
            // 黑名单快照：冷却中的项跳过捕获（避免无效系统调用）
            let blacklistedKeys = currentlyBlacklistedKeys()

            // 后台执行捕获管线（nonisolated async 自动离开 MainActor）
            let result = await Self.capturePipeline(currentItems, blacklistedKeys: blacklistedKeys)

            // 只应用视觉变化的项（避免无意义重渲染）
            apply(result, to: currentItems)

            // 补扫暂存的请求（串行执行，保证最终状态属于最新请求）
            if let pending = pendingRequest {
                pendingRequest = nil
                currentItems = pending
            } else {
                break
            }
        }
    }

    /// 兼容旧调用方（Spike 调试）的同步快照式 API
    public func resolveIconsSnapshot(for items: [MenuBarItem]) async -> [UUID: ResolvedIcon] {
        await resolveIcons(for: items)
        var result: [UUID: ResolvedIcon] = [:]
        for item in items {
            switch iconStates[item.iconCacheKey] {
            case .loaded(let image):
                result[item.id] = ResolvedIcon(
                    image: image,
                    sourceType: .screenCapture,
                    label: item.title ?? item.bundleIdentifier ?? "App"
                )
            default:
                break
            }
        }
        return result
    }

    // MARK: - 状态标记

    /// 首见项标记 pending（已有 loaded/failed 状态的项不动，防刷新闪烁）
    private func markPendingIfNeeded(for items: [MenuBarItem]) {
        for item in items where iconStates[item.iconCacheKey] == nil {
            iconStates[item.iconCacheKey] = .pending
        }
    }

    // MARK: - 应用捕获结果

    private func apply(_ result: CaptureResult, to items: [MenuBarItem]) {
        var statesChanged = false

        for item in items {
            let key = item.iconCacheKey
            if let icon = result.images[key] {
                // 视觉相等 → 不更新（不触发重渲染）
                if !CapturedIcon.isVisuallyEqual(cache[key], icon) {
                    cache[key] = icon
                    iconStates[key] = .loaded(icon.nsImage)
                    touchAccessOrder(for: key)
                    statesChanged = true
                }
                // 捕获成功 → 重置失败计数
                failedCaptures.removeValue(forKey: key)
            } else if result.failedKeys.contains(key) {
                recordFailure(for: key)
                if iconStates[key] != .failed {
                    iconStates[key] = .failed
                    statesChanged = true
                }
            }
            // 既无图像也无失败（被黑名单跳过 / 无窗口 bounds）→ 保持原状态
        }

        if statesChanged {
            evictIfNeeded()
        }
    }

    // MARK: - 失败黑名单

    /// 当前处于黑名单冷却中的 iconCacheKey 集合
    private func currentlyBlacklistedKeys() -> Set<String> {
        let now = Date()
        var keys = Set<String>()
        for (key, failed) in failedCaptures
        where failed.failureCount >= Self.maxFailuresBeforeBlacklist
            && now.timeIntervalSince(failed.lastFailureTime) < Self.blacklistCooldownSeconds {
            keys.insert(key)
        }
        return keys
    }

    private func recordFailure(for key: String) {
        let existing = failedCaptures[key]
        let count = (existing?.failureCount ?? 0) + 1
        failedCaptures[key] = FailedCapture(failureCount: count, lastFailureTime: Date())

        // 顺带清理过期失败记录
        let cutoff = Date().addingTimeInterval(-Self.blacklistCooldownSeconds)
        failedCaptures = failedCaptures.filter { $0.value.lastFailureTime > cutoff }
    }

    // MARK: - LRU

    private func touchAccessOrder(for key: String) {
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)
    }

    private func evictIfNeeded() {
        guard cache.count > Self.maxCacheSize else { return }
        let removeCount = cache.count - Self.maxCacheSize
        var evicted = 0
        while evicted < removeCount, !accessOrder.isEmpty {
            let key = accessOrder.removeFirst()
            if cache.removeValue(forKey: key) != nil {
                // 被驱逐项回退 pending（下次需要时重新捕获）
                iconStates[key] = .pending
                evicted += 1
            }
        }
    }

    // MARK: - 内存压力

    private func setupMemoryPressureHandling() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleMemoryPressure()
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressure() {
        guard !cache.isEmpty else { return }
        // 清理较旧的一半缓存（LRU 顺序）
        let removeCount = (cache.count + 1) / 2
        var evicted = 0
        while evicted < removeCount, !accessOrder.isEmpty {
            let key = accessOrder.removeFirst()
            if cache.removeValue(forKey: key) != nil {
                iconStates[key] = .pending
                evicted += 1
            }
        }
    }

    // MARK: - 捕获管线（后台线程执行）

    /// 纯函数式捕获管线：合成截图 → scale 校验 → 裁剪 → 失败项逐窗兜底
    ///
    /// nonisolated + async → 自动运行在全局并发执行器，不阻塞 MainActor
    private nonisolated static func capturePipeline(
        _ items: [MenuBarItem],
        blacklistedKeys: Set<String>
    ) async -> CaptureResult {
        var result = CaptureResult()

        // 1. 收集实时窗口 bounds，过滤退化窗口与黑名单项
        var entries: [(item: MenuBarItem, bounds: CGRect)] = []
        for item in items {
            guard item.windowID != 0,
                  !blacklistedKeys.contains(item.iconCacheKey)
            else { continue }
            guard let bounds = Bridging.frame(for: item.windowID),
                  bounds.width > 0, bounds.height > 0
            else { continue }
            entries.append((item, bounds))
        }

        // 无可捕获窗口：全部记为失败（保持外部可见的失败状态一致性）
        guard !entries.isEmpty else {
            result.failedKeys = Set(items.filter { !blacklistedKeys.contains($0.iconCacheKey) }.map(\.iconCacheKey))
            return result
        }

        // 2. 合成截图（一次系统调用截全部窗口）
        let union = entries.reduce(CGRect.null) { $0.union($1.bounds) }
        let windowIDs = entries.map(\.item.windowID)
        var excluded: [(item: MenuBarItem, bounds: CGRect)] = []

        if let composite = Bridging.captureComposite(windowIDs: windowIDs, screenBounds: union) {
            // 3. 反推真实捕获倍率并校验（只信任真实 backing scale，防错大错小）
            let derivedScale = CGFloat(composite.width) / union.width
            if let scale = validatedScale(derivedScale) {
                // 4. 按窗口 bounds 裁剪出单个图标
                for entry in entries {
                    let cropRect = CGRect(
                        x: (entry.bounds.minX - union.minX) * scale,
                        y: (entry.bounds.minY - union.minY) * scale,
                        width: entry.bounds.width * scale,
                        height: entry.bounds.height * scale
                    )
                    // 裁剪 + 脱离父图内存 + 全透明检测（未授权时系统返回全透明占位图）
                    if let cropped = composite.cropping(to: cropRect)?.detachedCopy(),
                       !cropped.isFullyTransparent {
                        result.images[entry.item.iconCacheKey] = CapturedIcon(cgImage: cropped, scale: scale)
                    } else {
                        excluded.append(entry)
                    }
                }
            } else {
                // scale 不可信（bounds 与图像描述的不是同一状态）→ 全部走逐窗兜底
                excluded = entries
            }
        } else {
            excluded = entries
        }

        // 5. 兜底：逐窗单独截图（合成失败 / 裁剪全透明的项）
        for entry in excluded {
            guard let image = Bridging.captureWindow(entry.item.windowID),
                  !image.isFullyTransparent,
                  let scale = validatedScale(CGFloat(image.width) / entry.bounds.width)
            else {
                result.failedKeys.insert(entry.item.iconCacheKey)
                continue
            }
            result.images[entry.item.iconCacheKey] = CapturedIcon(cgImage: image, scale: scale)
        }

        return result
    }

    /// 校验反推的捕获倍率是否落在真实 backing scale 上
    private nonisolated static func validatedScale(_ derived: CGFloat) -> CGFloat? {
        Self.plausibleBackingScales.first { abs(derived - $0) <= Self.scaleTolerance }
    }

    // MARK: - 调试

    /// 清空内存缓存（偏好设置变更时调用）
    public func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
        failedCaptures.removeAll()
        iconStates.removeAll()
    }

    /// 当前缓存规模（调试用）
    public var cacheSize: Int { cache.count }
}

// MARK: - 旧 API 兼容（Spike 调试路径）

/// 描述图标最终解析结果（兼容旧调用方）
public struct ResolvedIcon: Sendable {
    public let image: NSImage?
    public let sourceType: IconSourceType
    public let label: String

    public init(image: NSImage?, sourceType: IconSourceType, label: String) {
        self.image = image
        self.sourceType = sourceType
        self.label = label
    }
}

/// 图标来源（兼容旧调用方）
public enum IconSourceType: String, Codable, Sendable {
    case screenCapture // 按 windowID 截取窗口真实画面（唯一来源）
}

// MARK: - CGImage 工具

extension CGImage {
    /// 生成不共享父图像素内存的独立拷贝
    ///
    /// `cropping(to:)` 返回的子图共享父合成图的 backing store，
    /// 会把整张合成图的生命周期钉在缓存里；拷贝出小图后父图即可释放。
    nonisolated func detachedCopy() -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// 是否整张图全透明（未授权屏幕录制时系统会返回全透明占位图）
    ///
    /// 通过 CGContext 归一化像素格式后读 alpha 通道，避免不同
    /// 字节序 / alpha 位置导致的误判。
    nonisolated var isFullyTransparent: Bool {
        guard width > 0, height > 0, bitsPerPixel >= 32 else { return false }
        let bytesPerPixel = bitsPerPixel / 8
        // 归一化为 RGBA（premultipliedLast，alpha 在每像素最后一字节）
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return false }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return false }
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        let rowStride = context.bytesPerRow
        for y in 0..<height {
            let rowBase = y * rowStride
            for x in 0..<width {
                if ptr[rowBase + x * bytesPerPixel + 3] > 0 {
                    return false
                }
            }
        }
        return true
    }
}
