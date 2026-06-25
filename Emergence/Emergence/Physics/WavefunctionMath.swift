import Foundation

// Hydrogen wavefunction mathematics: Laguerre, associated Legendre, and
// the full |ψ_nlm|² density evaluator for both complex eigenstates and
// real (textbook) orbital combinations.
//
// Normalization constants are omitted — they cancel when the field is
// normalized by its own maximum for display (brief §5.3).
enum WavefunctionMath {

    // MARK: - Special functions

    /// Generalized (associated) Laguerre polynomial L_k^α(x) via stable recurrence.
    /// Verified: L₁^α = 1+α-x, L₂^1 = 3-3x+x²/2, L₂^3 = 10-5x+x²/2
    static func laguerre(_ k: Int, _ alpha: Double, _ x: Double) -> Double {
        if k <= 0 { return 1.0 }
        var lkm1 = 1.0                   // L₀^α
        var lk   = 1.0 + alpha - x       // L₁^α
        guard k > 1 else { return lk }
        var i = 1
        while i < k {
            let lkp1 = ((Double(2*i) + 1.0 + alpha - x) * lk
                        - (Double(i) + alpha) * lkm1) / Double(i + 1)
            lkm1 = lk; lk = lkp1; i += 1
        }
        return lk
    }

    /// Associated Legendre function P_ℓ^m(x) where x = cos θ, m ≥ 0.
    /// Condon–Shortley phase is irrelevant — density uses P² so sign drops out.
    static func assocLegendre(_ l: Int, _ m: Int, _ x: Double) -> Double {
        // Seed: P_m^m = (2m−1)!! · (1−x²)^(m/2)
        var pmm = 1.0
        if m > 0 {
            let somx2 = sqrt(max(0.0, 1.0 - x * x))
            var fact = 1.0
            for _ in 0..<m { pmm *= fact * somx2; fact += 2.0 }
        }
        if l == m { return pmm }

        // P_{m+1}^m
        var pmmp1 = x * Double(2 * m + 1) * pmm
        if l == m + 1 { return pmmp1 }

        // Recurrence up to l
        var pll = 0.0
        var ll  = m + 2
        while ll <= l {
            pll = (Double(2*ll - 1) * x * pmmp1 - Double(ll + m - 1) * pmm) / Double(ll - m)
            pmm = pmmp1; pmmp1 = pll; ll += 1
        }
        return pll
    }

    // MARK: - Density evaluators

    /// Un-normalized |ψ_nℓm|² at Cartesian point (x,y,z).
    /// `a` is the Bohr radius in world units (meters).
    /// Azimuthally symmetric for definite-m eigenstates — |ψ|² has no φ dependence.
    static func psi2(x: Double, y: Double, z: Double,
                     n: Int, l: Int, m: Int, a: Double) -> Double {
        let r = sqrt(x*x + y*y + z*z)
        let cosTheta = r < 1e-9 ? 1.0 : z / r
        let rho = 2.0 * r / (Double(n) * a)
        let radial = pow(rho, Double(l))
                   * exp(-rho / 2.0)
                   * laguerre(n - l - 1, Double(2*l + 1), rho)
        let plm = assocLegendre(l, abs(m), cosTheta)
        return radial * radial * plm * plm
    }

    /// Un-normalized density for real (textbook) orbitals — includes φ dependence.
    /// The quantum state (n,l,m) drives the radial and polar parts as usual;
    /// the φ factor differs by sign of m:
    ///   m = 0 → azimuthally symmetric (same as eigenstate)
    ///   m > 0 → cosine-type:  cos(|m|φ)  e.g., pₓ, dₓᵤ, d_{x²−y²}
    ///   m < 0 → sine-type:    sin(|m|φ)  e.g., p_y, d_yz, d_xy
    static func psi2Real(x: Double, y: Double, z: Double,
                         n: Int, l: Int, m: Int, a: Double) -> Double {
        let r = sqrt(x*x + y*y + z*z)
        let cosTheta = r < 1e-9 ? 1.0 : z / r
        let phi  = atan2(y, x)
        let absM = abs(m)
        let rho  = 2.0 * r / (Double(n) * a)
        let radial = pow(rho, Double(l))
                   * exp(-rho / 2.0)
                   * laguerre(n - l - 1, Double(2*l + 1), rho)
        let plm = assocLegendre(l, absM, cosTheta)
        let phiFactor: Double
        switch m {
        case 0:         phiFactor = 1.0
        case let pm where pm > 0: phiFactor = cos(Double(absM) * phi)
        default:        phiFactor = sin(Double(absM) * phi)
        }
        return radial * radial * plm * plm * phiFactor * phiFactor
    }

    /// Signed real-orbital amplitude ψ at Cartesian point (x,y,z).
    /// Positive and negative lobes have opposite signs — this encodes the quantum phase.
    /// Normalization constants are omitted; divide by the field maximum for display.
    /// m=0 → z-type, m>0 → cosine-type (pₓ, dₓᵤ …), m<0 → sine-type (p_y, d_yz …)
    static func psiReal(x: Double, y: Double, z: Double,
                        n: Int, l: Int, m: Int, a: Double) -> Double {
        let r = sqrt(x*x + y*y + z*z)
        let cosTheta = r < 1e-9 ? 1.0 : z / r
        let phi  = atan2(y, x)
        let absM = abs(m)
        let rho  = 2.0 * r / (Double(n) * a)
        let radial = pow(rho, Double(l))
                   * exp(-rho / 2.0)
                   * laguerre(n - l - 1, Double(2*l + 1), rho)
        let plm = assocLegendre(l, absM, cosTheta)
        let phiFactor: Double
        switch m {
        case 0:         phiFactor = 1.0
        case let pm where pm > 0: phiFactor = cos(Double(absM) * phi)
        default:        phiFactor = sin(Double(absM) * phi)
        }
        return radial * plm * phiFactor
    }

    // MARK: - Volume builder helpers

    /// The world-space Bohr radius (meters) sized so n=6 near-circular cloud ≈ 0.5 m across.
    /// Largest extent at n=6, ℓ=5: ρ_max ≈ 22 → r_max ≈ 66·a_world ≈ 0.25 m → a_world ≈ 3.8 mm.
    static let aWorld: Double = 0.0038

    /// Half-extent of the bounding box in meters (cloud fits within ±Rbox on each axis)
    static let rBox:   Double = 0.25
}
