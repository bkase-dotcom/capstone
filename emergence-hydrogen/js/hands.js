/* =============================================================================
 * hands.js — webcam hand tracking via ml5.js handPose (wraps MediaPipe Hands).
 * Produces a unified "pointer": { present, x, y, pinch } in CANVAS coordinates,
 * mirrored so motion feels like a selfie. Gesture interpretation (tap vs drag)
 * lives in the interaction layer so mouse + hand share one code path.
 * ===========================================================================*/

class HandTracker {
  constructor() {
    this.enabled = false;
    this.ready = false;
    this.loading = false;
    this.video = null;
    this.model = null;
    this.hands = [];
    this.error = null;

    // smoothed pointer
    this.present = false;
    this.x = 0; this.y = 0;
    this.pinch = false;
    this._pinchRaw = false;
    this._sx = 0; this._sy = 0;
    this.pinchAmount = 1;     // normalized thumb–index distance (for UI ring)
  }

  enable(onReady) {
    if (this.enabled) return;
    this.enabled = true;
    this.loading = true;
    try {
      this.video = createCapture(VIDEO, () => {});
      this.video.size(320, 240);
      this.video.hide();
      // ml5 1.x
      this.model = ml5.handPose({ maxHands: 1, flipped: false }, () => {
        this.ready = true; this.loading = false;
        this.model.detectStart(this.video, (results) => { this.hands = results; });
        if (onReady) onReady();
      });
    } catch (e) {
      this.error = e.message || String(e);
      this.loading = false; this.enabled = false;
    }
  }

  disable() {
    this.enabled = false; this.ready = false; this.present = false; this.pinch = false;
    try { if (this.model) this.model.detectStop(); } catch (e) {}
    try { if (this.video) { this.video.remove(); this.video = null; } } catch (e) {}
    this.hands = [];
  }

  // ml5 returns keypoints in the coordinate space of the video element's *set*
  // size (the one we pass to video.size()), NOT the camera's intrinsic
  // resolution. Normalize by that same size so the skeleton and pointer land
  // exactly on the hand and span the full frame.
  _videoDims() {
    const vw = (this.video && this.video.width) || 320;
    const vh = (this.video && this.video.height) || 240;
    return [vw, vh];
  }

  // map video-pixel coords -> design-space canvas coords (W x H), mirrored so
  // motion feels like a selfie. Maps the FULL camera frame onto the full
  // screen: moving your hand edge-to-edge in the cam reaches edge-to-edge
  // on screen.
  _toCanvas(px, py, vw, vh) {
    const nx = 1 - px / vw;        // mirror x → normalized [0,1] across frame
    const ny = py / vh;
    return [nx * W, ny * H];
  }

  update() {
    if (!this.ready || !this.hands || !this.hands.length) { this.present = false; this.pinch = false; return; }
    const h = this.hands[0];
    const kp = h.keypoints;
    if (!kp || kp.length < 13) { this.present = false; return; }
    const [vw, vh] = this._videoDims();

    const thumb = kp[4], index = kp[8], wrist = kp[0], midMcp = kp[9];
    // pointer = index fingertip (what you point with); pinch still uses thumb↔index
    const [targetX, targetY] = this._toCanvas(index.x, index.y, vw, vh);
    const a = 0.35;                                   // smoothing
    this._sx += (targetX - this._sx) * a;
    this._sy += (targetY - this._sy) * a;
    this.x = this._sx; this.y = this._sy;
    this.present = true;

    // pinch: thumb–index distance normalized by hand scale (wrist→middle MCP)
    const pinchPx = Math.hypot(thumb.x - index.x, thumb.y - index.y);
    const scale = Math.hypot(wrist.x - midMcp.x, wrist.y - midMcp.y) || 1;
    const ratio = pinchPx / scale;
    this.pinchAmount = ratio;
    // Engage only when thumb & index are nearly touching; release once clearly
    // apart. Thresholds are thumb–index distance as a fraction of hand size, so
    // they hold across distance from the camera. Hysteresis prevents flicker.
    const PINCH_ON = 0.28, PINCH_OFF = 0.42;
    if (this._pinchRaw) { if (ratio > PINCH_OFF) this._pinchRaw = false; }
    else { if (ratio < PINCH_ON) this._pinchRaw = true; }
    this.pinch = this._pinchRaw;
  }

  // small camera preview + landmark overlay in a corner
  drawPreview(g, px, py, w) {
    if (!this.ready || !this.video) return;
    const h = w * 0.75;
    g.push();
    g.translate(px, py);
    // mirrored video
    g.push(); g.translate(w, 0); g.scale(-1, 1);
    g.tint(255, 200); g.image(this.video, 0, 0, w, h); g.noTint();
    g.pop();
    g.noFill(); g.stroke(80, 90, 130); g.strokeWeight(1); g.rect(0, 0, w, h, 4);

    if (this.hands.length) {
      const [vw, vh] = this._videoDims();
      const kp = this.hands[0].keypoints;
      for (const k of kp) {
        const x = (1 - k.x / vw) * w, y = (k.y / vh) * h;
        g.noStroke(); g.fill(120, 220, 160); g.circle(x, y, 3);
      }
      // highlight thumb & index
      for (const idx of [4, 8]) {
        const k = kp[idx]; const x = (1 - k.x / vw) * w, y = (k.y / vh) * h;
        g.fill(this.pinch ? [255, 220, 90] : [120, 200, 255]); g.circle(x, y, 6);
      }
    }
    g.noStroke(); g.fill(150, 160, 190); g.textSize(9); g.textAlign(LEFT, BOTTOM);
    g.text('hand cam', 4, h - 3);
    g.pop();
  }
}
