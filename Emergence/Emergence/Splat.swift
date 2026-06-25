import simd

// Renderer-agnostic Gaussian splat descriptor.
// WavefunctionSplatGenerator produces these; the downstream renderer consumes them.
// When visionOS 27 GaussianSplatResource ships, this struct maps directly to its per-splat
// layout — swap the renderer, keep the generator.
struct Splat {
    /// World-space position in meters, relative to the atom anchor entity.
    var position: SIMD3<Float>
    /// Gaussian half-width in meters. Wavefunction splats are isotropic: x == y == z.
    var scale: SIMD3<Float>
    /// Orientation. Identity for isotropic splats.
    var rotation: simd_quatf
    /// Peak opacity at the Gaussian center, before kernel falloff. [0, 1]
    var opacity: Float
    /// Linear RGBA. Warm (orange→white) for positive ψ; cool (indigo→lavender) for negative ψ.
    var color: SIMD4<Float>
}
