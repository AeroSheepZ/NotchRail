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
    private nonisolated static let MAX_CACHE_SIZE = 200
    /// 拉黑前最大失败次数
    private nonisolated static let MAX_FAILURES_BEFORE_BLACKLIST = 3
    /// 黑名单冷却时长（秒）
    private nonisolated static let BLACKLIST_COOLDOWN_SECONDS: TimeInterval = 30
    /// macOS 实际可能出现的 backing scale
    private nonisolated static let PLAUSIBLE_BACKING_SCALES: [CGFloat] = [1, 2, 3]
    /// scale 匹配容差
    private nonisolated static let SCALE_TOLERANCE: CGFloat = 0.05

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

    /// 批量解析菜单栏项图标（内存已有项 0ms 瞬间直出，后台通过 isVisuallyEqual 动态增量比对实时刷新三方数值）
    public func resolveIcons(for items: [MenuBarItem]) async {
        guard !items.isEmpty else { return }

        // 1. 已有内存缓存的项先置为 loaded 状态（0ms 瞬间直出，彻底杜绝空白占位）
        for item in items {
            let key = item.iconCacheKey
            if let cached = cache[key] {
                iconStates[key] = .loaded(cached.nsImage)
            }
        }

        // 2. 未授权屏幕录制时直接返回
        guard CGPreflightScreenCaptureAccess() else { return }

        // 3. 获取失败冷却黑名单并执行后台捕获管线，由 apply 内部的 isVisuallyEqual 像素比对动态更新三方网速/天气/时钟数值
        let blacklisted = currentlyBlacklistedKeys()
        let result = await Self.capturePipeline(items, blacklistedKeys: blacklisted)
        apply(result, to: items)
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
                if iconStates[key] == nil || iconStates[key] == .pending {
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
        where failed.failureCount >= Self.MAX_FAILURES_BEFORE_BLACKLIST
            && now.timeIntervalSince(failed.lastFailureTime) < Self.BLACKLIST_COOLDOWN_SECONDS {
            keys.insert(key)
        }
        return keys
    }

    private func recordFailure(for key: String) {
        let existing = failedCaptures[key]
        let count = (existing?.failureCount ?? 0) + 1
        failedCaptures[key] = FailedCapture(failureCount: count, lastFailureTime: Date())

        // 顺带清理过期失败记录
        let cutoff = Date().addingTimeInterval(-Self.BLACKLIST_COOLDOWN_SECONDS)
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
        guard cache.count > Self.MAX_CACHE_SIZE else { return }
        evict(count: cache.count - Self.MAX_CACHE_SIZE)
    }

    /// 统一按 LRU 顺序驱逐指定数量的缓存项并回退状态
    private func evict(count: Int) {
        var evicted = 0
        while evicted < count, !accessOrder.isEmpty {
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
        evict(count: (cache.count + 1) / 2)
    }

    // MARK: - 捕获管线（后台线程执行）

    /// 纯函数式捕获管线：直接逐窗高精度截图 → scale 校验 → 自动裁剪
    ///
    /// nonisolated + async → 自动运行在全局并发执行器，不阻塞 MainActor
    private nonisolated static func capturePipeline(
        _ items: [MenuBarItem],
        blacklistedKeys: Set<String>
    ) async -> CaptureResult {
        var result = CaptureResult()

        // 1. 收集有效窗口 ID（过滤处于冷却中的黑名单键）
        var entries: [(item: MenuBarItem, bounds: CGRect)] = []
        for item in items {
            guard item.windowID != 0 else { continue }
            guard !blacklistedKeys.contains(item.iconCacheKey) else { continue }
            let bounds = Bridging.frame(for: item.windowID) ?? item.nativeFrame
            entries.append((item, bounds))
        }

        guard !entries.isEmpty else {
            return result
        }

        // 2. 逐窗进行原生真实菜单栏截图
        for entry in entries {
            guard let image = Bridging.captureWindow(entry.item.windowID),
                  image.width > 0, image.height > 0,
                  !image.isFullyTransparent
            else {
                result.failedKeys.insert(entry.item.iconCacheKey)
                continue
            }
            
            // 自动裁剪透明边距并归一化倍率
            let trimmed = image.trimmingTransparentPixels() ?? image
            let rawScale = CGFloat(image.width) / max(1, entry.bounds.width)
            let scale = validatedScale(rawScale) ?? max(1.0, rawScale.rounded())
            result.images[entry.item.iconCacheKey] = CapturedIcon(cgImage: trimmed, scale: scale)
        }

        return result
    }

    /// 校验反推的捕获倍率是否落在真实 backing scale 上
    private nonisolated static func validatedScale(_ derived: CGFloat) -> CGFloat? {
        guard derived > 0.5 && derived < 4.5 else { return nil }
        let rounded = derived.rounded()
        if Self.PLAUSIBLE_BACKING_SCALES.contains(rounded) && abs(derived - rounded) <= 0.35 {
            return rounded
        }
        return Self.PLAUSIBLE_BACKING_SCALES.first { abs(derived - $0) <= 0.35 }
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

// MARK: - CGImage 辅助扩展（跨格式像素分析与自动裁剪）

extension CGImage {
    private static let SRGB_COLOR_SPACE: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// 生成不共享父图像素内存的独立拷贝
    nonisolated func detachedCopy() -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace ?? Self.SRGB_COLOR_SPACE,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// 是否整张图全透明且无任何可见色彩内容（兼容 RGBA 与 XRGB 格式）
    nonisolated var isFullyTransparent: Bool {
        guard width > 0, height > 0 else { return true }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: Self.SRGB_COLOR_SPACE,
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
                let pixelOffset = rowBase + x * bytesPerPixel
                let r = ptr[pixelOffset]
                let g = ptr[pixelOffset + 1]
                let b = ptr[pixelOffset + 2]
                let a = ptr[pixelOffset + 3]
                // 任意通道存在可见内容即非全透明
                if a > 4 && (r > 4 || g > 4 || b > 4) {
                    return false
                }
            }
        }
        return true
    }

    /// 自动裁剪边缘全透明像素
    nonisolated func trimmingTransparentPixels(alphaThreshold: UInt8 = 6) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: Self.SRGB_COLOR_SPACE,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return self }
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        let rowStride = context.bytesPerRow
        
        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var hasVisiblePixel = false
        
        for y in 0..<height {
            let rowBase = y * rowStride
            for x in 0..<width {
                let pixelOffset = rowBase + x * bytesPerPixel
                let r = ptr[pixelOffset]
                let g = ptr[pixelOffset + 1]
                let b = ptr[pixelOffset + 2]
                let a = ptr[pixelOffset + 3]
                
                let isVisible = (a > alphaThreshold) || (r > 15 || g > 15 || b > 15)
                if isVisible {
                    hasVisiblePixel = true
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        
        guard hasVisiblePixel, minX <= maxX, minY <= maxY else {
            return self
        }
        
        // 允许四周保留 1px 微安全边距，避免边缘抗锯齿裁切
        let cropMinX = max(0, minX - 1)
        let cropMinY = max(0, minY - 1)
        let cropMaxX = min(width - 1, maxX + 1)
        let cropMaxY = min(height - 1, maxY + 1)
        
        let cropWidth = cropMaxX - cropMinX + 1
        let cropHeight = cropMaxY - cropMinY + 1
        
        // 若裁切区域与原图几乎相同（相差 <= 2px），直接返回原图
        if cropWidth >= width - 2 && cropHeight >= height - 2 {
            return self
        }
        
        // CGImage.cropping 坐标系与 CGContext 一致（左上角为原点）
        let cropRect = CGRect(x: cropMinX, y: cropMinY, width: cropWidth, height: cropHeight)
        return self.cropping(to: cropRect)?.detachedCopy() ?? self
    }
}
