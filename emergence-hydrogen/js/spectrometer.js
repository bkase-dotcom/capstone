/* =============================================================================
 * spectrometer.js — records emitted photon wavelengths as a live spectrum.
 * Mirrors the PhET spectrometer: emitted lines accumulate as colored bars.
 * ===========================================================================*/

class Spectrometer {
  constructor(x, y, w, h) {
    this.x = x; this.y = y; this.w = w; this.h = h;
    this.minNm = 80; this.maxNm = 820;
    this.bins = {};   // wavelength(rounded) -> count
    this.recording = true;
  }

  record(nm) {
    if (!this.recording) return;
    const key = Math.round(nm);
    this.bins[key] = (this.bins[key] || 0) + 1;
  }

  clear() { this.bins = {}; }

  nmToPx(nm) {
    const t = (nm - this.minNm) / (this.maxNm - this.minNm);
    return this.x + 36 + t * (this.w - 48);
  }

  draw(g) {
    g.push();
    g.noStroke(); g.fill(10, 12, 28);
    g.rect(this.x, this.y, this.w, this.h, 8);

    g.fill(180, 190, 220); g.textAlign(LEFT, TOP); g.textSize(13);
    g.text('Spectrometer', this.x + 12, this.y + 8);
    g.textAlign(RIGHT, TOP); g.textSize(9); g.fill(110, 120, 150);
    g.text(this.recording ? '● recording' : 'paused', this.x + this.w - 12, this.y + 10);

    const baseY = this.y + this.h - 22;

    // spectrum strip (visible band colored)
    for (let px = this.x + 36; px < this.x + this.w - 12; px += 2) {
      const t = (px - (this.x + 36)) / (this.w - 48);
      const nm = this.minNm + t * (this.maxNm - this.minNm);
      const c = wavelengthToRGB(nm);
      g.stroke(c[0], c[1], c[2], 70); g.strokeWeight(2);
      g.line(px, baseY + 4, px, baseY + 12);
    }

    // band labels
    g.noStroke(); g.fill(120, 130, 160); g.textSize(8); g.textAlign(CENTER, TOP);
    g.text('UV', this.nmToPx(150), baseY + 14);
    g.text('visible', this.nmToPx(550), baseY + 14);
    g.text('IR', this.nmToPx(800), baseY + 14);

    // recorded lines
    let maxCount = 1;
    for (const k in this.bins) maxCount = Math.max(maxCount, this.bins[k]);
    for (const k in this.bins) {
      const nm = +k;
      const px = this.nmToPx(nm);
      if (px < this.x + 30 || px > this.x + this.w - 8) continue;
      const c = wavelengthToRGB(nm);
      const hgt = (this.bins[k] / maxCount) * (this.h - 56);
      g.stroke(c[0], c[1], c[2]); g.strokeWeight(2.5);
      g.line(px, baseY, px, baseY - hgt);
    }
    g.pop();
  }
}
