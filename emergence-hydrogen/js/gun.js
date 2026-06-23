/* =============================================================================
 * gun.js — the light source. Fires photons rightward into the atom box.
 * Modes: 'monochromatic' (single wavelength) or 'white' (random visible+UV).
 * ===========================================================================*/

class LightGun {
  constructor(x, y) {
    this.x = x; this.y = y;            // muzzle position
    this.wavelength = 121.6;           // nm (Lyman α by default)
    this.mode = 'monochromatic';       // 'monochromatic' | 'white'
    this.beamOn = false;               // continuous beam toggle
    this.fireCooldown = 0;
    this.aimY = y;                     // vertical aim (target row)
    this.muzzleFlash = 0;
  }

  // Wavelength range the gun can produce (UV through near-IR)
  static MIN_NM = 80;
  static MAX_NM = 820;

  setWavelength(nm) {
    this.wavelength = Math.max(LightGun.MIN_NM, Math.min(LightGun.MAX_NM, nm));
  }
  setEnergy(eV) { this.setWavelength(energyToWavelength(eV)); }
  get energy() { return wavelengthToEnergy(this.wavelength); }

  // Produce one photon aimed at (targetX, targetY)
  fire(targetX, targetY, photons) {
    const wl = this.mode === 'white' ? this._randomWhiteWavelength() : this.wavelength;
    const dx = targetX - this.x, dy = targetY - this.aimY;
    const d = Math.hypot(dx, dy) || 1;
    const speed = 4.2;
    photons.push(new Photon(this.x + 24, this.aimY, speed * dx / d, speed * dy / d, wl));
    this.muzzleFlash = 1;
  }

  _randomWhiteWavelength() {
    // Weighted toward the UV/visible region so excitation is possible
    return 90 + Math.random() * (780 - 90);
  }

  update(dt, targetX, targetY, photons) {
    this.muzzleFlash = Math.max(0, this.muzzleFlash - 0.08 * dt);
    if (this.beamOn) {
      this.fireCooldown -= dt;
      if (this.fireCooldown <= 0) {
        this.fire(targetX, targetY, photons);
        this.fireCooldown = this.mode === 'white' ? 6 : 10;
      }
    }
  }

  draw(g) {
    const col = this.mode === 'white'
      ? [235, 235, 245]
      : wavelengthToRGB(this.wavelength);

    g.push();
    g.translate(this.x, this.aimY);

    // body
    g.noStroke();
    g.fill(40, 44, 66);
    g.rectMode(CENTER);
    g.rect(-30, 0, 70, 46, 8);
    g.fill(58, 64, 92);
    g.rect(-30, 0, 70, 30, 6);

    // muzzle
    g.fill(col[0], col[1], col[2]);
    g.rect(8, 0, 26, 16, 3);

    // muzzle flash
    if (this.muzzleFlash > 0) {
      g.fill(col[0], col[1], col[2], 180 * this.muzzleFlash);
      g.circle(22, 0, 26 * this.muzzleFlash + 8);
    }
    g.pop();
  }
}
