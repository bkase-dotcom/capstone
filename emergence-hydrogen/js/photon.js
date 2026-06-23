/* =============================================================================
 * photon.js — a travelling photon (wave-packet glyph)
 * ===========================================================================*/

class Photon {
  constructor(x, y, vx, vy, wavelengthNm) {
    this.x = x; this.y = y;
    this.vx = vx; this.vy = vy;
    this.wavelength = wavelengthNm;
    this.energy = wavelengthToEnergy(wavelengthNm);
    this.color = wavelengthToRGB(wavelengthNm);
    this.dead = false;
    this.phase = 0;
    this.born = 0;
    this.armed = false;   // becomes true once clear of the atom (prevents self-absorption)
  }

  update(dt) {
    this.x += this.vx * dt;
    this.y += this.vy * dt;
    this.phase += 0.5 * dt;
    this.born += dt;
  }

  // Draw a short sinusoidal wave-packet oriented along velocity
  draw(g) {
    const speed = Math.hypot(this.vx, this.vy) || 1;
    const ux = this.vx / speed, uy = this.vy / speed;   // along travel
    const px = -uy, py = ux;                              // perpendicular
    const len = 26, amp = 5, cycles = 3;

    g.push();
    g.noFill();
    g.stroke(this.color[0], this.color[1], this.color[2], 230);
    g.strokeWeight(2);
    g.beginShape();
    for (let i = -len / 2; i <= len / 2; i += 2) {
      const s = (i + len / 2) / len;                     // 0..1 along packet
      const env = Math.sin(s * Math.PI);                 // gaussian-ish envelope
      const wave = Math.sin(s * cycles * Math.PI * 2 + this.phase) * amp * env;
      g.vertex(this.x + ux * i + px * wave, this.y + uy * i + py * wave);
    }
    g.endShape();

    // soft glow head
    g.noStroke();
    g.fill(this.color[0], this.color[1], this.color[2], 60);
    g.circle(this.x, this.y, 14);
    g.pop();
  }
}
