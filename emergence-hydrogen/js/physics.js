/* =============================================================================
 * physics.js — Hydrogen atom physics
 * Ported from Materials_At_Scale/Prototypes/H/research/H_physics_reference.md
 * All energies in eV, wavelengths in nm. CODATA 2018 constants.
 * ===========================================================================*/

const HC_EV_NM = 1239.841984;     // h*c in eV·nm  -> lambda(nm) = HC / E(eV)
const RYDBERG_EV = 13.605693;     // |E_1|, hydrogen ionization energy (eV)

// Energy of level n:  E_n = -13.606 / n^2  (eV)
function energyLevel(n) {
  return -RYDBERG_EV / (n * n);
}

// Photon energy (eV) for a transition n_lo -> n_hi (absorption, n_hi > n_lo)
function transitionEnergy(nLow, nHigh) {
  return energyLevel(nHigh) - energyLevel(nLow); // positive
}

// Convert between photon energy (eV) and wavelength (nm)
function energyToWavelength(eV) { return HC_EV_NM / eV; }
function wavelengthToEnergy(nm) { return HC_EV_NM / nm; }

// Bohr orbit radius scales as n^2 (in units of the Bohr radius a0)
function orbitRadius(n) { return n * n; }

// --- Spectral series names (for labeling) ---------------------------------
const SERIES = {
  1: { name: 'Lyman',   band: 'UV' },
  2: { name: 'Balmer',  band: 'visible' },
  3: { name: 'Paschen', band: 'IR' },
  4: { name: 'Brackett', band: 'IR' },
  5: { name: 'Pfund',   band: 'IR' },
};

// Greek suffix for the first few lines of a series (alpha, beta, ...)
const GREEK = ['α', 'β', 'γ', 'δ', 'ε', 'ζ'];

// Build the full transition table for n = 1..NMAX.
// Each entry: {nLow, nHigh, dE (eV), lambda (nm), series, label}
const NMAX = 6;
function buildTransitions(nMax = NMAX) {
  const list = [];
  for (let lo = 1; lo < nMax; lo++) {
    for (let hi = lo + 1; hi <= nMax; hi++) {
      const dE = transitionEnergy(lo, hi);
      const lambda = energyToWavelength(dE);
      const series = SERIES[lo] ? SERIES[lo].name : `n=${lo}`;
      const greek = GREEK[hi - lo - 1] || `(${hi})`;
      list.push({
        nLow: lo, nHigh: hi, dE, lambda,
        series, band: SERIES[lo] ? SERIES[lo].band : 'IR',
        label: `${lo}→${hi}`,
        seriesLabel: `${series} ${greek}`,
      });
    }
  }
  return list;
}

const TRANSITIONS = buildTransitions();

// Transitions that START from a given level n (i.e. absorption from n)
function absorptionsFrom(n, nMax = NMAX) {
  return TRANSITIONS.filter(t => t.nLow === n && t.nHigh <= nMax);
}

// Emission options when an electron is at level n (drops to any lower level)
function emissionsFrom(n) {
  return TRANSITIONS.filter(t => t.nHigh === n);
}

// Does a photon of energy `eV` match a transition from level n?
// Returns the matched transition or null. `tolEV` is the absorption window.
function matchAbsorption(n, photonEV, tolEV = 0.08, nMax = NMAX) {
  let best = null, bestErr = Infinity;
  for (const t of absorptionsFrom(n, nMax)) {
    const err = Math.abs(t.dE - photonEV);
    if (err < tolEV && err < bestErr) { best = t; bestErr = err; }
  }
  return best;
}

// Ionization: a photon with energy >= |E_n| frees the electron from level n.
function ionizes(n, photonEV) {
  return photonEV >= -energyLevel(n) - 1e-6;
}

// --- Schrödinger model: (n, l, m) sub-states & dipole selection rules ------
// Selection rules for electric-dipole transitions: Δl = ±1, |Δm| <= 1.
function dipoleAllowed(l1, m1, l2, m2) {
  return Math.abs(l2 - l1) === 1 && Math.abs(m2 - m1) <= 1;
}

// All (l, m) sub-states available at level n
function subStates(n) {
  const out = [];
  for (let l = 0; l < n; l++)
    for (let m = -l; m <= l; m++) out.push({ l, m });
  return out;
}

const ORBITAL_LETTER = { 0: 's', 1: 'p', 2: 'd', 3: 'f' };

// --- Excited-state lifetimes & simulation time scale -----------------------
// Spontaneous emission is a memoryless (Poisson) process, so the time an
// electron sits in an excited level is EXPONENTIALLY distributed, with a mean
// equal to that level's radiative lifetime. Real hydrogen electric-dipole
// lifetimes for the dominant np channel scale ≈ 0.2 ns × n³ (anchored to the
// measured 2p lifetime of 1.6 ns):  2→1.6, 3→5.4, 4→12.8, 5→25, 6→43 ns.
// Consequence: higher levels live LONGER, so a cascade lingers up high and
// drops fast through the low levels — the opposite of a uniform dwell timer.
function levelLifetimeNs(n) {
  return 0.2 * n * n * n;
}

// Map real time onto on-screen frames (the sim steps ~60 frames/s). Anchored
// for watchability: the longest level (~43 ns at n=6) lasts a few seconds.
const TIME_FRAMES_PER_NS = 7;                       // sim frames per ns of real time
const REAL_NS_PER_FRAME  = 1 / TIME_FRAMES_PER_NS;  // real ns advanced per frame
const REAL_NS_PER_SCREEN_SEC = REAL_NS_PER_FRAME * 60;          // ns of reality per on-screen second
const TIME_SLOWDOWN = 1 / (REAL_NS_PER_SCREEN_SEC * 1e-9);      // how many× slower than reality

// Exponentially-distributed dwell (in frames) for an electron at level n.
function sampleLevelDwellFrames(n) {
  const mean = levelLifetimeNs(n) * TIME_FRAMES_PER_NS;
  const u = Math.max(1e-6, Math.random());
  return Math.min(mean * 4, -Math.log(u) * mean);   // cap the rare long tail
}
