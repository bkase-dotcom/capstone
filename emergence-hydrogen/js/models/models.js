/* =============================================================================
 * models.js — the six PhET "Models of the Hydrogen Atom"
 *   Classical : Billiard Ball, Plum Pudding, Classical Solar System
 *   Quantum   : Bohr, de Broglie, Schrödinger
 *
 * Common interface (all positions relative to atom centre cx,cy):
 *   reset()
 *   update(dt, emit)         emit(wavelengthNm, dirAngle) spawns an emitted photon
 *   tryAbsorb(photon)        -> true if the photon is consumed
 *   draw(g, cx, cy)
 *   electronN                current level (quantum models) or null
 *   blurb                    one-line description for the info panel
 * ===========================================================================*/

// ---- helper: map level n -> drawing radius in px -------------------------
function levelRadiusPx(n, boxR, minR = 26) {
  const t = (n * n - 1) / (NMAX * NMAX - 1);
  return minR + (boxR - minR) * t;
}

// =============================================================================
// Base class
// =============================================================================
class HydrogenModel {
  constructor() { this.electronN = null; this.absorbRadius = 60; }
  reset() {}
  update(dt, emit) {}
  tryAbsorb(photon) { return false; }
  draw(g, cx, cy) {}
  drawNucleus(g, cx, cy, r = 7) {
    g.noStroke();
    g.fill(255, 90, 80); g.circle(cx, cy, r * 2);
    g.fill(255, 180, 170, 180); g.circle(cx, cy, r);
  }
}

// =============================================================================
// CLASSICAL 1 — Billiard Ball : solid sphere, photons bounce off
// =============================================================================
class BilliardBallModel extends HydrogenModel {
  constructor() { super(); this.r = 46; this.flash = 0; this.blurb =
    'Billiard Ball — the atom as a hard sphere. Light just bounces off; nothing is absorbed.'; }
  update(dt) { this.flash = Math.max(0, this.flash - 0.06 * dt); }
  tryAbsorb(photon, cx, cy) {
    // handled in sketch via reflect(); never absorbs
    return false;
  }
  draw(g, cx, cy) {
    g.push();
    g.noStroke();
    for (let i = 6; i > 0; i--) {
      g.fill(120, 130, 170, 12 * i);
      g.circle(cx, cy, this.r * 2 + i * 4);
    }
    g.fill(150, 160, 200); g.circle(cx, cy, this.r * 2);
    g.fill(210, 220, 245); g.circle(cx - this.r * 0.3, cy - this.r * 0.3, this.r * 0.9);
    if (this.flash > 0) { g.fill(255, 255, 255, 160 * this.flash); g.circle(cx, cy, this.r * 2); }
    g.pop();
  }
}

// =============================================================================
// CLASSICAL 2 — Plum Pudding : electron in SHM inside positive jelly;
// absorbs a photon, vibrates, then re-emits the same wavelength.
// =============================================================================
class PlumPuddingModel extends HydrogenModel {
  constructor() {
    super(); this.R = 48;
    this.phase = 0; this.amp = 0; this.axis = 0;
    this.storedNm = null; this.emitTimer = 0;
    this.blurb = 'Plum Pudding — electron embedded in positive charge. Absorbs light, vibrates, then re-emits it.';
  }
  reset() { this.amp = 0; this.storedNm = null; this.emitTimer = 0; }
  update(dt, emit) {
    this.phase += 0.18 * dt;
    if (this.amp > 0) this.amp *= Math.pow(0.992, dt);
    if (this.storedNm !== null) {
      this.emitTimer -= dt;
      if (this.emitTimer <= 0) {
        emit(this.storedNm, Math.random() * Math.PI * 2);
        this.storedNm = null; this.amp *= 0.4;
      }
    }
  }
  tryAbsorb(photon) {
    if (this.storedNm !== null) return false;       // already excited
    this.storedNm = photon.wavelength;
    this.amp = this.R * 0.7;
    this.axis = Math.random() * Math.PI * 2;
    this.emitTimer = 50 + Math.random() * 50;
    return true;
  }
  draw(g, cx, cy) {
    g.push(); g.noStroke();
    for (let i = 5; i > 0; i--) { g.fill(120, 90, 200, 18 * i); g.circle(cx, cy, this.R * 2 + i * 3); }
    g.fill(110, 80, 190, 120); g.circle(cx, cy, this.R * 2);
    const off = Math.sin(this.phase) * this.amp;
    const ex = cx + Math.cos(this.axis) * off, ey = cy + Math.sin(this.axis) * off;
    g.fill(120, 200, 255); g.circle(ex, ey, 12);
    g.fill(220, 240, 255); g.circle(ex, ey, 5);
    g.pop();
  }
}

// =============================================================================
// CLASSICAL 3 — Classical Solar System : electron spirals in, radiating
// continuously (the classical catastrophe), then resets.
// =============================================================================
class SolarSystemModel extends HydrogenModel {
  constructor(boxR) {
    super(); this.boxR = boxR;
    this.reset();
    this.blurb = 'Classical Solar System — a planet-electron must radiate energy, spiral in, and collapse. (It can\'t — that\'s why classical physics fails.)';
  }
  reset() { this.r = this.boxR * 0.92; this.theta = 0; this.emitAcc = 0; this.dead = false; this.deadT = 0; }
  update(dt, emit) {
    if (this.dead) { this.deadT -= dt; if (this.deadT <= 0) this.reset(); return; }
    const omega = 0.04 * Math.sqrt((this.boxR * 0.92) ** 3 / Math.max(this.r, 8) ** 3);
    this.theta += omega * dt;
    this.r -= 0.45 * dt * (1 - this.r / (this.boxR * 1.1));   // accelerating infall
    this.emitAcc += dt;
    if (this.emitAcc > 7) {                                   // continuous radiation
      this.emitAcc = 0;
      const wl = 200 + (this.r / this.boxR) * 600;            // bluer as it falls in
      emit(wl, Math.random() * Math.PI * 2);
    }
    if (this.r <= 10) { this.dead = true; this.deadT = 35; }
  }
  draw(g, cx, cy) {
    g.push(); g.noStroke();
    g.stroke(90, 100, 140, 90); g.noFill(); g.strokeWeight(1);
    g.circle(cx, cy, this.r * 2);
    if (!this.dead) {
      const ex = cx + Math.cos(this.theta) * this.r, ey = cy + Math.sin(this.theta) * this.r;
      g.noStroke(); g.fill(120, 200, 255); g.circle(ex, ey, 12);
      g.fill(220, 240, 255); g.circle(ex, ey, 5);
    } else {
      g.noStroke(); g.fill(255, 230, 120, 200); g.circle(cx, cy, 22);
    }
    this.drawNucleus(g, cx, cy);
    g.pop();
  }
}

// =============================================================================
// Quantum base — discrete levels, resonant absorption, spontaneous emission
// =============================================================================
class QuantumModel extends HydrogenModel {
  constructor(boxR) {
    super(); this.boxR = boxR; this.electronN = 1;
    this.emitTimer = 0; this.jumpAnim = 1; this.prevR = 0;
    this.ionized = false; this.ionTimer = 0;
  }
  reset() { this.electronN = 1; this.emitTimer = 0; this.jumpAnim = 1; this.ionized = false; }

  radiusFor(n) { return levelRadiusPx(n, this.boxR); }

  // pick an emission target (overridden by Schrödinger for selection rules)
  emissionTarget() {
    const lower = [];
    for (let nf = 1; nf < this.electronN; nf++) lower.push(nf);
    return lower[Math.floor(Math.random() * lower.length)];
  }

  tryAbsorb(photon) {
    if (this.ionized) return false;
    if (ionizes(this.electronN, photon.energy) &&
        !matchAbsorption(this.electronN, photon.energy, 0.08)) {
      this.ionized = true; this.ionTimer = 55; return true;
    }
    const t = matchAbsorption(this.electronN, photon.energy, 0.08);
    if (t) {
      this.prevR = this.radiusFor(this.electronN);
      this.electronN = t.nHigh;
      this.jumpAnim = 0;
      this.emitTimer = sampleLevelDwellFrames(this.electronN);
      return true;
    }
    return false;
  }

  update(dt, emit) {
    if (this.jumpAnim < 1) this.jumpAnim = Math.min(1, this.jumpAnim + 0.08 * dt);

    if (this.ionized) {
      this.ionTimer -= dt;
      // recombination: a free electron is recaptured into the top level, then
      // cascades down. (The recombination delay itself is not a radiative
      // lifetime — in a real gas it depends on density — so it stays fixed.)
      if (this.ionTimer <= 0) { this.ionized = false; this.electronN = NMAX; this.emitTimer = sampleLevelDwellFrames(NMAX); }
      return;
    }
    if (this.electronN > 1) {
      this.emitTimer -= dt;
      if (this.emitTimer <= 0) {
        const nf = this.emissionTarget();
        if (nf != null) {
          const dE = energyLevel(this.electronN) - energyLevel(nf);
          emit(energyToWavelength(dE), Math.random() * Math.PI * 2);
          this.prevR = this.radiusFor(this.electronN);
          this.electronN = nf; this.jumpAnim = 0;
          this.emitTimer = sampleLevelDwellFrames(this.electronN);
        }
      }
    }
  }

  currentRadius() {
    const target = this.radiusFor(this.electronN);
    return this.prevR + (target - this.prevR) * this.jumpAnim;
  }
}

// =============================================================================
// QUANTUM 1 — Bohr : electron as a dot on a quantized circular orbit
// =============================================================================
class BohrModel extends QuantumModel {
  constructor(boxR) { super(boxR); this.theta = 0;
    this.blurb = 'Bohr — electron on quantized orbits. It only absorbs photons whose energy exactly bridges two levels.'; }
  update(dt, emit) { super.update(dt, emit); this.theta += 0.05 * dt; }
  draw(g, cx, cy) {
    g.push();
    // faint allowed orbits
    g.noFill();
    for (let n = 1; n <= NMAX; n++) {
      const r = this.radiusFor(n);
      g.stroke(90, 100, 140, n === this.electronN ? 0 : 70);
      g.strokeWeight(1); g.circle(cx, cy, r * 2);
    }
    // current orbit highlighted
    const r = this.currentRadius();
    g.stroke(255, 210, 70, 160); g.strokeWeight(1.6); g.circle(cx, cy, r * 2);
    // electron
    const ex = cx + Math.cos(this.theta) * r, ey = cy + Math.sin(this.theta) * r;
    g.noStroke();
    g.fill(120, 200, 255, 120); g.circle(ex, ey, 18);
    g.fill(150, 215, 255); g.circle(ex, ey, 11);
    g.fill(230, 245, 255); g.circle(ex, ey, 5);
    this.drawNucleus(g, cx, cy);
    g.pop();
  }
}

// =============================================================================
// QUANTUM 2 — de Broglie : electron as a standing wave around the orbit
// (number of wavelengths around the ring = n)
// =============================================================================
class DeBroglieModel extends QuantumModel {
  constructor(boxR) { super(boxR); this.phase = 0;
    this.blurb = 'de Broglie — the electron is a standing matter-wave; only orbits fitting a whole number of wavelengths survive.'; }
  update(dt, emit) { super.update(dt, emit); this.phase += 0.12 * dt; }
  draw(g, cx, cy) {
    g.push();
    g.noFill();
    for (let n = 1; n <= NMAX; n++) {
      g.stroke(90, 100, 140, 50); g.strokeWeight(1);
      g.circle(cx, cy, this.radiusFor(n) * 2);
    }
    const r = this.currentRadius();
    const n = this.electronN;
    const c = wavelengthToRGB(550);
    g.stroke(150, 215, 255); g.strokeWeight(2); g.noFill();
    g.beginShape();
    for (let a = 0; a <= Math.PI * 2 + 0.05; a += 0.06) {
      const amp = 9 * Math.sin(n * a + this.phase);
      const rr = r + amp;
      g.vertex(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr);
    }
    g.endShape();
    this.drawNucleus(g, cx, cy);
    g.pop();
  }
}

// =============================================================================
// QUANTUM 3 — Schrödinger : (n,l,m) probability cloud, dipole selection rules
// =============================================================================
const SCHROD_GRID = 192;        // density-field resolution (upscaled when drawn)
let SCHROD_FIELD = null;        // shared offscreen buffer (one model active at a time)

// Generalized (associated) Laguerre polynomial L_k^alpha(x) by the standard
// three-term recurrence. Used in the exact hydrogen radial wavefunction.
function laguerre(k, alpha, x) {
  if (k <= 0) return 1;
  let lkm1 = 1;                 // L_0^alpha
  let lk = 1 + alpha - x;       // L_1^alpha
  for (let i = 1; i < k; i++) {
    const lkp1 = ((2 * i + 1 + alpha - x) * lk - (i + alpha) * lkm1) / (i + 1);
    lkm1 = lk; lk = lkp1;
  }
  return lk;
}

class SchrodingerModel extends QuantumModel {
  constructor(boxR) {
    super(boxR);
    this.l = 0; this.m = 0;
    // Bohr radius in pixels. Chosen so the largest state (n=NMAX) fills the box;
    // smaller n are genuinely smaller (true ∝n² scaling). Tune the divisor to
    // zoom the whole family in/out.
    this.aPx = boxR / 50;
    if (!SCHROD_FIELD) { SCHROD_FIELD = createGraphics(SCHROD_GRID, SCHROD_GRID); SCHROD_FIELD.pixelDensity(1); }
    this.field = SCHROD_FIELD;
    this._rebuild();
    this.blurb = 'Schrödinger — electron as a 3-D probability cloud (n,ℓ,m). Transitions obey the dipole rule Δℓ=±1.';
  }
  reset() { super.reset(); this.l = 0; this.m = 0; this._rebuild(); }

  // angular probability |Y_lm|^2 approximation in the x–z slice (theta from +z)
  _angular(l, m, theta) {
    const c = Math.cos(theta), s = Math.sin(theta);
    if (l === 0) return 1;
    if (l === 1) return m === 0 ? c * c : s * s;
    if (l === 2) {
      if (m === 0) return (3 * c * c - 1) ** 2;
      if (Math.abs(m) === 1) return (s * c) ** 2;
      return s ** 4;
    }
    if (l === 3) {
      if (m === 0) return (5 * c ** 3 - 3 * c) ** 2;
      if (Math.abs(m) === 1) return (s * (5 * c * c - 1)) ** 2;
      if (Math.abs(m) === 2) return (s * s * c) ** 2;
      return s ** 6;
    }
    return 1;
  }

  // Exact hydrogen radial density |R_nl(r)|² (up to a constant; normalized
  // later). R_nl ∝ ρ^l e^{-ρ/2} L_{n-l-1}^{2l+1}(ρ) with ρ = 2r/(n·a), so
  // |R_nl|² ∝ ρ^{2l} e^{-ρ} [L]². This gives the true behavior: s-states peak
  // at the nucleus, p/d/f vanish there as r^{2l}, n-l-1 unevenly-spaced radial
  // nodes, and a dominant outermost lobe.
  _radialDensity(r, n, l) {
    const rho = 2 * r / (n * this.aPx);
    const lag = laguerre(n - l - 1, 2 * l + 1, rho);
    return Math.pow(rho, 2 * l) * Math.exp(-rho) * lag * lag;
  }

  // paint |ψ|² as a smooth density field into the offscreen buffer. The cloud
  // is azimuthally symmetric about the z-axis, so the x–z cross-section (here:
  // screen x = distance from axis, screen y = -z) is the whole story.
  _rebuild() {
    const n = this.electronN, l = this.l, m = this.m;
    const G = SCHROD_GRID, half = this.boxR;   // buffer spans [-boxR, boxR]
    const dens = new Float32Array(G * G);
    let max = 1e-6;
    for (let j = 0; j < G; j++) {
      const dz = (1 - (j + 0.5) / G * 2) * half;   // +z at the top
      for (let i = 0; i < G; i++) {
        const dx = ((i + 0.5) / G * 2 - 1) * half;
        const r = Math.hypot(dx, dz);
        const theta = r < 1e-6 ? 0 : Math.acos(dz / r);
        const d = this._radialDensity(r, n, l) * this._angular(l, m, theta);
        dens[j * G + i] = d;
        if (d > max) max = d;
      }
    }
    // map normalized density -> a soft blue→cyan→white glow (alpha = intensity)
    const f = this.field;
    f.loadPixels();
    for (let k = 0; k < G * G; k++) {
      const t = Math.pow(dens[k] / max, 0.55);     // gamma softens the falloff
      const idx = k * 4;
      f.pixels[idx]     = 60 + 185 * t;            // R
      f.pixels[idx + 1] = 130 + 120 * t;           // G
      f.pixels[idx + 2] = 230 + 25 * t;            // B
      f.pixels[idx + 3] = 235 * t;                 // A
    }
    f.updatePixels();
  }

  emissionTarget() {
    // choose a lower (n',l') obeying Δl = ±1, then set l/m
    const opts = [];
    for (let nf = 1; nf < this.electronN; nf++)
      for (let lf = 0; lf < nf; lf++)
        if (dipoleAllowed(this.l, this.m, lf, this.m)) opts.push({ nf, lf });
    if (!opts.length) return null;
    const pick = opts[Math.floor(Math.random() * opts.length)];
    this._pendingL = pick.lf;
    return pick.nf;
  }

  tryAbsorb(photon) {
    if (this.ionized) return false;
    const t = matchAbsorption(this.electronN, photon.energy, 0.08);
    if (t) {
      // need an upper l with Δl=±1 available at nHigh
      const ls = [];
      for (let lf = 0; lf < t.nHigh; lf++) if (dipoleAllowed(this.l, this.m, lf, this.m)) ls.push(lf);
      if (!ls.length) return false;
      this.l = ls[Math.floor(Math.random() * ls.length)];
      this.electronN = t.nHigh; this.jumpAnim = 0;
      this.emitTimer = sampleLevelDwellFrames(this.electronN); this._rebuild();
      return true;
    }
    if (ionizes(this.electronN, photon.energy)) { this.ionized = true; this.ionTimer = 55; return true; }
    return false;
  }

  update(dt, emit) {
    const before = this.electronN;
    super.update(dt, emit);
    if (this.electronN !== before) {
      if (this._pendingL != null) { this.l = this._pendingL; this._pendingL = null; }
      this.m = Math.max(-this.l, Math.min(this.l, this.m));
      this._rebuild();
    }
  }

  draw(g, cx, cy) {
    g.push();
    // faint level rings
    for (let n = 1; n <= NMAX; n++) { g.noFill(); g.stroke(90,100,140,25); g.strokeWeight(1); g.circle(cx,cy,this.radiusFor(n)*2); }
    // smooth probability cloud — additive blend gives it a soft glow; the
    // low-res field is bilinearly upscaled, so it reads as a continuous cloud
    g.push();
    g.imageMode(CENTER);
    g.blendMode(ADD);
    g.image(this.field, cx, cy, this.boxR * 2, this.boxR * 2);
    g.blendMode(BLEND);
    g.pop();
    this._drawProton(g, cx, cy);
    // state label
    g.noStroke(); g.fill(200, 210, 235); g.textAlign(CENTER, TOP); g.textSize(12);
    g.text(`${this.electronN}${ORBITAL_LETTER[this.l] || '?'}  m=${this.m}`, cx, cy + this.boxR + 6);
    g.pop();
  }

  // To-scale proton. Its charge radius (~0.84 fm) is ~1.6e-5 of the Bohr radius
  // (~0.529 Å), so at our pixel scale it's ~10^-4 px — far below one pixel. We
  // floor it to a single pixel so it's locatable; even this is ~10^4× too big.
  // It stays a fixed point while the electron cloud grows with n — as in reality.
  _drawProton(g, cx, cy) {
    const PROTON_OVER_BOHR = 1.6e-5;
    const r = Math.max(0.5, this.aPx * PROTON_OVER_BOHR);   // realistic → sub-pixel, floored
    g.noStroke();
    g.fill(255, 70, 60); g.circle(cx, cy, r * 2);
  }
}

// ---- registry ------------------------------------------------------------
function buildModels(boxR) {
  return {
    billiard: { label: 'Billiard Ball', type: 'classical', make: () => new BilliardBallModel() },
    plum:     { label: 'Plum Pudding',  type: 'classical', make: () => new PlumPuddingModel() },
    solar:    { label: 'Solar System',  type: 'classical', make: () => new SolarSystemModel(boxR) },
    bohr:     { label: 'Bohr',          type: 'quantum',   make: () => new BohrModel(boxR) },
    debroglie:{ label: 'de Broglie',    type: 'quantum',   make: () => new DeBroglieModel(boxR) },
    schrod:   { label: 'Schrödinger',   type: 'quantum',   make: () => new SchrodingerModel(boxR) },
  };
}
