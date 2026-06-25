import ARKit
import QuartzCore

@MainActor
@Observable
final class HandTracker {

    struct HandState {
        var thumbTip: SIMD3<Float> = .zero
        var indexTip: SIMD3<Float> = .zero
        var isTracked: Bool = false
        var isPinching: Bool = false

        var pinchPoint: SIMD3<Float> { (thumbTip + indexTip) * 0.5 }
    }

    private(set) var left  = HandState()
    private(set) var right = HandState()

    private let session       = ARKitSession()
    private let handProvider  = HandTrackingProvider()
    private let worldProvider = WorldTrackingProvider()

    static let pinchThreshold: Float = 0.015  // 15 mm — tighter to avoid near-pinch false positives

    var activePinching: Bool { left.isPinching || right.isPinching }

    /// True when at least one hand anchor is currently tracked by ARKit.
    /// Distinguishes a genuine unpinch (hand visible, fingers open) from a
    /// tracking drop (hand lost from cameras — e.g. moving too fast).
    var isAnyHandTracked: Bool { left.isTracked || right.isTracked }

    var activePinchPoint: SIMD3<Float>? {
        if right.isPinching { return right.pinchPoint }
        if left.isPinching  { return left.pinchPoint }
        return nil
    }

    /// Current head (device) transform in world space.
    /// Returns nil when the world tracking provider is not yet running (Simulator or startup).
    var deviceTransform: simd_float4x4? {
        guard worldProvider.state == .running else { return nil }
        return worldProvider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?.originFromAnchorTransform
    }

    func run() async {
        guard HandTrackingProvider.isSupported else {
            print("HandTracker: hand tracking not supported on this device")
            return
        }
        do {
            try await session.run([handProvider, worldProvider])
            for await update in handProvider.anchorUpdates {
                apply(update.anchor)
            }
        } catch {
            print("HandTracker: \(error)")
        }
    }

    private func apply(_ anchor: HandAnchor) {
        guard anchor.isTracked, let skel = anchor.handSkeleton else {
            switch anchor.chirality {
            case .left:  left.isTracked = false;  left.isPinching  = false
            case .right: right.isTracked = false; right.isPinching = false
            }
            return
        }

        let thumbJ = skel.joint(.thumbTip)
        let indexJ = skel.joint(.indexFingerTip)
        guard thumbJ.isTracked && indexJ.isTracked else { return }

        let base     = anchor.originFromAnchorTransform
        let thumbPos = col3(base * thumbJ.anchorFromJointTransform)
        let indexPos = col3(base * indexJ.anchorFromJointTransform)
        let dist     = simd_distance(thumbPos, indexPos)

        var s = HandState()
        s.thumbTip   = thumbPos
        s.indexTip   = indexPos
        s.isTracked  = true
        s.isPinching = dist < HandTracker.pinchThreshold

        switch anchor.chirality {
        case .left:  left  = s
        case .right: right = s
        }
    }

    private func col3(_ m: simd_float4x4) -> SIMD3<Float> {
        SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }
}
