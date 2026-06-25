import Foundation

// Drives the quantum state transition animation.
//
// Phase advances from 0 (initial state geometry) to π (target state geometry).
// The caller reads `phase`, `stateA`, and `stateB` each frame to regenerate the
// superposition point cloud; this struct only tracks timing state.
struct TransitionController {

    /// Wall-clock duration of the full 0 → π sweep in seconds.
    var transitionDuration: Float = 3.0

    /// States bookending the current transition.
    private(set) var stateA: OrbitalState = .ground
    private(set) var stateB: OrbitalState = .ground

    /// Current superposition phase. 0 = pure stateA density; π = pure stateB density.
    private(set) var phase: Float = 0

    /// True while phase < π.
    private(set) var isTransitioning: Bool = false

    // MARK: -

    /// Start a new transition from `from` to `to`.
    /// If already mid-transition, snaps to the nearest endpoint before restarting.
    mutating func startTransition(from: OrbitalState, to: OrbitalState) {
        stateA = isTransitioning ? cancel() : from
        stateB = to
        phase  = 0
        isTransitioning = true

        // NOTE: E1 selection rules (Δℓ = ±1) produce the most dramatic geometry change
        // because both wavefunctions share significant spatial support. Non-E1 pairs will
        // show weak interference — a fade rather than a geometric transition.
        let dl = abs(to.l - stateA.l)
        if dl != 1 {
            print("TransitionController: Δl = \(dl) ≠ ±1 — non-E1 pair; interference term may be weak.")
        }
    }

    /// Advance the phase by one timestep. Call every frame while `isTransitioning`.
    mutating func update(deltaTime: Float) {
        guard isTransitioning else { return }
        phase += .pi * deltaTime / max(transitionDuration, 0.001)
        if phase >= .pi {
            phase = .pi
            isTransitioning = false
        }
    }

    /// Snap immediately: returns whichever endpoint is closer to the current phase.
    @discardableResult
    mutating func cancel() -> OrbitalState {
        isTransitioning = false
        return phase < .pi / 2 ? stateA : stateB
    }
}
