import SwiftUI
import RealityKit
import RealityKitContent
import ARKit
import UIKit
import Metal

// MARK: - Vertex layout (position + packed BGRA color)

private struct PointVertex {
    var position: SIMD3<Float> = .zero
    var color: UInt32 = 0

    static func pack(r: Float, g: Float, b: Float) -> UInt32 {
        let ri = UInt32(max(0, min(255, r * 255 + 0.5)))
        let gi = UInt32(max(0, min(255, g * 255 + 0.5)))
        let bi = UInt32(max(0, min(255, b * 255 + 0.5)))
        return bi | (gi << 8) | (ri << 16) | 0xFF000000
    }
}

extension PointVertex {
    static var meshDescriptor: LowLevelMesh.Descriptor {
        var desc = LowLevelMesh.Descriptor()
        desc.vertexAttributes = [
            .init(semantic: .position, format: .float3,
                  offset: MemoryLayout<Self>.offset(of: \.position)!),
            .init(semantic: .color, format: .uchar4Normalized_bgra,
                  offset: MemoryLayout<Self>.offset(of: \.color)!)
        ]
        desc.vertexLayouts = [
            .init(bufferIndex: 0, bufferStride: MemoryLayout<Self>.stride)
        ]
        desc.indexType = .uint32
        return desc
    }
}

// MARK: - ImmersiveView

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @State private var rootEntity: Entity?
    @State private var atomContainer: Entity?
    @State private var hitSphereEntity: Entity?
    @State private var pointMesh: LowLevelMesh?
    @State private var rebuildTask:                Task<Void, Never>?
    @State private var transitionTask:             Task<Void, Never>?
    @State private var transitionRebuildInFlight:  Bool = false
    @State private var handTracker  = HandTracker()
    @State private var transition   = TransitionController()

    @State private var activePhotons: [ActivePhoton] = []

    // Atom movement physics
    @State private var atomVelocity: SIMD3<Float> = .zero
    @State private var isCoasting: Bool = false

    // Grab/release pulse: userScale is the scale the user set via two-hand gesture;
    // punchScale is a spring-driven multiplier that briefly deviates from 1.0 on
    // pinch-down (scale up) and pinch-release (scale down), then snaps back.
    @State private var userScale:     Float = ImmersiveView.initialScale
    @State private var punchScale:    Float = 1.0
    @State private var punchVelocity: Float = 0.0

    // Two-hand scale + rotate state — driven by MagnifyGesture / RotateGesture3D.
    @State private var twoHandAnchorScale: Float        = 0
    @State private var twoHandAnchorPos:   SIMD3<Float> = .zero
    @State private var twoHandAnchorMid:   SIMD3<Float> = .zero
    @State private var twoHandAnchorRot:   simd_quatf   = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    @State private var isTwoHandScaling:   Bool         = false

    // One-hand drag state — driven by DragGesture (system predicted positions).
    // Formula: atomPos = dragAtomStart + (currentPinch - dragStartPinch) * dragScale
    @State private var dragScale:            Float = 1.0
    @State private var dragStartPinch:       SIMD3<Float> = .zero
    @State private var dragAtomStart:        SIMD3<Float> = .zero
    @State private var isDraggingAtom:       Bool = false
    @State private var lastPinchPt:          SIMD3<Float> = .zero
    // Current pinch position fed by DragGesture.onChanged — read by update: closure.
    @State private var dragCurrentPinch:     SIMD3<Float>? = nil
    // Pinch position at the moment the gesture first fired — used for movement threshold.
    @State private var dragInitialPinch:     SIMD3<Float>? = nil
    // Timestamp of the previous DragGesture.onChanged call — for velocity EMA.
    @State private var velocityLastTime:     Date = .now
    // Last confirmed pinch world position — SpatialTapGesture.onEnded reads this.
    @State private var lastKnownPinchPos:    SIMD3<Float>? = nil

    static let atomPosition          = SIMD3<Float>(0, 1.2, -1.2)
    static let photonSpeed: Float     = 2.0
    static let moveThreshold: Float   = 0.015  // 1.5 cm hand travel before drag commits
    static let pointCount             = 1_000_000
    static let displayAWorld: Double  = WavefunctionMath.aWorld * 5.0
    static let displayRBox:   Double  = 0.35
    static let initialScale: Float    = 2.0
    // Momentum decay: half-life ≈ 140 ms — smooth glide matching visionOS window feel.
    static let momentumDecay: Float   = 5.0
    // Minimum release speed (m/s) to trigger coasting; below this the atom stops
    // immediately so residual finger-separation motion doesn't nudge it.
    static let coastThreshold: Float  = 0.25
    // Transition point cloud — lower grid resolution keeps per-frame rebuild under ~16 ms.
    // Increase transitionResolution for more detail at the cost of frame rate.
    static let transitionResolution   = 32
    static let transitionPointCount   = 500_000

    // MARK: - Types

    private struct ActivePhoton {
        let entity: ModelEntity
        let startPos: SIMD3<Float>
        let targetPos: SIMD3<Float>
        let energyEv: Double
        let travelTime: Float
        var elapsed: Float = 0
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.animation) { _ in
        RealityView { content in
            let root = Entity()
            content.add(root)
            rootEntity = root

            let container = Entity()
            container.position = Self.atomPosition
            container.scale    = SIMD3<Float>(repeating: Self.initialScale)
            root.addChild(container)
            atomContainer = container

            let hitSphere = Entity()
            // The input target is needed on all devices so that the system routes
            // pinch events to this entity (not the window behind) when the user
            // is gazing at the atom. The sphere uses a constant world-space radius
            // equal to displayRBox (0.35 m) regardless of atom scale: because the
            // hitSphere is a child of the scaled container, we pre-divide by the
            // initial scale so that container.scale × hitSphere.scale = 1 always.
            // Whenever the user two-hand-scales the atom we update hitSphereEntity
            // to maintain this invariant.
            hitSphere.scale = SIMD3<Float>(repeating: 1.0 / Self.initialScale)
            hitSphere.components.set(InputTargetComponent())
            hitSphere.components.set(CollisionComponent(shapes: [.generateSphere(radius: Float(Self.displayRBox))]))
            container.addChild(hitSphere)
            hitSphereEntity = hitSphere

            do {
                let mat = try await ShaderGraphMaterial(
                    named: "/Root/PointCloudMaterial",
                    from: "PointCloudMaterial",
                    in: realityKitContentBundle)

                let N = Self.pointCount
                var desc = PointVertex.meshDescriptor
                desc.vertexCapacity = N
                desc.indexCapacity  = N
                let mesh = try LowLevelMesh(descriptor: desc)

                mesh.withUnsafeMutableIndices { raw in
                    let indices = raw.bindMemory(to: UInt32.self)
                    for i in 0..<N { indices[i] = UInt32(i) }
                }

                pointMesh = mesh

                let resource = try await MeshResource(from: mesh)
                let cloudEntity = ModelEntity(mesh: resource, materials: [mat])
                container.addChild(cloudEntity)

                rebuildPoints(state: appModel.atomState.orbitalState)
            } catch {
                print("ImmersiveView: point cloud setup failed — \(error)")
            }
        } update: { _ in
            // Runs at 90 Hz, compositor-synchronized.
            // DragGesture.onChanged writes dragCurrentPinch; we read it here for smooth
            // display-rate position updates using the system's predicted hand positions.
            if isDraggingAtom, let pt = dragCurrentPinch {
                atomContainer?.position = dragAtomStart + (pt - dragStartPinch) * dragScale
            }
        }
        .task { await handTracker.run() }
        .task {
            var lastTime = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(8))
                let now = Date.now
                let dt  = Float(now.timeIntervalSince(lastTime))
                lastTime = now
                appModel.atomState.update(deltaTime: Double(dt))
                let wasTransitioning = transition.isTransitioning
                transition.update(deltaTime: dt)
                if transition.isTransitioning {
                    rebuildTransitionPoints()
                } else if wasTransitioning {
                    // Transition just completed — cancel any in-flight compute and restore
                    // the full-resolution static render.
                    transitionTask?.cancel()
                    transitionRebuildInFlight = false
                    rebuildPoints(state: appModel.atomState.orbitalState)
                }
                updatePhotons(dt: dt)
                updateHandGestures(now: now, dt: dt)

                // Grab/release pulse — spring-physics scale multiplier.
                // Stiffness 400, damping 22 → ζ ≈ 0.55 (slightly underdamped),
                // ~5 % amplitude, settles in ≈ 0.3 s.
                punchVelocity += (-400 * (punchScale - 1.0) - 22 * punchVelocity) * dt
                punchScale     = max(0.85, min(1.2, punchScale + punchVelocity * dt))
                atomContainer?.scale = SIMD3<Float>(repeating: userScale * punchScale)
            }
        }
        .onChange(of: appModel.atomState.orbitalState) { oldState, newState in
            transition.startTransition(from: oldState, to: newState)
        }
        // SpatialTapGesture: ML-based contact detection matching visionOS window taps.
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { _ in
                    guard appModel.photonFiringEnabled,
                          !isDraggingAtom,
                          !isTwoHandScaling else { return }
                    let origin = lastKnownPinchPos ?? Self.simulatorHandPos
                    firePhoton(from: origin, ev: appModel.atomState.dialedPhotonEv)
                }
        )
        // DragGesture: uses the system's predicted hand positions — the same pipeline
        // as visionOS window dragging.  Predicted positions extrapolate through brief
        // tracking gaps (hand flips, fast motion) so the atom never freezes and snaps.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in onDragChanged(value) }
                .onEnded   { value in onDragEnded(value)   }
        )
        // MagnifyGesture + RotateGesture3D: system two-hand pipeline for scale and
        // rotation — same tracking used for visionOS window resize/rotate gestures.
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in onMagnifyChanged(value) }
                .onEnded   { value in onMagnifyEnded(value)   }
        )
        .simultaneousGesture(
            RotateGesture3D()
                .targetedToAnyEntity()
                .onChanged { value in onRotateChanged(value) }
                .onEnded   { value in onRotateEnded(value)   }
        )
        } // end TimelineView
    }

    static let simulatorHandPos = SIMD3<Float>(0.4, 1.3, 0.0)

    // MARK: - Point cloud rebuild

    private func rebuildPoints(state: OrbitalState) {
        transitionTask?.cancel()
        transitionRebuildInFlight = false
        rebuildTask?.cancel()
        guard let mesh = pointMesh else { return }

        let displayBox = Self.displayBox(for: state)
        let aEff       = Self.effectiveA(for: state.n)
        let count = Self.pointCount

        rebuildTask = Task {
            guard !Task.isCancelled else { return }

            let vertices: [PointVertex] = await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(returning: ImmersiveView.computePoints(
                        state: state, displayBox: displayBox, aEff: aEff, count: count))
                }
            }

            guard !Task.isCancelled else { return }

            mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                vertices.withUnsafeBytes { src in
                    let copyLen = min(raw.count, src.count)
                    raw.copyMemory(from: UnsafeRawBufferPointer(start: src.baseAddress, count: copyLen))
                }
            }

            // Yield after the 16 MB copy so hand-tracking / position updates
            // that were queued on the main actor can run before we commit parts.
            await Task.yield()
            guard !Task.isCancelled else { return }

            let r = Float(displayBox)
            let bounds = BoundingBox(min: [-r, -r, -r], max: [r, r, r])
            mesh.parts.replaceAll([
                LowLevelMesh.Part(
                    indexOffset: 0,
                    indexCount: count,
                    topology: .point,
                    materialIndex: 0,
                    bounds: bounds)
            ])
        }
    }

    private func rebuildTransitionPoints() {
        // Only one transition rebuild in flight at a time — no cancellation.
        // The phase keeps advancing while compute runs; each completed frame
        // captures the phase at the moment it was dispatched, producing a
        // smooth animation at the rate the hardware can sustain (~30–60 fps).
        guard !transitionRebuildInFlight, let mesh = pointMesh else { return }
        transitionRebuildInFlight = true

        let sA         = transition.stateA
        let sB         = transition.stateB
        let phase      = transition.phase
        let displayBox = Self.displayBox(for: sA)   // both always == displayRBox
        let aEffA      = Self.effectiveA(for: sA.n)
        let aEffB      = Self.effectiveA(for: sB.n)
        let count      = Self.transitionPointCount

        transitionTask = Task {
            let vertices: [PointVertex] = await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(returning: ImmersiveView.computeTransitionPoints(
                        stateA: sA, stateB: sB,
                        phase: phase, displayBox: displayBox,
                        aEffA: aEffA, aEffB: aEffB, count: count))
                }
            }

            // Bail if cancelled (static rebuild started) or transition already ended.
            guard !Task.isCancelled, transition.isTransitioning else {
                transitionRebuildInFlight = false
                return
            }

            mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                vertices.withUnsafeBytes { src in
                    let copyLen = min(raw.count, src.count)
                    raw.copyMemory(from: UnsafeRawBufferPointer(start: src.baseAddress, count: copyLen))
                }
            }

            await Task.yield()
            guard !Task.isCancelled, transition.isTransitioning else {
                transitionRebuildInFlight = false
                return
            }

            let r = Float(displayBox)
            mesh.parts.replaceAll([
                LowLevelMesh.Part(
                    indexOffset: 0,
                    indexCount:  count,
                    topology:    .point,
                    materialIndex: 0,
                    bounds: BoundingBox(min: [-r, -r, -r], max: [r, r, r]))
            ])

            transitionRebuildInFlight = false
        }
    }

    private static func displayBox(for state: OrbitalState) -> Double {
        return displayRBox
    }

    /// Bohr radius used for wavefunction evaluation at display scale.
    /// For n ≤ 3 the orbital fits naturally; for n ≥ 4 we shrink aEff so the
    /// outermost lobe (≈ 2n²·a) stays within displayRBox.
    private static func effectiveA(for n: Int) -> Double {
        let maxAllowed = displayRBox / Double(2 * n * n)
        return min(displayAWorld, maxAllowed)
    }

    // MARK: - Point sampling

    private static func computePoints(state: OrbitalState, displayBox: Double, aEff: Double, count: Int) -> [PointVertex] {
        let rBox = displayBox
        let gridN = 128
        let step = rBox * 2.0 / Double(gridN - 1)

        var densities = [Double](repeating: 0, count: gridN * gridN * gridN)
        var maxD = 0.0
        var flatIdx = 0
        for ix in 0..<gridN {
            let x = -rBox + Double(ix) * step
            for iy in 0..<gridN {
                let y = -rBox + Double(iy) * step
                for iz in 0..<gridN {
                    let z = -rBox + Double(iz) * step
                    let d = WavefunctionMath.psi2Real(x: x, y: y, z: z,
                                                       n: state.n, l: state.l, m: state.m,
                                                       a: aEff)
                    densities[flatIdx] = d
                    if d > maxD { maxD = d }
                    flatIdx += 1
                }
            }
        }

        guard maxD > 0 else { return [PointVertex](repeating: PointVertex(), count: count) }

        let threshold = maxD * 0.002
        var cellPos   = [SIMD3<Float>]()
        var cumW      = [Double]()
        var cumSum    = 0.0

        flatIdx = 0
        for ix in 0..<gridN {
            let x = Float(-rBox + Double(ix) * step)
            for iy in 0..<gridN {
                let y = Float(-rBox + Double(iy) * step)
                for iz in 0..<gridN {
                    let z = Float(-rBox + Double(iz) * step)
                    let d = densities[flatIdx]
                    if d >= threshold {
                        cumSum += d / maxD
                        cellPos.append(SIMD3<Float>(x, y, z))
                        cumW.append(cumSum)
                    }
                    flatIdx += 1
                }
            }
        }

        guard !cellPos.isEmpty else { return [PointVertex](repeating: PointVertex(), count: count) }

        var rng    = SystemRandomNumberGenerator()
        var result = [PointVertex](repeating: PointVertex(), count: count)
        let sigma  = Float(step) * 1.2   // Gaussian σ — no hard boundary, cloud fades asymptotically

        for i in 0..<count {
            let target = Double.random(in: 0..<cumSum, using: &rng)
            var lo = 0, hi = cumW.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if cumW[mid] < target { lo = mid + 1 } else { hi = mid }
            }

            let pos = cellPos[lo] + ImmersiveView.gaussianJitter(sigma: sigma, using: &rng)

            let d    = WavefunctionMath.psi2Real(x: Double(pos.x), y: Double(pos.y), z: Double(pos.z),
                                                  n: state.n, l: state.l, m: state.m, a: aEff)
            let norm = min(Float(d / maxD), 1.0)
            let (r, g, b) = fireRGB(t: norm)
            result[i] = PointVertex(position: pos, color: PointVertex.pack(r: r, g: g, b: b))
        }

        return result
    }

    private static func fireRGB(t: Float) -> (Float, Float, Float) {
        switch t {
        case ..<0.20:
            let s = t / 0.20
            return (s * 0.25, 0, s * 0.55)
        case ..<0.45:
            let s = (t - 0.20) / 0.25
            return (0.25 + s * 0.75, 0, 0.55 * (1 - s))
        case ..<0.70:
            let s = (t - 0.45) / 0.25
            return (1.0, s * 0.55, 0)
        case ..<0.88:
            let s = (t - 0.70) / 0.18
            return (1.0, 0.55 + s * 0.40, s * 0.30)
        default:
            let s = (t - 0.88) / 0.12
            return (1.0, 0.95, 0.30 + s * 0.70)
        }
    }

    private static func coolRGB(t: Float) -> (Float, Float, Float) {
        // deep indigo → pale lavender (matches WavefunctionSplatGenerator coolLow/coolHigh)
        return (0.1 + t * 0.6, t * 0.6, 0.5 + t * 0.5)
    }

    // Box-Muller: generates 3 independent N(0, sigma²) offsets.
    // Unlike uniform ±jitter, Gaussian has no hard edge — the cloud boundary
    // fades asymptotically rather than stopping at a cube face.
    private static func gaussianJitter(sigma: Float, using rng: inout SystemRandomNumberGenerator) -> SIMD3<Float> {
        @inline(__always) func bm() -> (Float, Float) {
            let u1 = max(Float.random(in: 0..<1, using: &rng), 1e-7)
            let u2 = Float.random(in: 0..<1, using: &rng)
            let mag = sqrt(-2 * log(u1))
            return (mag * cos(2 * .pi * u2), mag * sin(2 * .pi * u2))
        }
        let (x, y) = bm()
        let (z, _) = bm()
        return SIMD3(x * sigma, y * sigma, z * sigma)
    }

    // MARK: - Transition point sampling

    /// Computes the superposition density |ψ_A + ψ_B·e^(iθ)|² at each grid cell and
    /// samples `count` points from it. Warm colormap for positive interference field,
    /// cool for negative — encodes the quantum phase structure of the two-state superposition.
    private static func computeTransitionPoints(
        stateA: OrbitalState, stateB: OrbitalState,
        phase: Float, displayBox: Double, aEffA: Double, aEffB: Double, count: Int) -> [PointVertex] {

        let rBox  = displayBox
        let gridN = transitionResolution
        let step  = rBox * 2.0 / Double(gridN - 1)
        let cosPh = Double(cos(phase))
        let total = gridN * gridN * gridN

        // Pass 1: evaluate ψ_A and ψ_B at every grid point; find per-field maxima.
        var psiAs   = [Double](repeating: 0, count: total)
        var psiBs   = [Double](repeating: 0, count: total)
        var psiMaxA = 0.0, psiMaxB = 0.0

        var flatIdx = 0
        for ix in 0..<gridN {
            let x = -rBox + Double(ix) * step
            for iy in 0..<gridN {
                let y = -rBox + Double(iy) * step
                for iz in 0..<gridN {
                    let z  = -rBox + Double(iz) * step
                    let pA = WavefunctionMath.psiReal(x: x, y: y, z: z,
                                                       n: stateA.n, l: stateA.l, m: stateA.m,
                                                       a: aEffA)
                    let pB = WavefunctionMath.psiReal(x: x, y: y, z: z,
                                                       n: stateB.n, l: stateB.l, m: stateB.m,
                                                       a: aEffB)
                    psiAs[flatIdx] = pA;  if abs(pA) > psiMaxA { psiMaxA = abs(pA) }
                    psiBs[flatIdx] = pB;  if abs(pB) > psiMaxB { psiMaxB = abs(pB) }
                    flatIdx += 1
                }
            }
        }

        guard psiMaxA > 0 || psiMaxB > 0 else {
            return [PointVertex](repeating: PointVertex(), count: count)
        }
        let normA = psiMaxA > 0 ? psiMaxA : 1.0
        let normB = psiMaxB > 0 ? psiMaxB : 1.0

        // Find superposition density maximum (no wavefunction evals — just array math).
        var densityMax = 0.0
        for i in 0..<total {
            let pA = psiAs[i] / normA
            let pB = psiBs[i] / normB
            let d  = 0.5 * (pA*pA + pB*pB) + pA*pB*cosPh
            if d > densityMax { densityMax = d }
        }
        guard densityMax > 0 else {
            return [PointVertex](repeating: PointVertex(), count: count)
        }

        // Build CDF from above-threshold cells; store normalized density and sign.
        let threshold = 0.002
        var cellPos   = [SIMD3<Float>]();   cellPos.reserveCapacity(total / 8)
        var cellDens  = [Float]()
        var cellSign  = [Float]()
        var cumW      = [Double]()
        var cumSum    = 0.0

        flatIdx = 0
        for ix in 0..<gridN {
            let x = Float(-rBox + Double(ix) * step)
            for iy in 0..<gridN {
                let y = Float(-rBox + Double(iy) * step)
                for iz in 0..<gridN {
                    let z    = Float(-rBox + Double(iz) * step)
                    let pA   = psiAs[flatIdx] / normA
                    let pB   = psiBs[flatIdx] / normB
                    let d    = 0.5 * (pA*pA + pB*pB) + pA*pB*cosPh
                    let norm = d / densityMax
                    if norm >= threshold {
                        cumSum += norm
                        cellPos.append(SIMD3<Float>(x, y, z))
                        cellDens.append(Float(norm))
                        cellSign.append(pA + pB*cosPh >= 0 ? 1 : -1)
                        cumW.append(cumSum)
                    }
                    flatIdx += 1
                }
            }
        }

        guard !cellPos.isEmpty else {
            return [PointVertex](repeating: PointVertex(), count: count)
        }

        var rng    = SystemRandomNumberGenerator()
        var result = [PointVertex](repeating: PointVertex(), count: count)
        let sigma  = Float(step) * 1.2

        for i in 0..<count {
            let target = Double.random(in: 0..<cumSum, using: &rng)
            var lo = 0, hi = cumW.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if cumW[mid] < target { lo = mid + 1 } else { hi = mid }
            }
            let pos = cellPos[lo] + ImmersiveView.gaussianJitter(sigma: sigma, using: &rng)
            let t = cellDens[lo]
            let (r, g, b) = cellSign[lo] > 0 ? fireRGB(t: t) : coolRGB(t: t)
            result[i] = PointVertex(position: pos, color: PointVertex.pack(r: r, g: g, b: b))
        }
        return result
    }

    // MARK: - Hand gesture update (runs every frame)

    private func updateHandGestures(now: Date, dt: Float) {
        guard dt > 0 else { return }

        // ── Coasting (momentum after drag release) ───────────────────────────────
        if isCoasting {
            if isTwoHandScaling || handTracker.activePinching {
                isCoasting   = false
                atomVelocity = .zero
            } else {
                let damping = exp(-Self.momentumDecay * dt)
                atomVelocity *= damping
                if dt > 0, dt < 0.1, let container = atomContainer {
                    container.position += atomVelocity * dt
                }
                if simd_length(atomVelocity) < 0.001 {
                    isCoasting   = false
                    atomVelocity = .zero
                }
            }
        }
    }

    // MARK: - Drag gesture handlers

    /// Called by DragGesture.onChanged.
    ///
    /// Uses `inputDevicePose3D` — the same predicted hand pose the system uses for window
    /// dragging.  The system extrapolates through brief occlusion (hand-orientation flips,
    /// fast motion), so `onChanged` fires continuously with no gaps.  This eliminates the
    /// freeze+snap that occurred when ARKit direct tracking dropped during thumb-over-finger
    /// occlusion.  Falls back to HandTracker on Simulator where `inputDevicePose3D` is nil.
    private func onDragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        guard !isTwoHandScaling else { return }

        // If the hand is visible but clearly open, the user has released — end the drag.
        // We only skip this gate when the hand is occluded (isAnyHandTracked == false),
        // because that's when we want inputDevicePose3D to extrapolate through the gap.
        if handTracker.isAnyHandTracked && !handTracker.activePinching {
            if isDraggingAtom {
                isDraggingAtom   = false
                dragCurrentPinch = nil
                startCoastingIfFast()
            }
            dragInitialPinch = nil
            return
        }

        // Resolve pinch world-space position.
        // `inputDevicePose3D` is in the entity's local coordinate space; convert to scene
        // (world) space so it matches the atom's RealityKit world-space coordinates.
        let pt: SIMD3<Float>
        if let pose = value.inputDevicePose3D {
            let s = value.convert(pose.position, from: .local, to: .scene)
            pt = SIMD3<Float>(Float(s.x), Float(s.y), Float(s.z))
        } else if let hp = handTracker.activePinchPoint {
            pt = hp
        } else {
            return
        }

        lastKnownPinchPos = pt

        if isDraggingAtom {
            let now = Date.now
            let dt  = Float(now.timeIntervalSince(velocityLastTime))
            if dt > 0, dt < 0.1 {
                let rawVel = (pt - lastPinchPt) * dragScale / dt
                atomVelocity = atomVelocity * 0.2 + rawVel * 0.8
            }
            velocityLastTime = now
            lastPinchPt      = pt
            dragCurrentPinch = pt
        } else if let initPt = dragInitialPinch {
            // Settling: wait for moveThreshold before committing to drag.
            if simd_distance(pt, initPt) > Self.moveThreshold {
                let atomPos  = atomContainer?.position ?? Self.atomPosition
                let tf       = handTracker.deviceTransform
                let hp: SIMD3<Float> = tf.map {
                    SIMD3($0.columns.3.x, $0.columns.3.y, $0.columns.3.z)
                } ?? SIMD3(0, 1.5, 0)
                let handDist = simd_length(initPt - hp)
                let atomDist = simd_length(atomPos - hp)
                dragScale        = handDist > 0.001 ? min(atomDist / handDist, 1.3) : 1.0
                dragStartPinch   = initPt
                dragAtomStart    = atomPos
                isDraggingAtom   = true
                lastPinchPt      = pt
                dragCurrentPinch = pt
                atomVelocity     = .zero
                velocityLastTime = Date.now
            }
        } else {
            // First frame — latch start position, cancel coasting, grab pulse.
            isCoasting       = false
            atomVelocity     = .zero
            dragInitialPinch = pt
            lastPinchPt      = pt
            velocityLastTime = Date.now
            punchVelocity   += 1.0
        }
    }

    /// Called by DragGesture.onEnded — ends drag and hands off to coasting.
    private func onDragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        punchVelocity -= 1.0
        if isDraggingAtom {
            isDraggingAtom   = false
            dragCurrentPinch = nil
            startCoastingIfFast()
        } else {
            atomVelocity = .zero
        }
        dragInitialPinch = nil
    }

    // MARK: - Coasting helper

    /// Begins coasting from current `atomVelocity`, capping speed so the atom
    /// never travels farther than a natural release would suggest. Clears velocity
    /// if it's below the coast threshold so incidental finger-separation noise doesn't
    /// nudge the atom after a slow deliberate release.
    private func startCoastingIfFast() {
        let speed = simd_length(atomVelocity)
        guard speed > Self.coastThreshold else { atomVelocity = .zero; return }
        // Cap to 2.5 m/s regardless of dragScale so distant-atom coasting feels
        // proportional rather than flying across the room.
        let cappedSpeed = min(speed, 2.5)
        atomVelocity = atomVelocity * (cappedSpeed / speed)
        isCoasting = true
    }

    // MARK: - Two-hand gesture handlers (MagnifyGesture + RotateGesture3D)

    private func beginTwoHandIfNeeded() {
        guard !isTwoHandScaling else { return }
        isTwoHandScaling   = true
        twoHandAnchorScale = userScale
        twoHandAnchorPos   = atomContainer?.position ?? Self.atomPosition
        twoHandAnchorRot   = atomContainer?.orientation ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        if handTracker.left.isTracked && handTracker.right.isTracked {
            twoHandAnchorMid = (handTracker.left.pinchPoint + handTracker.right.pinchPoint) * 0.5
        }
        isDraggingAtom   = false
        dragCurrentPinch = nil
        dragInitialPinch = nil
        isCoasting       = false
        atomVelocity     = .zero
    }

    private func onMagnifyChanged(_ value: EntityTargetValue<MagnifyGesture.Value>) {
        beginTwoHandIfNeeded()
        let newScale = min(max(twoHandAnchorScale * Float(value.magnification), 0.2), 10.0)
        userScale = newScale
        hitSphereEntity?.scale = SIMD3<Float>(repeating: 1.0 / newScale)
        if handTracker.left.isTracked && handTracker.right.isTracked {
            let mid = (handTracker.left.pinchPoint + handTracker.right.pinchPoint) * 0.5
            atomContainer?.position = twoHandAnchorPos + (mid - twoHandAnchorMid)
        }
        atomContainer?.scale = SIMD3<Float>(repeating: newScale * punchScale)
    }

    private func onMagnifyEnded(_ value: EntityTargetValue<MagnifyGesture.Value>) {
        isTwoHandScaling = false
    }

    private func onRotateChanged(_ value: EntityTargetValue<RotateGesture3D.Value>) {
        beginTwoHandIfNeeded()
        let qd = value.rotation.quaternion
        // RotateGesture3D's X and Z axes are both inverted relative to RealityKit world space;
        // Y (up) is shared and needs no correction.
        let dq = simd_quatf(ix: -Float(qd.imag.x), iy: Float(qd.imag.y),
                            iz: -Float(qd.imag.z), r: Float(qd.real))
        atomContainer?.orientation = dq * twoHandAnchorRot
    }

    private func onRotateEnded(_ value: EntityTargetValue<RotateGesture3D.Value>) {
        isTwoHandScaling = false
    }

    // MARK: - Photon lifecycle

    private func firePhoton(from origin: SIMD3<Float>, ev: Double) {
        guard let root = rootEntity else { return }
        let nm  = HydrogenPhysics.hcEvNm / ev
        let rgb = HydrogenPhysics.wavelengthToRGB(nm)
        let brightness = rgb.r + rgb.g + rgb.b
        let (r, g, b): (Double, Double, Double) = brightness > 0.15
            ? (rgb.r, rgb.g, rgb.b)
            : (0.45, 0.1, 1.0)

        let mat = UnlitMaterial(color: UIColor(red: CGFloat(r), green: CGFloat(g),
                                               blue: CGFloat(b), alpha: 1.0),
                                applyPostProcessToneMap: false)
        let sphere = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.018),
                                 materials: [mat])
        sphere.position = origin
        root.addChild(sphere)

        let targetPos  = atomContainer?.position ?? Self.atomPosition
        let dist       = simd_distance(origin, targetPos)
        let travelTime = max(dist / Self.photonSpeed, 0.05)
        activePhotons.append(ActivePhoton(entity: sphere,
                                          startPos: origin,
                                          targetPos: targetPos,
                                          energyEv: ev,
                                          travelTime: travelTime))
    }

    private func updatePhotons(dt: Float) {
        for i in activePhotons.indices.reversed() {
            activePhotons[i].elapsed += dt
            let t = min(activePhotons[i].elapsed / activePhotons[i].travelTime, 1.0)
            let p = activePhotons[i]
            p.entity.position = p.startPos + (p.targetPos - p.startPos) * t
            if t >= 1.0 {
                _ = appModel.atomState.tryAbsorb(photonEv: p.energyEv)
                p.entity.removeFromParent()
                activePhotons.remove(at: i)
            }
        }
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}
