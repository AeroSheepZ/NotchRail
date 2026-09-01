import SwiftUI

/// 轻量横向震动物理效果 (Shake Effect)
public struct ShakeEffect: GeometryEffect {
    public var amount: CGFloat = 6
    public var shakesPerUnit: CGFloat = 3
    public var animatableData: CGFloat
    
    public init(shakes: CGFloat, amount: CGFloat = 6, shakesPerUnit: CGFloat = 3) {
        self.animatableData = shakes
        self.amount = amount
        self.shakesPerUnit = shakesPerUnit
    }
    
    public func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
