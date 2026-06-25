import Testing
@testable import Emergence

// Tolerance for floating-point comparisons (eV and nm precision from brief §3–§4)
private let eps = 1e-3

// MARK: - Energy levels

@Test func energyLevel1() {
    #expect(abs(HydrogenPhysics.energyLevel(1) - (-13.605693)) < eps)
}

@Test func energyLevel2() {
    #expect(abs(HydrogenPhysics.energyLevel(2) - (-3.401423)) < eps)
}

@Test func energyLevel3() {
    #expect(abs(HydrogenPhysics.energyLevel(3) - (-1.511744)) < eps)
}

@Test func energyLevel6() {
    #expect(abs(HydrogenPhysics.energyLevel(6) - (-0.377936)) < eps)
}

// MARK: - Transition wavelengths (brief §4.1)

@Test func wavelength1to2() {
    // Lyman α: 121.50 nm
    #expect(abs(HydrogenPhysics.transitionWavelength(nLo: 1, nHi: 2) - 121.50) < 0.1)
}

@Test func wavelength2to3() {
    // Balmer Hα: 656.11 nm
    #expect(abs(HydrogenPhysics.transitionWavelength(nLo: 2, nHi: 3) - 656.11) < 0.1)
}

@Test func wavelength2to4() {
    // Balmer Hβ: 486.01 nm
    #expect(abs(HydrogenPhysics.transitionWavelength(nLo: 2, nHi: 4) - 486.01) < 0.1)
}

@Test func wavelength1to3() {
    // Lyman: 102.52 nm
    #expect(abs(HydrogenPhysics.transitionWavelength(nLo: 1, nHi: 3) - 102.52) < 0.1)
}

@Test func wavelength3to4() {
    // Paschen: 1874.61 nm
    #expect(abs(HydrogenPhysics.transitionWavelength(nLo: 3, nHi: 4) - 1874.61) < 1.0)
}

// MARK: - Selection rules (brief §4.2)

@Test func dipoleAllowedBasic() {
    // s→p allowed (Δl=1, Δm=0)
    #expect(HydrogenPhysics.dipoleAllowed(l1: 0, m1: 0, l2: 1, m2: 0) == true)
    // p→d allowed (Δl=1, Δm=1)
    #expect(HydrogenPhysics.dipoleAllowed(l1: 1, m1: 0, l2: 2, m2: 1) == true)
}

@Test func dipoleAllowedDeltaLZeroForbidden() {
    // s→s forbidden (Δl=0)
    #expect(HydrogenPhysics.dipoleAllowed(l1: 0, m1: 0, l2: 0, m2: 0) == false)
    // p→p forbidden (Δl=0)
    #expect(HydrogenPhysics.dipoleAllowed(l1: 1, m1: 0, l2: 1, m2: 0) == false)
}

@Test func dipoleAllowedDeltaMTwoForbidden() {
    // Δm=2 forbidden even with Δl=1
    #expect(HydrogenPhysics.dipoleAllowed(l1: 1, m1: -1, l2: 2, m2: 1) == false)
}

@Test func dipoleAllowedDeltaLTwoForbidden() {
    // s→d forbidden (Δl=2)
    #expect(HydrogenPhysics.dipoleAllowed(l1: 0, m1: 0, l2: 2, m2: 0) == false)
}

// MARK: - Substate counts (n² total per level)

@Test func subStateCounts() {
    for n in 1...6 {
        #expect(HydrogenPhysics.subStates(n).count == n * n)
    }
}

// MARK: - Laguerre polynomial (brief §5.1)

@Test func laguerreL0() {
    // L₀^α(x) = 1 for any α, x
    #expect(abs(WavefunctionMath.laguerre(0, 2.0, 3.0) - 1.0) < 1e-10)
}

@Test func laguerreL1() {
    // L₁^α(x) = 1 + α - x
    let alpha = 3.0, x = 2.5
    #expect(abs(WavefunctionMath.laguerre(1, alpha, x) - (1.0 + alpha - x)) < 1e-10)
}

@Test func laguerreL2alpha1() {
    // L₂^1(x) = 3 - 3x + x²/2  (brief-verified closed form)
    let x = 2.0
    let expected = 3.0 - 3.0*x + x*x/2.0
    #expect(abs(WavefunctionMath.laguerre(2, 1.0, x) - expected) < 1e-10)
}

@Test func laguerreL2alpha3() {
    // L₂^3(x) = 10 - 5x + x²/2  (brief-verified closed form)
    let x = 2.0
    let expected = 10.0 - 5.0*x + x*x/2.0
    #expect(abs(WavefunctionMath.laguerre(2, 3.0, x) - expected) < 1e-10)
}

// MARK: - psi2 boundary conditions (brief §5.3)

@Test func psi2AtOriginSStateFinite() {
    // s-states (l=0) are finite and nonzero at the nucleus
    let a = WavefunctionMath.aWorld
    let d = WavefunctionMath.psi2(x: 0, y: 0, z: 0, n: 1, l: 0, m: 0, a: a)
    #expect(d > 0)
    #expect(d.isFinite)
}

@Test func psi2AtOriginPStateZero() {
    // p-states (l=1) vanish at the nucleus (angular node)
    let a = WavefunctionMath.aWorld
    let d = WavefunctionMath.psi2(x: 0, y: 0, z: 0, n: 2, l: 1, m: 0, a: a)
    #expect(d < 1e-20)
}

@Test func psi2AtOriginDStateZero() {
    // d-states (l=2) vanish at the nucleus
    let a = WavefunctionMath.aWorld
    let d = WavefunctionMath.psi2(x: 0, y: 0, z: 0, n: 3, l: 2, m: 0, a: a)
    #expect(d < 1e-20)
}

@Test func psi2IsNonNegative() {
    // Density must be non-negative everywhere
    let a = WavefunctionMath.aWorld
    let offsets: [Double] = [0, 0.01, 0.05, 0.1, 0.2]
    for x in offsets {
        for n in 1...4 {
            for l in 0..<n {
                for m in -l...l {
                    let d = WavefunctionMath.psi2(x: x, y: x*0.3, z: x*0.7,
                                                  n: n, l: l, m: m, a: a)
                    #expect(d >= 0)
                }
            }
        }
    }
}

// MARK: - Radial node counts
// For state (n,l): n - l - 1 radial nodes (zeros in R_nl excluding r=0 and r=∞)
// We verify by scanning radially and counting sign changes in R_nl ∝ ρ^l * exp(-ρ/2) * L_{n-l-1}^{2l+1}(ρ)

@Test func radialNodes2s() {
    // 2s: n-l-1 = 1 node
    #expect(radialNodeCount(n: 2, l: 0) == 1)
}

@Test func radialNodes3s() {
    // 3s: n-l-1 = 2 nodes
    #expect(radialNodeCount(n: 3, l: 0) == 2)
}

@Test func radialNodes3p() {
    // 3p: n-l-1 = 1 node
    #expect(radialNodeCount(n: 3, l: 1) == 1)
}

@Test func radialNodes1s() {
    // 1s: n-l-1 = 0 nodes
    #expect(radialNodeCount(n: 1, l: 0) == 0)
}

// Count sign changes in the radial function (excluding the ρ^l prefactor node at origin)
private func radialNodeCount(n: Int, l: Int) -> Int {
    let a = WavefunctionMath.aWorld
    let nSamples = 2000
    let rMax = Double(n * n) * 5.0 * a // well beyond outermost lobe
    var nodes = 0
    var prevSign = 0.0
    for i in 0..<nSamples {
        let r = rMax * Double(i + 1) / Double(nSamples)
        let rho = 2.0 * r / (Double(n) * a)
        // Radial function value (sign is what matters)
        let val = WavefunctionMath.laguerre(n - l - 1, Double(2*l + 1), rho)
        let sign = val < 0 ? -1.0 : 1.0
        if prevSign != 0 && sign != prevSign { nodes += 1 }
        prevSign = sign
    }
    return nodes
}

// MARK: - psi2Real azimuthal variation

@Test func psi2RealMZeroMatchesEigenstate() {
    // For m=0, real and eigenstate densities are identical (no phi dependence)
    let a = WavefunctionMath.aWorld
    let x = 0.05, y = 0.03, z = 0.04
    let eigen = WavefunctionMath.psi2(x: x, y: y, z: z, n: 2, l: 1, m: 0, a: a)
    let real  = WavefunctionMath.psi2Real(x: x, y: y, z: z, n: 2, l: 1, m: 0, a: a)
    #expect(abs(eigen - real) < 1e-20)
}

@Test func psi2RealHasPhiVariation() {
    // For m≠0, real orbital density varies with phi (unlike eigenstate which doesn't)
    let a = WavefunctionMath.aWorld
    let r = 0.04
    // Two points at same (r, theta) but different phi
    let d1 = WavefunctionMath.psi2Real(x: r, y: 0, z: 0, n: 2, l: 1, m: 1, a: a) // phi=0
    let d2 = WavefunctionMath.psi2Real(x: 0, y: r, z: 0, n: 2, l: 1, m: 1, a: a) // phi=π/2
    // cos²(phi): d1 should be large (phi=0→cos²=1), d2 should be ~0 (phi=π/2→cos²=0)
    #expect(d1 > 0.001)
    #expect(d2 < 1e-10)
}

// MARK: - Emission targets

@Test func groundStateHasNoEmissionTargets() {
    // 1s ground state: no downward transitions possible
    let targets = HydrogenPhysics.emissionTargets(n: 1, l: 0, m: 0)
    #expect(targets.isEmpty)
}

@Test func twoSHasNoEmissionTargets() {
    // 2s (l=0): Δl=±1 requires l'=1, but l'<n'=1 forces l'=0 → no valid target
    let targets = HydrogenPhysics.emissionTargets(n: 2, l: 0, m: 0)
    #expect(targets.isEmpty)
}

@Test func twoPHasEmissionTarget() {
    // 2p (l=1): can decay to 1s (l=0) — the only allowed lower state
    let targets = HydrogenPhysics.emissionTargets(n: 2, l: 1, m: 0)
    #expect(!targets.isEmpty)
    #expect(targets.allSatisfy { $0.n == 1 && $0.l == 0 })
}

// MARK: - Ionization energy

@Test func ionizationEnergyGroundState() {
    #expect(abs(HydrogenPhysics.ionizationEnergy(1) - 13.605693) < eps)
}

@Test func ionizationEnergy2() {
    #expect(abs(HydrogenPhysics.ionizationEnergy(2) - 3.401423) < eps)
}
