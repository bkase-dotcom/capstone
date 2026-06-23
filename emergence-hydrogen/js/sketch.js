/* =============================================================================
 * sketch.js — Models of the Hydrogen Atom (gesture edition)
 * Emergence prototype · p5.js + ml5 handPose
 * ===========================================================================*/

// ---- layout ---------------------------------------------------------------
const W = 1180, H = 720;
const BOX = { x: 300, y: 80, s: 480 };
let CX, CY, BOXR;
const GUN_X = 232;
const DIA = { x: 820, y: 80, w: 340, h: 405 };
const SPEC = { x: 820, y: 505, w: 340, h: 165 };
const CAM = { x: 20, y: 80, w: 176 };

// ---- energy tuning band ---------------------------------------------------
const TUNE = { x0: 120, x1: 1060, eMin: 0.4, eMax: 13.7, snap: 0.18 };

// ---- state ----------------------------------------------------------------
let MODELS, model, gun, diagram, spectrometer, hands;
let photons = [];
let press = { active: false, sx: 0, sy: 0, dragging: false };
let tuningGlow = 0;
let realTimeNs = 0;             // compressed "real" time elapsed since reset (ns)
let slider, wlReadout;

// The simulation is authored in a fixed 1180x720 design space; `view` scales &
// centers that design into the live (window-sized) canvas so it fills the
// screen. All pointer math happens in design space, so the hand and mouse line
// up with the rendered UI regardless of window size.
let view = { s: 1, ox: 0, oy: 0 };

function layout() {
  const top = document.getElementById('toolbar').offsetHeight;
  const bot = document.getElementById('bottombar').offsetHeight;
  const availW = windowWidth;
  const availH = Math.max(1, windowHeight - top - bot);
  view.s = Math.min(availW / W, availH / H);   // uniform scale (letterbox)
  view.ox = (availW - W * view.s) / 2;
  view.oy = top + (availH - H * view.s) / 2;
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  layout();
}

function setup() {
  const c = createCanvas(windowWidth, windowHeight);
  c.parent('stage');
  CX = BOX.x + BOX.s / 2;
  CY = BOX.y + BOX.s / 2;
  BOXR = BOX.s / 2 - 34;

  MODELS = buildModels(BOXR);
  gun = new LightGun(GUN_X, CY);
  diagram = new EnergyDiagram(DIA.x, DIA.y, DIA.w, DIA.h);
  spectrometer = new Spectrometer(SPEC.x, SPEC.y, SPEC.w, SPEC.h);
  hands = new HandTracker();

  // optional ?model=bohr|schrod|debroglie|billiard|plum|solar
  const qModel = new URLSearchParams(window.location.search).get('model');
  if (qModel && MODELS[qModel]) UI.model = qModel;

  buildUI(MODELS);
  setActiveModel(UI.model);

  UI.onModelChange = setActiveModel;
  UI.onReset = () => { model.reset(); realTimeNs = 0; };
  UI.onClear = () => spectrometer.clear();
  UI.onToggleHand = toggleHand;

  slider = document.getElementById('wavelength');
  wlReadout = document.getElementById('wl-readout');
  slider.min = LightGun.MIN_NM; slider.max = LightGun.MAX_NM; slider.step = 0.5;
  slider.value = gun.wavelength;
  slider.addEventListener('input', () => gun.setWavelength(parseFloat(slider.value)));

  textFont('monospace');
  layout();   // size the design viewport now that the control bars exist
}

function setActiveModel(key) {
  model = MODELS[key].make();
  photons = [];
  realTimeNs = 0;
}

function toggleHand() {
  if (!hands.enabled) {
    setHandButton('loading');
    hands.enable(() => setHandButton('on'));
    UI.handTracking = true;
    setTimeout(() => { if (hands.error) setHandButton('error'); }, 400);
  } else {
    hands.disable(); UI.handTracking = false; setHandButton('off');
  }
}

// ---------------------------------------------------------------------------
// Unified pointer (hand if tracking & present, else mouse)
// ---------------------------------------------------------------------------
function getPointer() {
  if (hands.enabled && hands.ready && hands.present) {
    return { x: hands.x, y: hands.y, down: hands.pinch, src: 'hand', present: true };
  }
  // window-space mouse → design space (inverse of the view transform)
  const mx = (mouseX - view.ox) / view.s, my = (mouseY - view.oy) / view.s;
  const inside = mx >= 0 && mx <= W && my >= 0 && my <= H;
  return { x: mx, y: my, down: mouseIsPressed && mouseButton === LEFT && inside,
           src: 'mouse', present: inside };
}

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------
function draw() {
  background(14, 16, 30);
  if (hands.enabled) hands.update();

  const ptr = getPointer();
  handleGesture(ptr);

  const dt = UI.paused ? 0 : UI.simSpeed;
  if (!UI.paused) stepSimulation(dt);

  // sync slider to gun
  slider.value = gun.wavelength;
  wlReadout.textContent =
    `${gun.wavelength.toFixed(1)} nm · ${gun.energy.toFixed(2)} eV · ${bandName(gun.wavelength)}`;

  // --- render --- (p5 global mode: drawing fns live on `window`)
  // everything below is authored in 1180x720 design space; scale it to fill
  // the live canvas. Pointer coords above are already in this same space.
  push();
  translate(view.ox, view.oy);
  scale(view.s);
  drawTitle();
  drawTimescale();
  drawBox();
  drawBeamPreview();
  model.draw(window, CX, CY);
  drawPhotons();
  gun.draw(window);

  diagram.draw(window, model.electronN, gun.energy, tuningGlow > 0);
  if (model.electronN == null) drawNoLevelsNote();
  spectrometer.draw(window);

  drawTransitionTable();
  if (hands.enabled) hands.drawPreview(window, CAM.x, CAM.y, CAM.w);
  drawInfoPanel();
  drawTuningRuler(ptr);
  drawPointer(ptr);
  pop();

  tuningGlow = Math.max(0, tuningGlow - 0.05);
}

// ---------------------------------------------------------------------------
// Simulation step
// ---------------------------------------------------------------------------
function stepSimulation(dt) {
  realTimeNs += REAL_NS_PER_FRAME * dt;   // advance the compressed real-time clock

  // gun beam
  gun.mode = UI.lightMode;
  gun.beamOn = UI.beamOn;
  gun.update(dt, CX, CY, photons);

  // emit callback for the atom
  const emit = (wl, ang) => {
    const sp = 3.4;
    photons.push(new Photon(CX, CY, Math.cos(ang) * sp, Math.sin(ang) * sp, wl));
    spectrometer.record(wl);
  };
  model.update(dt, emit);

  // photons
  for (const p of photons) {
    if (p.dead) continue;
    p.update(dt);
    // out of bounds
    if (p.x < -40 || p.x > W + 40 || p.y < -40 || p.y > H + 40) { p.dead = true; continue; }

    // interaction with atom
    const d = Math.hypot(p.x - CX, p.y - CY);
    if (model instanceof BilliardBallModel) {
      if (d < model.r + 6) {
        const nx = (p.x - CX) / (d || 1), ny = (p.y - CY) / (d || 1);
        const dot = p.vx * nx + p.vy * ny;
        if (dot < 0) { p.vx -= 2 * dot * nx; p.vy -= 2 * dot * ny; model.flash = 1; }
      }
    } else {
      const rad = interactionRadius(model);
      if (!p.armed && d > rad + 6) p.armed = true;     // cleared the atom → now absorbable
      if (rad > 0 && p.armed && d < rad) {
        if (model.tryAbsorb(p)) p.dead = true;
      }
    }
  }
  photons = photons.filter(p => !p.dead);
  if (photons.length > 400) photons.splice(0, photons.length - 400);
}

function interactionRadius(m) {
  if (m instanceof PlumPuddingModel) return m.R;
  if (m instanceof SolarSystemModel) return 0;
  if (m.currentRadius) return m.currentRadius() + 18;
  return 50;
}

// ---------------------------------------------------------------------------
// Gesture state machine — quick pinch = fire, pinch-drag = tune energy
//
// Forming a pinch physically shifts the fingertip (the cursor), and the cam→
// screen gain magnifies it — so without care a tap reads as a drag. We absorb
// that initial motion with a short SETTLE window (hand only): while settling,
// the drag-anchor tracks the hand instead of locking, so only motion AFTER the
// pinch has stabilized can commit to a drag. A bigger threshold guards jitter.
// ---------------------------------------------------------------------------
const DRAG_THRESH = 40;          // design px of deliberate motion to start tuning
const PINCH_SETTLE = 10;         // frames (~0.17s) to let the pinch settle first
function handleGesture(ptr) {
  if (ptr.down && !press.active) {
    press.active = true; press.dragging = false;
    press.sx = ptr.x; press.sy = ptr.y;
    press.settle = ptr.src === 'hand' ? PINCH_SETTLE : 0;   // mouse needs no settle
  } else if (ptr.down && press.active) {
    if (press.settle > 0) {
      // still settling: follow the hand so the pinch jerk can't seed a drag
      press.settle--; press.sx = ptr.x; press.sy = ptr.y;
    } else {
      const moved = Math.hypot(ptr.x - press.sx, ptr.y - press.sy);
      if (!press.dragging && moved > DRAG_THRESH) {
        press.dragging = true;
        press.dragStartX = ptr.x;          // anchor the relative drag here…
        press.dragStartE = gun.energy;     // …and tune outward from the current value
      }
      if (press.dragging) tuneFromPointer(ptr.x);
    }
  } else if (!ptr.down && press.active) {
    if (!press.dragging) firePhoton();
    press.active = false; press.dragging = false;
  }
}

function tuneFromPointer(px) {
  // Relative tuning: move the energy from its value when the drag began, scaled
  // by the band's px→eV sensitivity. The value never jumps to the cursor's x.
  const evPerPx = (TUNE.eMax - TUNE.eMin) / (TUNE.x1 - TUNE.x0);
  let e = constrain(press.dragStartE + (px - press.dragStartX) * evPerPx, TUNE.eMin, TUNE.eMax);
  // magnetic snap to transitions available from current level (+ ionization)
  const targets = [];
  if (model.electronN != null) {
    for (const t of absorptionsFrom(model.electronN)) targets.push(t.dE);
    targets.push(-energyLevel(model.electronN)); // ionization edge
  }
  let best = null, bestErr = TUNE.snap;
  for (const tE of targets) { const err = Math.abs(tE - e); if (err < bestErr) { best = tE; bestErr = err; } }
  if (best != null) e = best;
  gun.setEnergy(e);
  tuningGlow = 1;
}

function firePhoton() {
  if (UI.lightMode === 'white') gun.fire(CX, CY, photons);
  else gun.fire(CX, CY, photons);
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------
function drawTitle() {
  noStroke();
  fill(235, 240, 255); textAlign(LEFT, TOP); textSize(18);
  text('Models of the Hydrogen Atom', 20, 22);
  fill(120, 130, 165); textSize(11);
  text('Emergence prototype · pinch-tap to fire a photon · pinch-drag to tune its energy', 20, 48);
}

// readable real-time string (atto → milli seconds), input in nanoseconds
function fmtRealTime(ns) {
  if (ns < 1e-6) return (ns * 1e9).toFixed(0) + ' as';
  if (ns < 1e-3) return (ns * 1e6).toFixed(1) + ' fs';
  if (ns < 1)    return (ns * 1e3).toFixed(1) + ' ps';
  if (ns < 1e3)  return ns.toFixed(1) + ' ns';
  if (ns < 1e6)  return (ns / 1e3).toFixed(2) + ' µs';
  return (ns / 1e6).toFixed(2) + ' ms';
}

// scientific notation with a unicode superscript exponent, e.g. 1.2×10⁸
function fmtSci(x) {
  const e = Math.floor(Math.log10(x));
  const m = x / Math.pow(10, e);
  const sup = String(e).replace(/[0-9]/g, d => '⁰¹²³⁴⁵⁶⁷⁸⁹'[+d]);
  return `${m.toFixed(1)}×10${sup}`;
}

// time-dilation readout + live "real time" clock (top-right, above the diagram)
function drawTimescale() {
  push();
  const xR = DIA.x + DIA.w;
  noStroke(); textAlign(RIGHT, TOP);
  fill(150, 160, 190); textSize(10.5);
  text(`time slowed ~${fmtSci(TIME_SLOWDOWN)}× · 1 s here ≈ ${REAL_NS_PER_SCREEN_SEC.toFixed(1)} ns real`, xR, 20);
  fill(120, 220, 160); textSize(13);
  text(`real time elapsed: ${fmtRealTime(realTimeNs)}`, xR, 36);
  pop();
}

function drawBox() {
  push();
  noFill(); stroke(70, 80, 120); strokeWeight(1.5);
  rect(BOX.x, BOX.y, BOX.s, BOX.s, 6);
  noStroke(); fill(120, 130, 165); textSize(11); textAlign(RIGHT, BOTTOM);
  text(MODELS[UI.model].label + ' model', BOX.x + BOX.s - 8, BOX.y + BOX.s + 16);
  pop();
}

function drawBeamPreview() {
  const col = UI.lightMode === 'white' ? [235, 235, 245] : wavelengthToRGB(gun.wavelength);
  push();
  stroke(col[0], col[1], col[2], UI.beamOn ? 90 : 35);
  strokeWeight(UI.beamOn ? 6 : 2);
  line(GUN_X + 24, CY, BOX.x, CY);
  pop();
}

function drawPhotons() { for (const p of photons) p.draw(window); }

function drawNoLevelsNote() {
  push(); fill(110, 120, 150); textSize(11); textAlign(CENTER, CENTER);
  text('(this model has no\nquantized energy levels)', DIA.x + DIA.w / 2, DIA.y + DIA.h / 2);
  pop();
}

function drawTransitionTable() {
  const x = CAM.x, y = CAM.y + CAM.w * 0.75 + 16, w = CAM.w;
  push();
  noStroke(); fill(10, 12, 28); rect(x, y, w, 250, 8);
  fill(180, 190, 220); textAlign(LEFT, TOP); textSize(12);
  text('Absorption from n=' + (model.electronN || 1), x + 10, y + 8);
  textSize(10);
  const from = model.electronN || 1;
  let yy = y + 30;
  for (const t of absorptionsFrom(from)) {
    const c = wavelengthToRGB(t.lambda);
    fill(c[0], c[1], c[2]); rect(x + 10, yy + 2, 10, 10, 2);
    fill(200, 210, 230);
    text(`${t.label}  ${t.dE.toFixed(2)} eV  ${t.lambda.toFixed(0)} nm`, x + 26, yy);
    yy += 16;
  }
  fill(120, 130, 160); textSize(9);
  text('green ✓ on the diagram = a match', x + 10, yy + 4);
  pop();
}

function drawInfoPanel() {
  const x = 20, y = 560, w = 270, h = 150;
  push();
  noStroke(); fill(10, 12, 28); rect(x, y, w, h, 8);
  fill(200, 210, 235); textAlign(LEFT, TOP); textSize(12);
  text(MODELS[UI.model].label, x + 10, y + 10);
  fill(150, 162, 195); textSize(10.5);
  text(model.blurb, x + 10, y + 30, w - 20, h - 40);
  pop();
}

function drawTuningRuler(ptr) {
  const y = H - 28;
  push();
  // base line
  stroke(60, 70, 100); strokeWeight(2); line(TUNE.x0, y, TUNE.x1, y);
  // transition ticks from current level
  if (model.electronN != null) {
    for (const t of absorptionsFrom(model.electronN)) {
      const tx = map(t.dE, TUNE.eMin, TUNE.eMax, TUNE.x0, TUNE.x1);
      const c = wavelengthToRGB(t.lambda);
      stroke(c[0], c[1], c[2]); strokeWeight(2); line(tx, y - 7, tx, y + 7);
      noStroke(); fill(c[0], c[1], c[2]); textSize(9); textAlign(CENTER, TOP);
      text(t.label, tx, y + 9);
    }
    // ionization edge
    const ix = map(-energyLevel(model.electronN), TUNE.eMin, TUNE.eMax, TUNE.x0, TUNE.x1);
    stroke(255, 140, 120); strokeWeight(1.5); line(ix, y - 9, ix, y + 9);
  }
  // current energy marker
  const mx = map(constrain(gun.energy, TUNE.eMin, TUNE.eMax), TUNE.eMin, TUNE.eMax, TUNE.x0, TUNE.x1);
  const c = wavelengthToRGB(gun.wavelength);
  fill(c[0], c[1], c[2]); noStroke();
  triangle(mx, y - 12, mx - 6, y - 22, mx + 6, y - 22);
  // label
  fill(150, 160, 190); textAlign(LEFT, CENTER); textSize(10);
  text('low E', TUNE.x0 - 46, y); textAlign(RIGHT, CENTER);
  text('high E', TUNE.x1 + 48, y);
  if (press.dragging) {
    fill(255, 230, 120); textAlign(CENTER, BOTTOM); textSize(11);
    text('tuning…', mx, y - 26);
  }
  pop();
}

function drawPointer(ptr) {
  if (!ptr.present) return;
  push();
  const r = press.dragging ? 26 : 18;
  noFill();
  if (ptr.down) stroke(255, 220, 90, 220); else stroke(120, 200, 255, 220);
  strokeWeight(2); circle(ptr.x, ptr.y, r);
  if (ptr.down) { noStroke(); fill(255, 220, 90, 120); circle(ptr.x, ptr.y, r * 0.4); }
  // label
  noStroke(); fill(150, 160, 190); textSize(9); textAlign(LEFT, CENTER);
  text(ptr.src === 'hand' ? 'hand' : 'mouse', ptr.x + r, ptr.y);
  pop();
}

// keyboard conveniences
function keyPressed() {
  if (key === ' ') { UI.paused = !UI.paused; UI._pauseBtn.textContent = UI.paused ? '▶ Play' : '⏸ Pause'; }
  if (key === 'f' || key === 'F') firePhoton();
  if (key === 'r' || key === 'R') { model.reset(); realTimeNs = 0; }
}
