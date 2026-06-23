/* =============================================================================
 * spectrum.js — visible-spectrum color from wavelength
 * Classic Dan Bruton approximation (380–780 nm). UV/IR rendered as cues.
 * Returns [r,g,b] in 0..255.
 * ===========================================================================*/

function wavelengthToRGB(nm) {
  let r = 0, g = 0, b = 0;

  if (nm < 380) {
    // UV — render as a dim violet so the beam is still visible on screen
    const t = constrainClamp((nm - 200) / (380 - 200), 0, 1);
    r = 0.35 + 0.25 * (1 - t);
    g = 0.0;
    b = 0.55 + 0.45 * t;
    return scaleRGB(r, g, b, 0.85);
  } else if (nm <= 440) {
    r = -(nm - 440) / (440 - 380); g = 0; b = 1;
  } else if (nm <= 490) {
    r = 0; g = (nm - 440) / (490 - 440); b = 1;
  } else if (nm <= 510) {
    r = 0; g = 1; b = -(nm - 510) / (510 - 490);
  } else if (nm <= 580) {
    r = (nm - 510) / (580 - 510); g = 1; b = 0;
  } else if (nm <= 645) {
    r = 1; g = -(nm - 645) / (645 - 580); b = 0;
  } else if (nm <= 780) {
    r = 1; g = 0; b = 0;
  } else {
    // IR — render as a deep, dim red
    const t = constrainClamp((nm - 780) / (1400 - 780), 0, 1);
    r = 0.75 * (1 - 0.6 * t); g = 0; b = 0;
    return scaleRGB(r, g, b, 1);
  }

  // Intensity falloff near the limits of human vision
  let factor = 1;
  if (nm < 420) factor = 0.3 + 0.7 * (nm - 380) / (420 - 380);
  else if (nm > 700) factor = 0.3 + 0.7 * (780 - nm) / (780 - 700);

  return scaleRGB(r, g, b, factor);
}

function scaleRGB(r, g, b, factor) {
  const gamma = 0.8;
  const f = (c) => (c <= 0 ? 0 : Math.round(255 * Math.pow(c * factor, gamma)));
  return [f(r), f(g), f(b)];
}

function constrainClamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

// Band label for a wavelength
function bandName(nm) {
  if (nm < 380) return 'UV';
  if (nm > 780) return 'IR';
  return 'visible';
}
