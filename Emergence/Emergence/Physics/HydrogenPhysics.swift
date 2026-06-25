import Foundation

// CODATA-2018 physical constants and hydrogen atom physics.
// All energies in eV, wavelengths in nm, times in seconds.
enum HydrogenPhysics {

    // MARK: - Constants

    static let hcEvNm    = 1239.841984  // h·c (eV·nm)
    static let rydbergEv = 13.605693    // ionization energy of ground state
    static let nMax      = 6            // highest bound level modeled
    static let absorptionToleranceEv = 0.08  // resonance match window (eV)
    static let slowdown  = 1.17e8       // display is ~1.17×10⁸× slower than reality

    static let orbitalLetter: [Int: String] = [0:"s", 1:"p", 2:"d", 3:"f", 4:"g", 5:"h"]

    // MARK: - Energy levels

    /// E_n = -RYDBERG_EV / n²  (eV, negative)
    static func energyLevel(_ n: Int) -> Double {
        -rydbergEv / Double(n * n)
    }

    /// Absorption transition energy n_lo → n_hi (positive eV)
    static func transitionEnergy(nLo: Int, nHi: Int) -> Double {
        energyLevel(nHi) - energyLevel(nLo)
    }

    /// Photon wavelength (nm) for transition between levels
    static func transitionWavelength(nLo: Int, nHi: Int) -> Double {
        hcEvNm / transitionEnergy(nLo: nLo, nHi: nHi)
    }

    /// Ionization energy from level n (energy to free electron, positive eV)
    static func ionizationEnergy(_ n: Int) -> Double {
        -energyLevel(n)
    }

    // MARK: - Selection rules

    /// Electric-dipole (E1) selection rule: Δℓ = ±1, |Δm| ≤ 1
    static func dipoleAllowed(l1: Int, m1: Int, l2: Int, m2: Int) -> Bool {
        abs(l2 - l1) == 1 && abs(m2 - m1) <= 1
    }

    /// All (ℓ, m) substates available at principal level n (n² total)
    static func subStates(_ n: Int) -> [(l: Int, m: Int)] {
        var states: [(l: Int, m: Int)] = []
        for l in 0..<n {
            for m in -l...l {
                states.append((l: l, m: m))
            }
        }
        return states
    }

    // MARK: - Lifetimes & time dilation

    /// Sample exponential dwell time in display-seconds for excited level n.
    /// τ(n) = 0.2 ns · n³, scaled by SLOWDOWN.
    static func sampleDwellSeconds(_ n: Int) -> Double {
        let mean = (0.2 * pow(Double(n), 3) * 1e-9) * slowdown
        let u = max(1e-6, Double.random(in: 0...1))
        return min(mean * 4.0, -log(u) * mean)
    }

    /// Whether a photon of energy photonEv would ionize the atom from level n
    static func ionizes(n: Int, photonEv: Double) -> Bool {
        photonEv >= ionizationEnergy(n)
    }

    // MARK: - Transition targets

    /// All dipole-allowed emission targets from state (n, l, m): returns (n', l', m') with n' < n
    static func emissionTargets(n: Int, l: Int, m: Int) -> [(n: Int, l: Int, m: Int)] {
        var targets: [(n: Int, l: Int, m: Int)] = []
        for nTarget in 1..<n {
            for lTarget in 0..<nTarget {
                guard abs(lTarget - l) == 1 else { continue }
                for mTarget in -lTarget...lTarget {
                    guard abs(mTarget - m) <= 1 else { continue }
                    targets.append((n: nTarget, l: lTarget, m: mTarget))
                }
            }
        }
        return targets
    }

    /// Find a resonant absorption target for photon energy photonEv from state (n, l, m).
    /// Returns a randomly selected allowed upper (n', l', m'), or nil if no resonance.
    static func absorptionMatch(n: Int, l: Int, m: Int, photonEv: Double) -> (n: Int, l: Int, m: Int)? {
        guard n < nMax else { return nil }
        var candidates: [(n: Int, l: Int, m: Int)] = []
        for nHi in (n + 1)...nMax {
            let deltaE = transitionEnergy(nLo: n, nHi: nHi)
            guard abs(deltaE - photonEv) < absorptionToleranceEv else { continue }
            for lHi in 0..<nHi {
                guard abs(lHi - l) == 1 else { continue }
                for mHi in -lHi...lHi {
                    guard abs(mHi - m) <= 1 else { continue }
                    candidates.append((n: nHi, l: lHi, m: mHi))
                }
            }
        }
        return candidates.randomElement()
    }

    // MARK: - Color

    /// Dan Bruton wavelength-to-RGB approximation (380–780 nm), gamma 0.8.
    /// Returns (r, g, b) each in 0...1. UV < 380 → dim violet; IR > 780 → dim red.
    static func wavelengthToRGB(_ nm: Double) -> (r: Double, g: Double, b: Double) {
        var r, g, b: Double

        switch nm {
        case 380..<440:
            r = -(nm - 440) / (440 - 380); g = 0;                         b = 1
        case 440..<490:
            r = 0;                          g = (nm - 440) / (490 - 440); b = 1
        case 490..<510:
            r = 0;                          g = 1;                         b = -(nm - 510) / (510 - 490)
        case 510..<580:
            r = (nm - 510) / (580 - 510);  g = 1;                         b = 0
        case 580..<645:
            r = 1;                          g = -(nm - 645) / (645 - 580); b = 0
        case 645...780:
            r = 1;                          g = 0;                         b = 0
        case ..<380:
            return (r: 0.3, g: 0.0, b: 0.3) // dim violet (UV)
        default:
            return (r: 0.3, g: 0.0, b: 0.0) // dim red (IR)
        }

        // Intensity rolloff at spectral edges
        let factor: Double
        switch nm {
        case 380..<420: factor = 0.3 + 0.7 * (nm - 380) / (420 - 380)
        case 700..<780: factor = 0.3 + 0.7 * (780 - nm) / (780 - 700)
        default:        factor = 1.0
        }

        let gamma = 0.8
        func apply(_ c: Double) -> Double { c == 0 ? 0 : pow(c * factor, gamma) }
        return (r: apply(r), g: apply(g), b: apply(b))
    }
}
