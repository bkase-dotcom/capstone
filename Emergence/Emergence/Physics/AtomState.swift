import Foundation

// MARK: - Orbital display mode

enum OrbitalDisplayMode {
    case eigenstate   // complex |ψ_nℓm|², azimuthally symmetric
    case realOrbital  // real linear combinations (pₓ, p_y, d_xy, …), includes φ dependence
}

// MARK: - OrbitalState

struct OrbitalState: Equatable {
    let n: Int
    let l: Int
    let m: Int

    static let ground = OrbitalState(n: 1, l: 0, m: 0)

    var label: String {
        let letter = HydrogenPhysics.orbitalLetter[l] ?? "?"
        let mSign  = m >= 0 ? "+\(m)" : "\(m)"
        return "\(n)\(letter) m=\(mSign)"
    }

    var isGroundState: Bool { n == 1 }
}

// MARK: - Emitted photon record

struct EmittedPhoton {
    let wavelengthNm: Double
    let fromN: Int
    let toN: Int
    var color: (r: Double, g: Double, b: Double) {
        HydrogenPhysics.wavelengthToRGB(wavelengthNm)
    }
}

// MARK: - AtomStateMachine

@MainActor
@Observable
final class AtomStateMachine {

    // MARK: Observed state

    private(set) var orbitalState: OrbitalState = .ground
    private(set) var isIonized    = false
    /// When true the atom was set directly from the UI; spontaneous emission is suppressed.
    private(set) var isPinned     = false
    var displayMode: OrbitalDisplayMode = .eigenstate

    /// Real-time elapsed (seconds, real-world scale), accumulated from display time
    private(set) var realTimeElapsed: Double = 0

    /// Photon energy the user has currently dialed (eV)
    var dialedPhotonEv: Double = HydrogenPhysics.transitionEnergy(nLo: 1, nHi: 2)

    /// Record of all spontaneously emitted photons (for spectrometer)
    private(set) var emittedPhotons: [EmittedPhoton] = []

    // MARK: Private timers

    private var dwellRemaining:      Double = 0  // seconds until spontaneous emission
    private var recombinationDelay:  Double = 0  // seconds until recombination after ionization
    private static let recombinationDelayS = 2.0 // fixed visual delay (not a radiative rate)
    // Minimum display-time before spontaneous decay so users can observe each orbital.
    private static let minDwellSeconds     = 20.0

    // MARK: - Update loop (call every frame with wall-clock Δt)

    func update(deltaTime dt: Double) {
        realTimeElapsed += dt / HydrogenPhysics.slowdown

        if isIonized {
            recombinationDelay -= dt
            if recombinationDelay <= 0 { recombine() }
            return
        }

        // Ground state is stable; pinned states don't decay spontaneously.
        guard !orbitalState.isGroundState && !isPinned else { return }

        dwellRemaining -= dt
        if dwellRemaining <= 0 { attemptEmission() }
    }

    // MARK: - Absorption

    /// Try to absorb a photon with energy `photonEv` (eV).
    /// Returns true if absorbed (resonant match or ionization).
    @discardableResult
    func tryAbsorb(photonEv: Double) -> Bool {
        guard !isIonized else { return false }

        if HydrogenPhysics.ionizes(n: orbitalState.n, photonEv: photonEv) {
            ionize(); return true
        }

        guard let target = HydrogenPhysics.absorptionMatch(
            n: orbitalState.n, l: orbitalState.l, m: orbitalState.m,
            photonEv: photonEv) else {
            return false
        }

        isPinned        = false  // photon absorption re-enables natural decay
        orbitalState    = OrbitalState(n: target.n, l: target.l, m: target.m)
        dwellRemaining  = max(Self.minDwellSeconds, HydrogenPhysics.sampleDwellSeconds(target.n))
        return true
    }

    // MARK: - Dialed energy helpers

    /// Nearest available transition energy (eV) from current level, for magnetic snap UI.
    func nearestTransitionEnergy(to ev: Double) -> Double {
        var best     = ev
        var bestDist = Double.infinity

        if orbitalState.n < HydrogenPhysics.nMax {
            for nHi in (orbitalState.n + 1)...HydrogenPhysics.nMax {
                let target = HydrogenPhysics.transitionEnergy(nLo: orbitalState.n, nHi: nHi)
                let dist   = abs(target - ev)
                if dist < bestDist { bestDist = dist; best = target }
            }
        }

        // Also consider ionization edge
        let ionE = HydrogenPhysics.ionizationEnergy(orbitalState.n)
        if abs(ionE - ev) < bestDist { best = ionE }

        return best
    }

    /// All available transition energies from the current level (for energy diagram brackets)
    var availableTransitionEnergies: [(nHi: Int, ev: Double)] {
        guard orbitalState.n < HydrogenPhysics.nMax else { return [] }
        return ((orbitalState.n + 1)...HydrogenPhysics.nMax).map { nHi in
            (nHi: nHi, ev: HydrogenPhysics.transitionEnergy(nLo: orbitalState.n, nHi: nHi))
        }
    }

    /// Whether the dialed energy matches a real transition (green bracket condition)
    var dialedEnergyIsResonant: Bool {
        guard !isIonized else { return false }
        return HydrogenPhysics.absorptionMatch(
            n: orbitalState.n, l: orbitalState.l, m: orbitalState.m,
            photonEv: dialedPhotonEv) != nil
    }

    /// Whether the dialed energy would ionize
    var dialedEnergyIonizes: Bool {
        HydrogenPhysics.ionizes(n: orbitalState.n, photonEv: dialedPhotonEv)
    }

    // MARK: - Density sampling (for volume texture generation)

    /// Un-normalized |ψ|² at world-space point, respecting current display mode.
    func density(atX x: Double, y: Double, z: Double) -> Double {
        let s = orbitalState
        switch displayMode {
        case .eigenstate:
            return WavefunctionMath.psi2(x: x, y: y, z: z,
                                         n: s.n, l: s.l, m: s.m,
                                         a: WavefunctionMath.aWorld)
        case .realOrbital:
            return WavefunctionMath.psi2Real(x: x, y: y, z: z,
                                              n: s.n, l: s.l, m: s.m,
                                              a: WavefunctionMath.aWorld)
        }
    }

    // MARK: - Direct state override (UI control panel)

    /// Bypasses photon absorption and pins the atom in the given state until the next photon hit.
    func forceSetState(_ newState: OrbitalState) {
        isIonized      = false
        isPinned       = true   // suppress spontaneous decay
        orbitalState   = newState
        dwellRemaining = 0
    }

    // MARK: - Reset

    func reset() {
        orbitalState       = .ground
        isIonized          = false
        isPinned           = false
        dwellRemaining     = 0
        recombinationDelay = 0
        realTimeElapsed    = 0
        emittedPhotons     = []
        dialedPhotonEv     = HydrogenPhysics.transitionEnergy(nLo: 1, nHi: 2)
    }

    func clearSpectrometer() {
        emittedPhotons = []
    }

    // MARK: - Private helpers

    private func attemptEmission() {
        let s       = orbitalState
        let targets = HydrogenPhysics.emissionTargets(n: s.n, l: s.l, m: s.m)

        guard let target = targets.randomElement() else {
            // Metastable (e.g., 2s has no E1 decay path) — re-arm with a long pause
            dwellRemaining = 30.0
            return
        }

        let wl = HydrogenPhysics.transitionWavelength(nLo: target.n, nHi: s.n)
        emittedPhotons.append(EmittedPhoton(wavelengthNm: wl, fromN: s.n, toN: target.n))

        orbitalState = OrbitalState(n: target.n, l: target.l, m: target.m)
        if !orbitalState.isGroundState {
            dwellRemaining = max(Self.minDwellSeconds, HydrogenPhysics.sampleDwellSeconds(target.n))
        }
    }

    private func ionize() {
        isIonized          = true
        recombinationDelay = AtomStateMachine.recombinationDelayS
    }

    private func recombine() {
        isIonized      = false
        isPinned       = false
        orbitalState   = .ground
        dwellRemaining = 0
    }
}
