# Models of the Hydrogen Atom — gesture edition

An interactive, physics-accurate recreation of PhET's
[*Models of the Hydrogen Atom*](https://phet.colorado.edu/sims/html/models-of-the-hydrogen-atom/latest/models-of-the-hydrogen-atom_all.html),
rebuilt in **p5.js** with **webcam hand-gesture input** (via ml5.js `handPose`,
which wraps Google MediaPipe Hands).

This is an **Emergence** prototype — a fast, cheap way to feel out the embodied
interaction language (reach in, tune, fire) before committing it to a visionOS
experience and, ultimately, to *Plenum*'s interactive-hologram hardware. The aim
is the same as the capstone's: let a non-expert *perceive* quantum behavior by
manipulating it directly, rather than reading equations about it.

## What it does

A light source fires photons at a hydrogen atom. You choose an atomic model and
watch how each one responds to light:

- **Classical** — Billiard Ball (light bounces), Plum Pudding (absorb → vibrate →
  re-emit), Classical Solar System (the electron spirals in and collapses — the
  classical catastrophe).
- **Quantum** — Bohr (quantized orbits), de Broglie (standing matter-wave),
  Schrödinger (n, ℓ, m probability cloud with the Δℓ = ±1 dipole selection rule).

For the quantum models, a photon is **absorbed only when its energy matches a
gap between levels** (n=1→2 = 10.2 eV / 121.6 nm, 1→3 = 12.09 eV, …). The electron
jumps up, then spontaneously emits its way back down; emitted wavelengths
accumulate in the spectrometer.

## The gesture language

Designed to transfer in spirit to visionOS pinch interactions:

| Gesture | Action |
|---|---|
| **Quick pinch** (tap) | Fire one photon at the atom |
| **Pinch + drag** | Scrub the photon's energy. It **magnetically snaps** to the transition energies available from the electron's current level — line it up with 1→2, 1→3, 1→4 … |

Mouse fallback (works without a webcam): **click** = fire, **click-drag** = tune.
Keyboard: `space` pause, `f` fire, `r` reset atom.

The energy-level diagram (right) shows the dialed photon energy as a bracket
rising from the current level; it turns **green ✓** when you've matched a real
transition. The tuning ruler along the bottom marks each transition.

## Run it

It's plain static files — no build step.

```bash
cd emergence-hydrogen
python3 -m http.server 8000
# open http://localhost:8000
```

Then click **Hand tracking: off → ON** and grant camera access to use gestures.
(Camera requires `localhost` or HTTPS — opening `index.html` via `file://` works
for mouse mode but the webcam will be blocked.)

Optional: `?model=bohr|schrod|debroglie|billiard|plum|solar` to pick the starting
model, e.g. `http://localhost:8000/?model=schrod`.

## Tech

- **p5.js 1.11** — rendering & input
- **ml5.js 1.x `handPose`** — in-browser hand tracking (21 landmarks, wraps
  MediaPipe Hands); pinch = normalized thumb–index distance with hysteresis
- both loaded from CDN; no dependencies to install

## Physics provenance

Energy levels, transition wavelengths, and selection rules are ported from the
project's existing physics reference
(`Materials_At_Scale/Prototypes/H/research/H_physics_reference.md`) and the Python
prototype `H/h_interactive.py`. Constants are CODATA 2018.

> Fidelity note: this is a *prototype*. The Schrödinger cloud uses an approximate
> angular/radial envelope for real-time rendering, not exact wavefunction
> sampling; energies use the exact non-relativistic spectrum E_n = −13.606/n² eV.

## File map

```
index.html            page shell + CDN scripts + control bars
style.css             dark UI styling
js/physics.js         energy levels, transitions, selection rules, conversions
js/spectrum.js        wavelength → RGB
js/photon.js          travelling wave-packet glyph
js/gun.js             light source (monochromatic / white)
js/energyDiagram.js   energy-level diagram + photon-energy bracket
js/spectrometer.js    emitted-wavelength histogram
js/models/models.js   the six atom models (shared base + per-model behavior)
js/hands.js           ml5 handPose → unified pinch pointer
js/ui.js              HTML control bars + shared UI state
js/sketch.js          layout, gesture state machine, simulation loop
```
