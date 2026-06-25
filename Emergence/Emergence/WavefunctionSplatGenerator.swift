import Foundation
import simd

// Analytically evaluates the hydrogen wavefunction and emits a [Splat] array for
// injection into a Gaussian splat renderer.
//
// No imports of RealityKit or MetalSplatter — stays renderer-agnostic.
// The generator output is a plain [Splat] value; swap the downstream consumer freely.
//
// Phase structure:
//   P0  — STO-3G seeded 1s (3 exact Gaussian primitives; no grid needed)
//   P1+ — Grid sampler for all other orbitals (64³ by default)
struct WavefunctionSplatGenerator {

    // MARK: - Tunable constants

    /// Grid resolution per axis for the n≥2 sampler. 64 → 64³ = 262 144 evals.
    var resolution: Int = 64

    /// Fraction of |ψ|_max below which a voxel is skipped. Lower = more splats, richer outer cloud.
    var threshold: Double = 0.01

    /// Splat scale as a multiple of the grid step. Overlap adjacent voxels for visual continuity.
    var kOverlap: Double = 0.7

    /// Opacity transfer exponent γ: opacity = pow(normalizedMag, γ).
    /// Values < 1 lift the diffuse outer cloud; brief recommends 0.6–0.8.
    var opacityGamma: Float = 0.7

    // Transfer-function ramp endpoints — expose so design can iterate without touching the math.
    var warmLow:  SIMD4<Float> = SIMD4(0.9, 0.3, 0.0, 1)    // deep orange
    var warmHigh: SIMD4<Float> = SIMD4(1.0, 0.95, 0.8, 1)   // near-white
    var coolLow:  SIMD4<Float> = SIMD4(0.1, 0.0, 0.50, 1)   // deep indigo
    var coolHigh: SIMD4<Float> = SIMD4(0.7, 0.6, 1.00, 1)   // pale lavender

    // STO-3G primitive Gaussian exponents (Bohr⁻²) and contraction coefficients for H 1s.
    // Source: Pople, Hehre, Stewart (1969). These are exact basis-set values — do not alter.
    private static let sto3gAlphas: [Double] = [3.4252509, 0.6239137, 0.1688554]
    private static let sto3gCoeffs: [Double] = [0.1543290, 0.5353281, 0.4446345]

    /// Grid resolution per axis for transition generation. Lower than `resolution` to
    /// maintain frame rate during per-frame regeneration. Tune if device cannot hold 60 Hz.
    var transitionResolution: Int = 32

    // MARK: - Entry point

    /// Generate splats for `state`. Runs synchronously — call from a background thread.
    /// Node-count postcondition (§5.2):
    ///   radial nodes = n − l − 1,  angular nodes = l,  total = n − 1
    func generate(state: OrbitalState) -> [Splat] {
        if state.n == 1 && state.l == 0 && state.m == 0 {
            return generateSTO3G()
        }
        return generateGrid(state: state)
    }

    // MARK: - STO-3G path (1s only)

    private func generateSTO3G() -> [Splat] {
        let alphas = Self.sto3gAlphas
        let coeffs = Self.sto3gCoeffs
        let totalCoeff = coeffs.reduce(0, +)
        let aWorld = WavefunctionMath.aWorld

        return zip(alphas, coeffs).map { alpha, coeff in
            // Scale: σ = sqrt(1/(2α)) Bohr × aWorld m/Bohr
            let sigma = Float(sqrt(1.0 / (2.0 * alpha)) * aWorld)
            let opacity = Float(coeff / totalCoeff)
            return Splat(
                position: .zero,
                scale: SIMD3(repeating: sigma),
                rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                opacity: opacity,
                color: SIMD4(warmHigh.x, warmHigh.y, warmHigh.z, 1)
            )
        }
    }

    // MARK: - Grid sampler (n ≥ 2 and any non-1s state)

    private func generateGrid(state: OrbitalState) -> [Splat] {
        let rBox = halfExtent(n: state.n)
        let N = resolution
        let step = rBox * 2.0 / Double(N - 1)

        // First pass: find |ψ|_max for normalization.
        var psiMax = 0.0
        for ix in 0..<N {
            let x = -rBox + Double(ix) * step
            for iy in 0..<N {
                let y = -rBox + Double(iy) * step
                for iz in 0..<N {
                    let z = -rBox + Double(iz) * step
                    let v = abs(WavefunctionMath.psiReal(x: x, y: y, z: z,
                                                          n: state.n, l: state.l, m: state.m,
                                                          a: WavefunctionMath.aWorld))
                    if v > psiMax { psiMax = v }
                }
            }
        }
        guard psiMax > 0 else { return [] }

        let splatScale = SIMD3<Float>(repeating: Float(step * kOverlap))

        var splats: [Splat] = []
        splats.reserveCapacity(N * N * N / 10)

        // Second pass: emit above-threshold voxels as splats.
        for ix in 0..<N {
            let x = -rBox + Double(ix) * step
            for iy in 0..<N {
                let y = -rBox + Double(iy) * step
                for iz in 0..<N {
                    let z = -rBox + Double(iz) * step
                    let psi = WavefunctionMath.psiReal(x: x, y: y, z: z,
                                                        n: state.n, l: state.l, m: state.m,
                                                        a: WavefunctionMath.aWorld)
                    let mag = abs(psi) / psiMax
                    guard mag >= threshold else { continue }

                    let normalizedMag = Float(mag)
                    let opacity = pow(normalizedMag, opacityGamma)
                    let color = psi > 0
                        ? lerp(warmLow, warmHigh, t: normalizedMag)
                        : lerp(coolLow, coolHigh, t: normalizedMag)

                    splats.append(Splat(
                        position: SIMD3<Float>(Float(x), Float(y), Float(z)),
                        scale: splatScale,
                        rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                        opacity: opacity,
                        color: SIMD4<Float>(color.x, color.y, color.z, 1)
                    ))
                }
            }
        }
        return splats
    }

    // MARK: - Helpers

    /// Grid half-extent grows as n² · a₀ so higher shells sample their full spatial extent.
    /// Hard-coding a fixed box for all n is a failure mode (§11).
    private func halfExtent(n: Int) -> Double {
        let nSquaredExtent = Double(n * n) * 7.0 * WavefunctionMath.aWorld
        return min(nSquaredExtent, WavefunctionMath.rBox)
    }

    private func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, t: Float) -> SIMD4<Float> {
        a + (b - a) * t
    }

    // MARK: - Transition generator

    /// Generate splats for the quantum superposition of stateA and stateB at the given phase (0…π).
    ///
    /// Density = ½(ψ_A² + ψ_B²) + ψ_A·ψ_B·cos(phase)
    /// Sign    = sign(ψ_A + ψ_B·cos(phase))   — drives the warm/cool color mapping.
    ///
    /// At phase=0  density is weighted toward stateA geometry.
    /// At phase=π/2 both clouds coexist with no interference term.
    /// At phase=π  density is weighted toward stateB geometry.
    ///
    /// NOTE: pairs following E1 selection rules (Δℓ = ±1, Δm = 0, ±1) produce the most
    /// dramatic animation because both wavefunctions share significant spatial support.
    /// Non-E1 pairs (Δℓ ≠ ±1) will produce weak interference — a slow fade rather than
    /// a geometric transition. This is not enforced as an error; a warning is logged.
    ///
    /// Does NOT modify the existing `generate(state:)` path.
    func generate(stateA: (n: Int, l: Int, m: Int),
                  stateB: (n: Int, l: Int, m: Int),
                  phase: Float) -> [Splat] {
        let dl = abs(stateB.l - stateA.l)
        if dl != 1 {
            print("WavefunctionSplatGenerator: Δl = \(dl) ≠ ±1 — non-E1 pair, interference term may be weak.")
        }

        let rBox  = max(halfExtent(n: stateA.n), halfExtent(n: stateB.n))
        let N     = transitionResolution
        let step  = rBox * 2.0 / Double(N - 1)
        let cosPh = Double(cos(phase))

        // Pass 1 — evaluate both wavefunctions at every grid point; accumulate per-field maxima.
        let total = N * N * N
        var psiAs   = [Double](repeating: 0, count: total)
        var psiBs   = [Double](repeating: 0, count: total)
        var psiMaxA = 0.0, psiMaxB = 0.0

        var idx = 0
        for ix in 0..<N {
            let x = -rBox + Double(ix) * step
            for iy in 0..<N {
                let y = -rBox + Double(iy) * step
                for iz in 0..<N {
                    let z  = -rBox + Double(iz) * step
                    let pA = WavefunctionMath.psiReal(x: x, y: y, z: z,
                                                       n: stateA.n, l: stateA.l, m: stateA.m,
                                                       a: WavefunctionMath.aWorld)
                    let pB = WavefunctionMath.psiReal(x: x, y: y, z: z,
                                                       n: stateB.n, l: stateB.l, m: stateB.m,
                                                       a: WavefunctionMath.aWorld)
                    psiAs[idx] = pA;  if abs(pA) > psiMaxA { psiMaxA = abs(pA) }
                    psiBs[idx] = pB;  if abs(pB) > psiMaxB { psiMaxB = abs(pB) }
                    idx += 1
                }
            }
        }
        guard psiMaxA > 0 || psiMaxB > 0 else { return [] }
        let normA = psiMaxA > 0 ? psiMaxA : 1.0
        let normB = psiMaxB > 0 ? psiMaxB : 1.0

        // Pass 2 — find superposition density maximum (cheap, no wavefunction evals).
        var densityMax = 0.0
        for i in 0..<total {
            let pA = psiAs[i] / normA
            let pB = psiBs[i] / normB
            let d  = 0.5 * (pA*pA + pB*pB) + pA*pB*cosPh
            if d > densityMax { densityMax = d }
        }
        guard densityMax > 0 else { return [] }

        // Pass 3 — emit above-threshold voxels as splats.
        let splatScale = SIMD3<Float>(repeating: Float(step * kOverlap))
        var splats: [Splat] = []
        splats.reserveCapacity(total / 8)

        idx = 0
        for ix in 0..<N {
            let x = -rBox + Double(ix) * step
            for iy in 0..<N {
                let y = -rBox + Double(iy) * step
                for iz in 0..<N {
                    let z  = -rBox + Double(iz) * step
                    let pA = psiAs[idx] / normA
                    let pB = psiBs[idx] / normB
                    let d  = 0.5 * (pA*pA + pB*pB) + pA*pB*cosPh
                    let mag = d / densityMax
                    if mag >= threshold {
                        let t         = Float(mag)
                        let opacity   = pow(t, opacityGamma)
                        let signField = pA + pB * cosPh
                        let color     = signField >= 0
                            ? lerp(warmLow, warmHigh, t: t)
                            : lerp(coolLow, coolHigh, t: t)
                        splats.append(Splat(
                            position: SIMD3<Float>(Float(x), Float(y), Float(z)),
                            scale:    splatScale,
                            rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                            opacity:  opacity,
                            color:    SIMD4<Float>(color.x, color.y, color.z, 1)
                        ))
                    }
                    idx += 1
                }
            }
        }
        return splats
    }
}
