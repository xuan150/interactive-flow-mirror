// Numeric check of the notice field in Assets/_Project/Notice/Notice_Clear.hlsl (docs/notice.md, round 5). Same formulas, without
// the warp / tilt / width wobble. Run: node docs/notice-field-check.js
// Checks: the core has no step at its edge, the shell's density peak, no folding (Jacobian > 0), and that a moving viewer's tail
// stays one continuous low-density trail. Keep the constants in step with the #defines at the top of Notice_Clear.hlsl.
const A = 0.25, B = 0.76;
const C = {
  rim: 0.25, deflect: 0.6, keep: 0.05, ramp: 2.0, band: 0.5, lee: 0.5, leePush: 0.85,
  wakeDim: 0.6, wakeFade: 0.6, wakeSamples: 3, depthPush: 1.0,
};
const S = (x) => x * x * (3 - 2 * x);
const sat = (x) => Math.min(Math.max(x, 0), 1);
const sdf = (x, y) => { // upright capsule
  const qy = Math.abs(y) - (B - A);
  return Math.hypot(Math.abs(x), Math.max(qy, 0)) + Math.min(Math.max(Math.abs(x), qy), 0) - A;
};

// One copy of the field at (cx, cy), strength st. Returns the moved point.
function field(x, y, stayer, cx, cy, st, deflect = C.deflect) {
  const px = x - cx, py = y - cy;
  const s = sdf(px, py), d = Math.max(s + A, 0);
  const L = A / Math.min(Math.max(C.rim, 0.05), 0.8);
  const D0 = A / (C.ramp + 1);
  let dp;
  if (d < D0) dp = A * Math.pow(d / D0, 1 / (C.ramp + 1)); // the core: a soft ramp, nothing is cut out
  else dp = d + (A - D0) * (1 - S(sat((d - D0) / (L - D0)))); // the shell: the rest piles up outside, fading to nothing at L
  const fs = stayer ? S(sat(d / A)) : 1;
  const qy = Math.abs(py) - (B - A), qox = Math.abs(px), qoy = Math.max(qy, 0);
  const sgx = px >= 0 ? 1 : -1, sgy = py >= 0 ? 1 : -1;
  let nx, ny;
  if (qox + qoy > 0) { const l = Math.hypot(qox, qoy); nx = qox / l * sgx; ny = qoy / l * sgy; } else { nx = sgx; ny = 0; }
  const up = (() => { const t = sat((-nx + 0.5) / 1.0); return S(t); })(); // 1 on the upstream (left) side, 0 on the lee side
  const shear = -Math.tanh(py / (C.band * B)) * deflect * (C.lee + (1 - C.lee) * up);
  const push = (dp - d) * st * fs * (C.leePush + (1 - C.leePush) * up);
  return [x + (nx - shear * ny) * push, y + (ny + shear * nx) * push];
}

// The whole field: the body pushes the dots; a moving viewer also leaves a soft dim band along the tail (a weight, no push), so
// the trail is one continuous low-density region instead of a row of holes. Returns [x, y, weight] (weight 1 = as bright as before).
function whole(x, y, stayer, tail, deflect) {
  const m = field(x, y, stayer, 0, 0, C.depthPush, deflect);
  const tl = Math.hypot(tail[0], tail[1]);
  const tailW = S(sat((Math.min(tl, 1.2) - 0.04) / (0.35 - 0.04)));
  if (tailW <= 0) return [m[0], m[1], 1];
  const k = tl > 1.2 ? 1.2 / tl : 1, tx = tail[0] * k, ty = tail[1] * k, td = Math.hypot(tx, ty);
  let band = 0;
  for (let i = 1; i <= C.wakeSamples; i++) {
    const lam = i / C.wakeSamples;
    const sk = sdf(m[0] - lam * tx, m[1] - lam * ty);
    band = Math.max(band, (1 - S(sat((sk + 0.5 * A) / (2 * A)))) * (1 - C.wakeFade * lam));
  }
  const behind = S(sat((((m[0] * tx + m[1] * ty) / td) - 0.2 * A) / (1.2 * A)));
  return [m[0], m[1], 1 - tailW * C.wakeDim * band * behind];
}

function density(tail, N = 3000000, W = 2.2, H = 1.6, bin = 0.05) {
  const nx = Math.round(2 * W / bin), ny = Math.round(2 * H / bin), hist = new Float64Array(nx * ny);
  for (let i = 0; i < N; i++) {
    const x = (Math.random() * 2 - 1) * W, y = (Math.random() * 2 - 1) * H;
    const [mx, my, w] = whole(x, y, Math.random() < C.keep, tail);
    const ix = Math.floor((mx + W) / bin), iy = Math.floor((my + H) / bin);
    if (ix >= 0 && ix < nx && iy >= 0 && iy < ny) hist[iy * nx + ix] += w;
  }
  const mean = N / (nx * ny);
  const at = (x, y) => hist[Math.floor((y + H) / bin) * nx + Math.floor((x + W) / bin)] / mean;
  return { at, nx, ny, W, H, bin, mean, hist };
}

const row = (D, y, x0, x1, step) => { let s = ''; for (let x = x0; x <= x1 + 1e-9; x += step) s += D.at(x, y).toFixed(2).padStart(6); return s; };

// 1. Still viewer: the density along x at the middle height and at y = 0.5, and the peak of the shell.
const still = density([0, 0]);
console.log('x:                ' + [-1, -0.8, -0.6, -0.5, -0.4, -0.3, -0.2, -0.1, 0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1].map((v) => v.toFixed(1).padStart(6)).join(''));
const xs = [-1, -0.8, -0.6, -0.5, -0.4, -0.3, -0.2, -0.1, 0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1];
console.log('density y=0:      ' + xs.map((x) => still.at(x, 0.01).toFixed(2).padStart(6)).join(''));
console.log('density y=0.5:    ' + xs.map((x) => still.at(x, 0.5).toFixed(2).padStart(6)).join(''));
let peak = 0, px = 0, py = 0;
for (let iy = 8; iy < still.ny - 8; iy++) for (let ix = 8; ix < still.nx - 8; ix++) {
  const v = still.hist[iy * still.nx + ix] / still.mean;
  if (v > peak) { peak = v; px = (ix + 0.5) * still.bin - still.W; py = (iy + 0.5) * still.bin - still.H; }
}
console.log(`shell peak density ${peak.toFixed(2)}x at (${px.toFixed(2)}, ${py.toFixed(2)})`);
// The largest jump between neighbouring bins along the middle height across the core's edge (x = +-A): a hard edge would show here.
let jump = 0;
for (let x = -0.6; x < 0.6; x += 0.05) jump = Math.max(jump, Math.abs(still.at(x + 0.05, 0.01) - still.at(x, 0.01)));
console.log(`largest step between neighbouring 0.05 bins across the core, y=0: ${jump.toFixed(2)}`);

// 2. Folding: finite-difference Jacobian determinant of the body field (a stayer differs only by a smaller push).
for (const deflect of [0.6, 1.0, 1.5]) {
  let minDet = 9, at = null;
  const e = 1e-3;
  for (let x = -1.0; x <= 1.0; x += 0.02) for (let y = -1.4; y <= 1.4; y += 0.02) {
    if (Math.abs(x) < 2 * e) continue;
    const f = (a, b) => whole(a, b, false, [0, 0], deflect);
    const [a, b] = f(x + e, y), [c, d] = f(x - e, y), [g, h] = f(x, y + e), [k, l] = f(x, y - e);
    const det = ((a - c) / (2 * e)) * ((h - l) / (2 * e)) - ((g - k) / (2 * e)) * ((b - d) / (2 * e));
    if (det < minDet) { minDet = det; at = [x, y]; }
  }
  console.log(`deflect ${deflect}: min Jacobian det ${minDet.toFixed(3)} at (${at.map((v) => v.toFixed(2))})`);
}

// 3. Moving viewer: tails of 0.6 and 1.2 screen half-heights toward -x (the viewer has been moving +x): the visible density (dots
// times their weight) along the middle height from behind the tail to ahead of the body. It should be one soft trail, not islands.
for (const len of [0.6, 1.2]) {
  const D = density([-len, 0]);
  const xs2 = []; for (let x = -len - 0.8; x <= 0.81; x += 0.1) xs2.push(+x.toFixed(2));
  console.log(`tail ${len}: x = ${xs2[0]} .. ${xs2[xs2.length - 1]}`);
  console.log('  density y=0:   ' + xs2.map((x) => D.at(x, 0.01).toFixed(2).padStart(5)).join(''));
}
