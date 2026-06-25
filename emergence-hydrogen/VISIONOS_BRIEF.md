# Hydrogen Atom — visionOS / Apple Vision Pro Port: Engineering & Physics Brief

**Audience:** the Claude agent picking up this work inside an Xcode workspace.
**Source of truth:** the 2D p5.js prototype in this repo (`emergence-hydrogen/`). Every formula below is already implemented and numerically verified there; file/line references are given so you can read the originals.
**Date:** 2026-06.

---

## 0. How to use this brief

1. The **physics in §3–§6 is exact and non-negotiable** — it is the whole point of the project. Reproduce it faithfully. All constants are CODATA-2018, all closed forms are verified.
2. The **rendering and interaction sections (§7–§10) are directive but pragmatic.** Architecture choices that are version-sensitive on visionOS are flagged `⚠️ VERIFY` — confirm them against the visionOS SDK you actually have before committing.
3. When in doubt about a number, re-derive it from §3 or read the cited JS file. Do **not** invent constants.

---

## 1. What we are building

A spatial, embodied recreation of **"Models of the Hydrogen Atom"** for Apple Vision Pro, focused exclusively on the **Schrödinger interpretation**: a programmatically generated, **volumetrically ray-marched 3D electron probability cloud** `|ψ_nℓm|²` computed from the real hydrogen wavefunctions, that the user excites and de-excites by firing photons at it with **spatial hand gestures**.

### In scope (decided with the product owner)

- **3D Schrödinger probability cloud**, volumetric raymarch of the true `|ψ_nℓm|²` field.
- **Orbital basis:** the rigorous **definite-(n, ℓ, m) energy eigenstates**, rendering `|ψ_nℓm|²`. This is the basis the dipole selection rules operate in (so transitions stay self-consistent). Real "textbook" orbitals (pₓ, p_y, d_xy…) are an *optional* cosmetic mode — see §6.4.
- **Full transition dynamics:** resonant photon absorption, spontaneous-emission cascade with **Δℓ = ±1, Δm ∈ {−1,0,+1}** dipole selection rules, **n³ radiative lifetimes**, ionization + recombination.
- **Energy-level diagram** and **accumulating spectrometer** as spatial panels.
- **Time-dilation readout:** "real time elapsed" clock + slowdown factor.
- **Dual presentation:** runs in a **mixed-reality (passthrough) ImmersiveSpace** *and* can switch to a **fully immersive** environment (an Apple environment now, a custom one later).

### Out of scope

- The other five models (Billiard Ball, Plum Pudding, Classical Solar System, Bohr, de Broglie). Schrödinger only.
- Spin, fine/hyperfine structure, relativistic corrections, multi-electron physics. Non-relativistic, spinless, single-electron hydrogen only — same as the 2D prototype.

---

## 2. Source-of-truth code map (read these)

| File | What to extract |
|---|---|
| `js/physics.js` | Constants, `energyLevel(n)`, transitions, `dipoleAllowed`, `subStates(n)`, lifetimes (`levelLifetimeNs`, `sampleLevelDwellFrames`), time-scale constants. |
| `js/models/models.js` → `SchrodingerModel` & `QuantumModel` | Wavefunction math (`laguerre`, `_radialDensity`, `_angular`), density-field build (`_rebuild`), the absorption/emission/ionization state machine, transfer function & color. |
| `js/spectrum.js` | `wavelengthToRGB(nm)` — wavelength → display color (used for photons, beam, spectrometer). |
| `js/photon.js` | Photon glyph behavior (traveling wave-packet). |
| `js/energyDiagram.js` | Energy-ladder panel + "photon energy bracket" match mechanic. |
| `js/spectrometer.js` | Emission-line accumulation & spectrum strip. |
| `js/sketch.js` | Gesture state machine (tap vs. drag, relative tuning, magnetic snap), main loop, time clock. |

---

## 3. Physical constants & energy levels

CODATA-2018, energies in **eV**, wavelengths in **nm**.

```
HC_EV_NM   = 1239.841984      // h·c  →  λ(nm) = HC_EV_NM / E(eV)
RYDBERG_EV = 13.605693        // |E₁|, hydrogen ionization energy
a₀         = 0.529177210903e-10 m   // Bohr radius (for real-world scale only)
```

**Energy of level n:**  `E_n = −RYDBERG_EV / n²`  (eV)

| n | E_n (eV) | Ionization energy from n = −E_n (eV) | substates (n²) |
|---|---|---|---|
| 1 | −13.6057 | 13.6057 | 1 |
| 2 | −3.4014  | 3.4014  | 4 |
| 3 | −1.5117  | 1.5117  | 9 |
| 4 | −0.8504  | 0.8504  | 16 |
| 5 | −0.5442  | 0.5442  | 25 |
| 6 | −0.3779  | 0.3779  | 36 |

`NMAX = 6` (highest bound level modeled).

---

## 4. Transitions & selection rules

### 4.1 Transition energies / wavelengths (n_lo → n_hi)

`ΔE = E_hi − E_lo` (absorption, positive); `λ = HC_EV_NM / ΔE`.

| transition | ΔE (eV) | λ (nm) | band | series |
|---|---|---|---|---|
| 1→2 | 10.2043 | 121.50 | UV | Lyman |
| 1→3 | 12.0939 | 102.52 | UV | Lyman |
| 1→4 | 12.7553 | 97.20 | UV | Lyman |
| 1→5 | 13.0615 | 94.92 | UV | Lyman |
| 1→6 | 13.2278 | 93.73 | UV | Lyman |
| 2→3 | 1.8897 | 656.11 | visible | Balmer (Hα) |
| 2→4 | 2.5511 | 486.01 | visible | Balmer (Hβ) |
| 2→5 | 2.8572 | 433.94 | visible | Balmer |
| 2→6 | 3.0235 | 410.07 | visible | Balmer |
| 3→4 | 0.6614 | 1874.61 | IR | Paschen |
| 3→5 | 0.9675 | 1281.47 | IR | Paschen |
| 3→6 | 1.1338 | 1093.52 | IR | Paschen |
| 4→5 | 0.3061 | 4050.08 | IR | Brackett |
| 4→6 | 0.4724 | 2624.45 | IR | Brackett |
| 5→6 | 0.1663 | 7455.82 | IR | Pfund |

(Generate this table in code from `E_n`, don't hardcode — but use it to sanity-check.)

### 4.2 Electric-dipole (E1) selection rules

A transition between (ℓ, m) and (ℓ', m') is dipole-allowed iff:

```
Δℓ = |ℓ' − ℓ| = 1      AND      |m' − m| ≤ 1
```

(`physics.js: dipoleAllowed(l1,m1,l2,m2)`.) This governs **both** which (ℓ) the electron can absorb into and which (n', ℓ') it can emit down to. **n itself is unrestricted** (any Δn), only ℓ and m are constrained.

### 4.3 Substates available at level n

For each n: `ℓ = 0 … n−1`, and for each ℓ: `m = −ℓ … +ℓ`. Total = n² (table in §3). `ORBITAL_LETTER = {0:"s", 1:"p", 2:"d", 3:"f", 4:"g", 5:"h"}`.

---

## 5. The wavefunction (the math to render)

The full hydrogen stationary state (atomic units, `a = a₀`):

```
ψ_nℓm(r,θ,φ) = R_nℓ(r) · Y_ℓm(θ,φ)
density       = |ψ_nℓm|² = |R_nℓ(r)|² · |Y_ℓm(θ,φ)|²
```

For definite-m eigenstates, `|Y_ℓm|²` is **independent of φ** (azimuthally symmetric about the z / quantization axis). ⇒ **the 3D density is a surface of revolution of a 2D (r,θ) field about z.** You may exploit this (render/compute a 2D field and revolve) or evaluate fully in 3D — both are cheap. The 2D prototype renders the x–z slice (`models.js: _rebuild`); the 3D port simply removes the slice assumption.

### 5.1 Radial part `R_nℓ(r)`

```
ρ = 2r / (n · a)
R_nℓ(r) = N_nℓ · ρ^ℓ · e^(−ρ/2) · L_{n−ℓ−1}^{2ℓ+1}(ρ)
N_nℓ    = sqrt( (2/(n·a))³ · (n−ℓ−1)! / (2n·(n+ℓ)!) )      // normalization
```

`L_k^α` = generalized (associated) Laguerre polynomial. **Radial behavior to preserve:** density ∝ `r^(2ℓ)` near the nucleus (s-states peak AT the nucleus; p/d/f vanish there), `n−ℓ−1` unevenly-spaced radial nodes, a **dominant outermost lobe**. Verified node counts: (2s→1), (3s→2), (3p→1), (6s→5), etc.

**Laguerre recurrence** (verified against closed forms L₁¹, L₂¹, L₂³):

```swift
// Lₖ^α(x)
func laguerre(_ k: Int, _ alpha: Double, _ x: Double) -> Double {
    if k <= 0 { return 1 }
    var lkm1 = 1.0                 // L₀
    var lk   = 1 + alpha - x       // L₁
    var i = 1
    while i < k {
        let lkp1 = ((Double(2*i) + 1 + alpha - x) * lk - (Double(i) + alpha) * lkm1) / Double(i + 1)
        lkm1 = lk; lk = lkp1; i += 1
    }
    return lk
}
```

### 5.2 Angular part `|Y_ℓm(θ,φ)|²`

```
|Y_ℓm(θ,φ)|² = (2ℓ+1)/(4π) · (ℓ−|m|)!/(ℓ+|m|)! · [P_ℓ^{|m|}(cosθ)]²      // φ drops out
```

`P_ℓ^m` = associated Legendre function. **Angular shapes are exactly the recognizable orbital lobes** — already verified term-by-term against |Y_ℓm|² in the 2D prototype for ℓ ≤ 3; for the 3D port you need ℓ up to **5** (n=6 ⇒ ℓ_max = 5), so use the general recurrence rather than a hardcoded table.

**Associated Legendre recurrence** (Condon–Shortley sign irrelevant — it's squared; pass `m = |m|`):

```swift
// P_ℓ^m(x), x = cosθ, m ≥ 0
func assocLegendre(_ l: Int, _ m: Int, _ x: Double) -> Double {
    // P_m^m = (2m−1)!! · (1−x²)^(m/2)
    var pmm = 1.0
    if m > 0 {
        let somx2 = sqrt(max(0.0, 1.0 - x*x))
        var fact = 1.0
        for _ in 0..<m { pmm *= fact * somx2; fact += 2.0 }   // (2m−1)!! · somx2^m
    }
    if l == m { return pmm }
    var pmmp1 = x * Double(2*m + 1) * pmm                      // P_{m+1}^m
    if l == m + 1 { return pmmp1 }
    var pll = 0.0
    var ll = m + 2
    while ll <= l {
        pll = (Double(2*ll - 1) * x * pmmp1 - Double(ll + m - 1) * pmm) / Double(ll - m)
        pmm = pmmp1; pmmp1 = pll; ll += 1
    }
    return pll
}
```

### 5.3 Putting it together — `density(x,y,z)`

```swift
// returns un-normalized |ψ_nℓm|² at a point; aWorld = Bohr radius in world units (§9)
func psi2(_ x: Double, _ y: Double, _ z: Double, n: Int, l: Int, m: Int, a: Double) -> Double {
    let r = sqrt(x*x + y*y + z*z)
    let cosTheta = r < 1e-9 ? 1.0 : z / r
    let rho = 2*r / (Double(n) * a)
    let radial = pow(rho, Double(l)) * exp(-rho/2) * laguerre(n - l - 1, Double(2*l + 1), rho)
    let plm = assocLegendre(l, abs(m), cosTheta)
    // normalization constants may be dropped (see note) — squared shape is what matters
    return (radial * radial) * (plm * plm)
}
```

**Normalization note:** because each state is rendered one at a time and the field is normalized by its own maximum for display (see §6.1), the constant prefactors `N_nℓ` and the `(2ℓ+1)/4π · …` angular constant **cancel** and may be omitted for rendering. Keep them only if you ever need absolute, cross-state-comparable probability density. The φ-dependence `e^(imφ)` vanishes under `|·|²` for definite m.

### 5.4 Building the 3D volume texture

1. Allocate a 3D scalar texture, recommended **96³–128³** (`Float16` is plenty).
2. For each voxel, map index → world offset (x,y,z) over `[−Rbox, +Rbox]³` (see §9 for Rbox), evaluate `psi2(...)`, store.
3. Track the max; **normalize the stored field by max** (or store raw + pass max to the shader).
4. Regenerate **only on a state change** (absorption/emission/recombination), not per frame. A 128³ field is ~2M evaluations — do it on a background thread or, preferably, a **Metal compute shader** to keep it sub-frame.
5. **Optimization (recommended):** exploit azimuthal symmetry — compute a 2D `(r,θ)` texture (e.g. 256×256) and revolve it in the raymarch shader by computing `(r,θ)` from the sample point. Far higher radial resolution for the same cost.

---

## 6. Simulation state machine (transition dynamics)

Mirror `SchrodingerModel` + `QuantumModel` in `models.js`. State: current `(n, ℓ, m)`, `ionized` flag, a per-state dwell timer, and a jump-animation interpolant.

### 6.1 Density render normalization & transfer function

The 2D prototype maps normalized density → color with a soft glow (`models.js: _rebuild` paint loop + `draw`):

```
t   = pow(density / maxDensity, 0.55)        // gamma softens falloff
rgb = ( 60+185·t , 130+120·t , 230+25·t )    // deep blue → cyan → white
a   = 235·t                                  // opacity ∝ intensity
blend = additive (glow)
```

For the **volumetric raymarch**, reuse this as the **transfer function** `density → (rgb, σ)` where σ is opacity/extinction per unit length. Use a front-to-back emission–absorption integral:

```
for each step along the ray (inside the bounding cube):
    d   = sampleVolume(p)                 // normalized 0..1
    t   = pow(d, 0.55)
    rgb = mix(deepBlue, white, t)         // tune to taste; match 2D palette
    sigma = k · d                         // extinction; k tuned for density of cloud
    Cout += (1 - Aout) * (rgb * sigma * stepLen)
    Aout += (1 - Aout) * (sigma * stepLen)
    if Aout > 0.99 { break }
```

Keep the look consistent with the 2D version (a luminous nebular cloud, brightest where probability is highest). Step count ~64–128; use jittered start to avoid banding.

### 6.2 Absorption (photon hits atom)

When a photon reaches the atom, with `E = photon.energy` (eV) and current `(n, ℓ, m)`:

1. **Resonant match:** find a transition `n → n_hi` (n_hi > n, ≤ NMAX) with `|ΔE − E| < TOL`. `TOL = 0.08 eV` in 2D (`matchAbsorption`) — for a precise spatial controller you may tighten it; expose as a constant.
2. If matched, require an allowed upper `ℓ'` with `Δℓ = ±1` from current ℓ (and the m rule). Pick uniformly among allowed `ℓ'`. Set `n = n_hi`, `ℓ = ℓ'`, start the jump animation, **rebuild the volume**, and arm the emission dwell timer (§6.5).
3. **Ionization:** if no resonant match **and** `E ≥ |E_n|` (`ionizes(n,E)`), set `ionized = true` and start a recombination delay.
4. Otherwise the photon is **not absorbed** (passes through / scatters).

Photon "armed" rule (avoid self-absorption on spawn): a photon becomes absorbable only after it has first cleared the atom's interaction radius (`photon.js: armed`, `sketch.js` interaction loop).

### 6.3 Spontaneous emission cascade

While bound and `n > 1`, after the dwell timer expires:

1. Choose a lower target `(n', ℓ')` with `n' < n` and `Δℓ = ±1` allowed (Schrödinger `emissionTarget` enumerates valid `(n',ℓ')` and picks one).
2. Emit a photon of energy `ΔE = E_n − E_{n'}`, wavelength `λ = HC/ΔE`, **recorded by the spectrometer** (§8). Emission direction is isotropic (random) — in 3D, pick a uniform random direction on the sphere.
3. Set `n = n'`, `ℓ = ℓ'`, clamp `m` to `[−ℓ, ℓ]`, rebuild volume, re-arm dwell timer.
4. Repeat until `n = 1` (ground state, stable).

### 6.4 (Optional) real-orbital cosmetic mode

If you later add the "textbook" orbital toggle: render real linear combinations (pₓ, p_y from m=±1; d_xy, d_{x²−y²} from m=±2; etc.), but **keep the (n,ℓ,m) eigenstate machinery underneath** for transitions — the real orbitals are display-only. Default mode stays the m-eigenstate `|ψ_nℓm|²`.

### 6.5 Lifetimes & time dilation (relative-time accuracy)

Spontaneous emission is **memoryless** ⇒ the dwell time in an excited level is **exponentially distributed** with mean = the level's radiative lifetime.

```
τ(n) = 0.2 ns · n³         // anchored to measured 2p lifetime (1.6 ns); dominant np channel
```

| n | τ(n) (ns) |
|---|---|
| 2 | 1.60 |
| 3 | 5.40 |
| 4 | 12.80 |
| 5 | 25.00 |
| 6 | 43.20 |

Higher levels live **longer** → a cascade lingers high and drops fast through low levels. (This fixed an artifact in an earlier build where every level shared a uniform timer and the electron wrongly "lingered" at n=2.)

**Time scale (frame-rate independent — use wall-clock Δt in seconds, NOT frames):**

```
SLOWDOWN              = 1.17e8                 // display is ~1.17×10⁸× slower than reality
REAL_SECONDS_PER_DISPLAY_SECOND = 1 / SLOWDOWN ≈ 8.547e-9   // 1 s in headset ≈ 8.55 ns real
displayDwellSeconds(n) = τ(n)_seconds · SLOWDOWN
```

Mean display dwell: n2 ≈ 0.19 s, n3 ≈ 0.63 s, n4 ≈ 1.50 s, n5 ≈ 2.93 s, n6 ≈ 5.05 s. Sample each dwell:

```swift
func sampleDwellSeconds(_ n: Int) -> Double {
    let mean = (0.2 * pow(Double(n), 3) * 1e-9) * SLOWDOWN   // seconds
    let u = max(1e-6, Double.random(in: 0...1))
    return min(mean * 4, -log(u) * mean)                     // exponential, tail-capped
}
```

**Real-time clock:** accumulate `realTimeElapsed += Δt_display · REAL_SECONDS_PER_DISPLAY_SECOND`; display in ns/ps/fs (see §8). Reset on atom reset / state reset.

**Caveats to surface in the brief, not "fix":**
- **2s metastability:** the *one* case where lingering at n=2 is physically real — 2s cannot E1-decay to 1s (Δℓ=0 forbidden) and lives ~0.12 s, ~10⁷× longer than 2p. We deliberately use the n-based τ for a watchable, consistent clock. If desired, add 2s as a **labeled, capped "metastable"** special case — but a true-scale 2s would freeze the sim.
- The **recombination delay** after ionization is *not* a radiative lifetime (in a real gas it depends on density, µs–ms); keep it a fixed, modest delay and don't tie it to the ns clock.

### 6.6 Color (wavelength → RGB)

Reuse `spectrum.js: wavelengthToRGB(nm)` verbatim (Dan Bruton 380–780 nm approximation, with dim violet for UV < 380 and dim red for IR > 780, gamma 0.8). Used for **photon glyph color, beam color, spectrometer lines, and the energy-bracket readout.** Port the function exactly.

---

## 7. Volumetric rendering on visionOS

**Goal:** a luminous 3D `|ψ|²` cloud, ray-marched, that works in **mixed (passthrough)** and **full** immersion.

### Recommended architecture

- **RealityKit in an `ImmersiveSpace`.** RealityKit handles both passthrough and fully-immersive presentation via the space's **immersion style** (`.mixed` / `.progressive` / `.full`), so a single content graph serves both modes and lets you drop into an Apple environment or a custom one later. `⚠️ VERIFY` the immersion-style switching API for your SDK.
- **The cloud = a unit bounding-box entity** with a custom material that ray-marches a **3D texture** of normalized `|ψ|²` (§5.4).
  - Generate the texture with a **Metal compute shader** (or background CPU) on each state change; upload as a 3D texture resource. `⚠️ VERIFY` current RealityKit support for 3D textures / `LowLevelTexture`.
  - **Shader path:** the supported custom-shading route in RealityKit on visionOS is **`ShaderGraphMaterial` (MaterialX)**. A raymarch with a bounded, fixed step count can be expressed there. **This is the single biggest technical risk — validate a minimal raymarch-in-ShaderGraphMaterial spike first.** `⚠️ VERIFY`
  - **Fallback if ShaderGraph raymarch proves impractical:** a full-Metal immersive renderer via **CompositorServices / `LayerRenderer`** gives unrestricted shader freedom (easy raymarch) but you must handle passthrough compositing yourself and it's a heavier path. (Note: the product owner explicitly chose volumetric over a particle cloud, so prefer making the volume work over substituting particles.)
- **Per-state regeneration**, not per-frame. Animate the *transition* (level change) by cross-fading/scaling between the old and new volumes over the jump-animation interval (the 2D `jumpAnim` interpolates the orbital radius; in 3D, cross-fade the two density textures or blend their opacities).
- **The nucleus** is a sub-pixel point at true scale (proton:Bohr ≈ 1.6×10⁻⁵). Render a tiny fixed marker (a small emissive sphere) at the origin, clearly dwarfed by the cloud — see `models.js: _drawProton`. Optionally a subtle billboarded glow so it's locatable.

---

## 8. Spatial UI panels

Implement as SwiftUI views attached to the immersive scene (RealityKit attachments) or as floating windows the user can place. Keep them legible at ~1–1.5 m.

- **Energy-level diagram** (`energyDiagram.js`): vertical ladder of `E_n` (n=1..6) with the current level highlighted; a **"photon energy bracket"** rising from the current level by the dialed photon energy, turning **green ✓** when it matches a real transition from the current n, **red** when it would ionize, **blue** otherwise. This is the core "match the gap" feedback — make it prominent and spatial. Ticks for available transitions from the current level.
- **Spectrometer** (`spectrometer.js`): a UV→visible→IR axis (range 80–820 nm) with a colored spectrum strip; each **emitted** wavelength accumulates as a colored vertical line whose height ∝ count. Persistent until cleared.
- **Time-dilation readout** (`sketch.js: drawTimescale`): two lines —
  `time slowed ~1.2×10⁸× · 1 s here ≈ 8.5 ns real`
  `real time elapsed: <ns/ps/fs>` (live).
- **Current state label:** `n ℓ-letter m` (e.g. `3d m=−1`) near the cloud.

---

## 9. Scale, units, placement

- **Pick a render-space Bohr radius `aWorld`** mapping atomic units → meters. Constraint: the largest modeled state (n=6, near-circular ℓ=5) extends to roughly `ρ ≈ 22` ⇒ `r ≈ 66·aWorld`. To make the n=6 cloud about **0.5 m** across (a comfortable tabletop atom): `66·aWorld ≈ 0.25 m ⇒ aWorld ≈ 3.8 mm`. Set the volume bounding half-extent `Rbox ≈ 0.25 m`.
- **Consequence (intended):** lower-n clouds are genuinely, dramatically smaller (1s ≈ a few cm) — true ∝n² scaling, as in the corrected 2D version. Don't "fix" this; it's physically honest. Offer a user **scale handle** (two-hand pinch-zoom) so they can grow a small state to inspect it.
- **Placement:** spawn at a comfortable reach (~0.6–0.8 m in front, ~eye level), **grabbable/rotatable** with a one-hand pinch-drag, **scalable** with two hands.

---

## 10. Embodied interaction design (Vision Pro hand tracking)

The 2D prototype already defines clean gesture *semantics* — port the **semantics**, upgrade the *modality* to spatial. The 2D vocabulary (`sketch.js`): **quick pinch = fire photon**, **pinch-drag = tune energy (relative)**, with magnetic snap to available transition energies and a settle window distinguishing tap from drag.

### Recommended spatial mapping (you have latitude here)

- **Fire a photon — pinch toward the atom.** A pinch (thumb–index) that releases without travel fires one photon from a **light-source object** toward the atom. Make it physical: a small handheld/anchored **emitter** the user aims; pinch-flick "throws" a photon wave-packet (port `photon.js` glyph into 3D — a short sinusoidal wave-packet colored by `wavelengthToRGB`). Keep the **tap-vs-drag discrimination** from 2D: a brief settle window after pinch-onset so the act of pinching doesn't read as a drag.
- **Tune wavelength/energy — pinch + drag, RELATIVE.** On pinch-and-move (past a small threshold, after the settle window), scrub photon energy **from its current value** (do **not** snap the value to hand position — this was an explicit design decision). Map hand displacement along a chosen axis → ΔE at a fixed sensitivity. **Magnetically snap** to the transition energies available from the current level (and the ionization edge) when within a small tolerance, exactly as `tuneFromPointer` / `TUNE.snap` do. A spatial **dial/knob** grabbed and twisted is an acceptable alternative — relative either way.
- **Direct manipulation of the atom:** one-hand pinch-drag to **rotate**, two-hand pinch to **scale**, so the user can orbit and zoom the cloud. (The quantization z-axis matters for m-eigenstate shapes — let them reorient to see the lobes/tori.)
- **Feedback loop:** the energy bracket on the diagram turns green when the dialed energy matches a real gap from the current level — this is the "aha" moment; keep it tight and immediate. On a successful absorption, animate the cloud morphing to the new orbital; on emission, spawn an outgoing photon of the emitted wavelength and log it in the spectrometer.

`⚠️ VERIFY` the exact hand-tracking / gesture APIs (ARKit `HandTrackingProvider` for skeletal joints; `SpatialEventGesture` / system pinch for indirect input; RealityKit gesture components). Prefer the **system pinch** for reliability where it suffices, and skeletal hand joints only where you need richer spatial aiming.

---

## 11. Fidelity & provenance

- Physics ported from this repo's `physics.js` / `models.js`, themselves ported from `Materials_At_Scale/Prototypes/H/research/H_physics_reference.md` and the Python prototype `H/h_interactive.py`. Constants CODATA-2018.
- **Exact:** energy spectrum `E_n = −13.606/n²`; transition energies/wavelengths; dipole selection rules Δℓ=±1, Δm≤1; radial wavefunctions `R_nℓ` (associated Laguerre, verified node counts & central behavior); angular `|Y_ℓm|²` (associated Legendre, verified shapes).
- **Modeled / approximate (state clearly in-app if you keep the "fidelity note"):** radiative lifetimes use the `0.2·n³ ns` np-channel scaling (relative timing accurate; not ℓ-resolved — so 2s metastability is not separately modeled); emission branching picks uniformly among dipole-allowed lower states (not weighted by true branching ratios); ionization→recombination delay is a fixed visual delay, not a density-dependent rate; absorption tolerance `TOL` is a UX window, not a natural linewidth.

---

## 12. Build checklist for the Xcode agent

1. **Math core (portable, test first):** port `laguerre`, `assocLegendre`, `psi2`, `energyLevel`, transition table, `dipoleAllowed`, `sampleDwellSeconds`, `wavelengthToRGB`. Unit-test against the verified numbers in §3–§5 (energy table, transition λ's, Laguerre closed forms, node counts, `psi2(0,0,0)` finite for s & zero for ℓ>0).
2. **Volume generation:** Metal compute (or CPU) → normalized 3D `|ψ_nℓm|²` texture; regenerate on state change.
3. **Raymarch spike (highest risk):** minimal `ShaderGraphMaterial` raymarch of a test 3D texture in a `.mixed` ImmersiveSpace. Validate before building further; fall back to CompositorServices/Metal only if necessary.
4. **State machine:** absorption (resonant + ionization), emission cascade (Δℓ=±1, Δm rule, n³ exponential lifetimes), recombination; transition cross-fade animation.
5. **Embodiment:** photon-fire pinch (tap-vs-drag settle), relative energy tuning with magnetic snap, atom grab/rotate/scale.
6. **Panels:** energy diagram (with green-match bracket), spectrometer, time-dilation + real-time clock, state label.
7. **Dual presentation:** confirm mixed (passthrough) and full immersion both render the volume correctly; expose an environment toggle.
8. **Scale & placement:** `aWorld ≈ 3.8 mm`, `Rbox ≈ 0.25 m`, comfortable spawn, scale handle.

---

*Questions for the product owner that may arise during build:* (a) want the optional **real-orbital** display mode (§6.4)? (b) want the **2s-metastable** special case surfaced (§6.5)? (c) target visionOS version (affects raymarch path in §7)? — flagged here so they can be raised rather than guessed.
