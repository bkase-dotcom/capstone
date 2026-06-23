/* =============================================================================
 * energyDiagram.js — electron energy-level diagram (right panel)
 * Draws levels n=1..NMAX, highlights the electron's current level, and shows
 * the dialed photon energy as a bracket rising from the current level so the
 * user can line it up with a higher level (the core "match the gap" mechanic).
 * ===========================================================================*/

class EnergyDiagram {
  constructor(x, y, w, h) {
    this.x = x; this.y = y; this.w = w; this.h = h;
    this.nMax = NMAX;
    // Energy axis: E=0 (top) down to E_1 = -13.6 eV (bottom)
    this.eTop = 0.4;
    this.eBot = energyLevel(1) - 0.4;
  }

  eToPx(eV) {
    const t = (eV - this.eTop) / (this.eBot - this.eTop);
    return this.y + 34 + t * (this.h - 62);   // leave headroom for the panel title
  }

  levelX(n) {
    // fan the levels slightly so high-n lines (which bunch up) stay legible
    return this.x + 46;
  }

  draw(g, electronN, photonEV, tuning) {
    g.push();
    // panel
    g.noStroke(); g.fill(10, 12, 28);
    g.rect(this.x, this.y, this.w, this.h, 8);
    g.fill(180, 190, 220);
    g.textAlign(LEFT, TOP); g.textSize(13);
    g.text('Electron Energy (eV)', this.x + 12, this.y + 8);

    const xL = this.x + 44;
    const xR = this.x + this.w - 16;

    // levels
    for (let n = 1; n <= this.nMax; n++) {
      const yy = this.eToPx(energyLevel(n));
      const isCur = n === electronN;
      if (isCur) { g.stroke(255, 210, 70); g.strokeWeight(3); }
      else { g.stroke(90, 100, 140); g.strokeWeight(1.2); }
      g.line(xL, yy, xR, yy);

      g.noStroke();
      g.fill(isCur ? 255 : 150, isCur ? 210 : 160, isCur ? 70 : 190);
      g.textAlign(RIGHT, CENTER); g.textSize(11);
      g.text('n=' + n, xL - 6, yy);
      g.textAlign(LEFT, CENTER); g.fill(90, 100, 130); g.textSize(9);
      g.text(energyLevel(n).toFixed(2), xR + 2, yy);
    }
    // ionization line
    const y0 = this.eToPx(0);
    g.stroke(120, 130, 170); g.strokeWeight(0.8); g.drawingContext.setLineDash([4, 4]);
    g.line(xL, y0, xR, y0); g.drawingContext.setLineDash([]);
    g.noStroke(); g.fill(120, 130, 170); g.textAlign(LEFT, CENTER); g.textSize(9);
    g.text('ionized (n=∞)', xL + 4, y0 - 8);

    // photon-energy bracket: from current level up by photonEV
    if (photonEV && electronN) {
      const eStart = energyLevel(electronN);
      const eEnd = Math.min(0.2, eStart + photonEV);
      const yStart = this.eToPx(eStart);
      const yEnd = this.eToPx(eEnd);
      const bx = xR - 18;

      const match = matchAbsorption(electronN, photonEV, 0.08);
      const ion = ionizes(electronN, photonEV);
      const col = match ? [120, 255, 140] : ion ? [255, 140, 120] : [120, 170, 255];

      g.stroke(col[0], col[1], col[2], tuning ? 255 : 180);
      g.strokeWeight(tuning ? 4 : 3);
      g.line(bx, yStart, bx, yEnd);
      // arrowhead at top
      g.fill(col[0], col[1], col[2]); g.noStroke();
      g.triangle(bx, yEnd, bx - 4, yEnd + 7, bx + 4, yEnd + 7);

      // energy readout near the bracket
      g.textAlign(RIGHT, CENTER); g.textSize(11);
      g.fill(col[0], col[1], col[2]);
      const midY = (yStart + yEnd) / 2;
      let tag = photonEV.toFixed(2) + ' eV';
      if (match) tag = match.label + '  ✓';
      else if (ion) tag = 'ionize ✓';
      g.text(tag, bx - 8, midY);
    }
    g.pop();
  }
}
