// Notice flow (docs/notice.md, "Flow"): a JS copy of Notice_Flow.hlsl plus numeric checks. Run: node docs/notice-flow-check.js
// Keep K and step() in step with Notice_Flow.hlsl (same names, same order). The checks only say the integration is sound; whether
// the dots look like they flow around the viewer is judged in the Game view.
'use strict';

const TAU = 6.2831853;
const K = {
  // The body: an upright capsule of a fixed size (Width Stay, Height Stay) that wobbles, breathes, sways and wanders like Clear's.
  WOBBLE: 0.12, BREATH: 0.1, WANDER: 0.1,
  // How fast a fully aware dot is moved off the edge (AVOID) and along it (SLIDE), screen half-heights per second.
  AVOID: 0.07, SLIDE: 0.14,
  // The field reaches this far outside the edge, and fades out this share of the half-width inside it (the middle is left alone).
  REACH: 0.45, INNER: 0.6,
  // Along the edge the dot keeps the part of its own flow that runs along the edge: none where the flow hits the edge head-on, all
  // of it where it runs past; SIGN_BAND is how much along-ness counts as all of it. FALLBACK is the little "up on the upper half,
  // down on the lower half" added so the dots whose flow hits head-on (or that hardly move, the far dust) still pick a side.
  SIGN_BAND: 0.4, FALLBACK: 0.15,
  // Spring back to the idle place (seconds), never quicker than RETURN_RATIO response times (keeps the damping ratio >= 0.6).
  RETURN: 2.5, RETURN_RATIO: 1.5,
  // Hard limits: offset (half-heights), offset speed (half-heights per second), one step (seconds).
  O_MAX: 0.45, W_MAX: 0.6, DT_MAX: 0.1,
  // Awareness: each dot wakes up at its own point of the rise. Strength breathes this much per dot; the far layers take FAR_GAIN of
  // the strength and are FAR_SLOW times slower.
  STAGGER: 0.6, JITTER: 0.25, FAR_GAIN: 0.4, FAR_SLOW: 1.5,
  // Per ribbon (0-1 far dust, 2-5 the story ribbons): strength and response time (seconds).
  GAIN: [0.35, 0.35, 1.0, 0.7, 0.9, 0.6],
  RESP: [1.4, 1.4, 0.6, 1.0, 0.8, 1.2],
};
// Test-only terms (Notice_FLOW_NO_AVOID / NO_SLIDE): which of the two pushes are on.
const BOTH = { avoid: true, slide: true };

const sat = (x) => Math.min(Math.max(x, 0), 1);
const lerp = (a, b, t) => a + (b - a) * t;
const smoothstep = (a, b, x) => { const t = sat((x - a) / (b - a)); return t * t * (3 - 2 * t); };

// Same as Notice_Warp / Notice_WidthScale / Notice_BoxSdf in Notice_Clear.hlsl.
function warp(x, y, t, amp) {
  return [(0.6 * Math.sin(2.7 * y + 0.41 * t + 0.3) + 0.4 * Math.sin(4.9 * y - 0.29 * t + 2.1)) * amp,
          (0.6 * Math.sin(3.1 * x - 0.37 * t + 1.1) + 0.4 * Math.sin(5.7 * x + 0.23 * t + 4.0)) * amp];
}
function widthScale(y, b, t, wobble) {
  const k = y / Math.max(b, 1e-3);
  return Math.min(Math.max(1 + wobble * (0.6 * Math.sin(1.9 * k + 0.31 * t) + 0.4 * Math.sin(3.3 * k - 0.23 * t + 1.7)), 0.5), 1.6);
}
function boxSdf(px, py, ex, ey, r) {
  const qx = Math.abs(px) - (ex - r), qy = Math.abs(py) - (ey - r);
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
}

// The body at this moment. n: { clock, viewerX, viewerY, aware, widthStay, heightStay, ragged, widthWobble, tilt }.
function body(n) {
  const t = n.clock;
  const A = Math.max(n.widthStay * (1 + K.WOBBLE * Math.sin(0.37 * t + 0.6)), 1e-3);
  const B = Math.max(n.heightStay * (1 + K.WOBBLE * Math.sin(0.29 * t + 2.4)), 1e-3);
  const ang = n.tilt * Math.sin(0.23 * t + 1.3);
  return {
    t, A, B, r: Math.min(A * (1 - K.BREATH * (0.5 + 0.5 * Math.sin(0.31 * t + 0.9))), 0.9 * B),
    cx: n.viewerX * 2 + K.WANDER * Math.sin(0.21 * t + 1), cy: n.viewerY + K.WANDER * Math.sin(0.17 * t + 2),
    sn: Math.sin(ang), cs: Math.cos(ang),
  };
}

// Distance to the edge (s < 0 inside), the outward normal on the screen, and the height in the body (patch space y).
function field(x, y, b, n) {
  const p0 = x - b.cx, p1 = y - b.cy;
  const prx = b.cs * p0 + b.sn * p1, pry = -b.sn * p0 + b.cs * p1;
  const wv = widthScale(pry, b.B, b.t, n.widthWobble);
  const [wx, wy] = warp(prx / wv, pry, b.t, n.ragged);
  const pwx = prx / wv + wx, pwy = pry + wy;
  const s = boxSdf(pwx, pwy, b.A, b.B, b.r);
  const sgx = pwx >= 0 ? 1 : -1, sgy = pwy >= 0 ? 1 : -1;
  const qx = Math.abs(pwx) - (b.A - b.r), qy = Math.abs(pwy) - (b.B - b.r);
  const qox = Math.max(qx, 0), qoy = Math.max(qy, 0);
  let nx, ny;
  if (qox + qoy > 0) { const l = Math.hypot(qox, qoy); nx = (qox / l) * sgx; ny = (qoy / l) * sgy; }
  else if (qx > qy) { nx = sgx; ny = 0; } else { nx = 0; ny = sgy; }
  // A normal goes back through the width scale divided, not multiplied; then undo the sway.
  const dx = nx / wv, dy = ny;
  let sx = b.cs * dx - b.sn * dy, sy = b.sn * dx + b.cs * dy;
  const l = Math.hypot(sx, sy) + 1e-6;
  return { s, nx: sx / l, ny: sy / l, h: pwy / b.B };
}

// One step of one dot. q: { x, y (its idle place, screen half-heights), fx, fy (unit direction of its idle flow), ox, oy, wx, wy
// (offset and offset speed, the stored attributes), ribbon, depthF, stag, phase, rate, respJ (its own random numbers) }.
function step(q, b, n, dt, terms = BOTH) {
  dt = Math.min(Math.max(dt, 0), K.DT_MAX);
  const aw = smoothstep(q.stag * K.STAGGER, q.stag * K.STAGGER + 1 - K.STAGGER, n.aware);
  const gain = K.GAIN[q.ribbon] * lerp(1, K.FAR_GAIN, q.depthF) * (1 + K.JITTER * Math.sin(TAU * (q.phase + b.t * (0.04 + 0.08 * q.rate))));
  const resp = K.RESP[q.ribbon] * lerp(1, K.FAR_SLOW, q.depthF) * (0.8 + 0.4 * q.respJ);
  const ret = Math.max(K.RETURN, K.RETURN_RATIO * resp);
  const g = aw * gain;
  let tx = -q.ox / ret, ty = -q.oy / ret;
  if (g > 0) {
    const f = field(q.x + q.ox, q.y + q.oy, b, n);
    const h = f.s > 0 ? 1 - smoothstep(0, K.REACH, f.s) : smoothstep(-K.INNER * b.A, 0, f.s);
    if (terms.avoid) { tx += g * K.AVOID * h * f.nx; ty += g * K.AVOID * h * f.ny; }
    if (terms.slide) {
      const ex = f.ny, ey = -f.nx;
      const along = Math.tanh((ex * q.fx + ey * (q.fy + K.FALLBACK * Math.tanh(Math.min(Math.max(f.h, -4), 4)))) / K.SIGN_BAND);
      tx += g * K.SLIDE * h * along * ex; ty += g * K.SLIDE * h * along * ey;
    }
  }
  const k = 1 - Math.exp(-dt / resp);
  q.wx += (tx - q.wx) * k; q.wy += (ty - q.wy) * k;
  const wl = Math.hypot(q.wx, q.wy);
  if (wl > K.W_MAX) { q.wx *= K.W_MAX / wl; q.wy *= K.W_MAX / wl; }
  q.ox += q.wx * dt; q.oy += q.wy * dt;
  const ol = Math.hypot(q.ox, q.oy);
  if (ol > K.O_MAX) {
    const ux = q.ox / ol, uy = q.oy / ol;
    q.ox = ux * K.O_MAX; q.oy = uy * K.O_MAX;
    const out = q.wx * ux + q.wy * uy;
    if (out > 0) { q.wx -= out * ux; q.wy -= out * uy; }
  }
}

// ---- The scripted visit (same timeline as ScriptedPersonSource): seconds -> where the viewer is (-1..1), or null = nobody.
const PATH = [
  { t: 0, at: null }, { t: 5, at: [-0.15, -0.05] }, { t: 17, at: [-0.15, -0.05] }, { t: 20, at: [0.12, -0.05] },
  { t: 24, at: null }, { t: 40, at: null },
];
function pathAt(t, path = PATH) {
  for (let i = path.length - 1; i >= 0; i--) {
    if (t < path[i].t) continue;
    const a = path[i], b = path[i + 1];
    if (!a.at) return null;
    if (!b || !b.at) return a.at;
    const u = (t - a.t) / (b.t - a.t);
    return [lerp(a.at[0], b.at[0], u), lerp(a.at[1], b.at[1], u)];
  }
  return null;
}

// NoticeState's share of this: the lagged viewer and the awareness (same rules as NoticeState.cs: delay, rise, afterglow drain).
function notice(settings = {}) {
  const s = { noticeDelay: 0.5, awareRise: 1.0, viewerLag: 0.6, afterglowPerDwell: 0.5, afterglowMin: 1, afterglowMax: 20, ...settings };
  let was = false, dwell = 0, a = 0, afterglow = 1, vx = 0, vy = 0, clock = 0;
  return (dt, at) => {
    const present = !!at;
    if (present && !was) { dwell = 0; vx = at[0]; vy = at[1]; }
    else if (!present && was) afterglow = Math.min(Math.max(dwell * s.afterglowPerDwell, s.afterglowMin), s.afterglowMax);
    was = present;
    if (present) {
      dwell += dt;
      const k = 1 - Math.exp(-dt / s.viewerLag);
      vx += (at[0] - vx) * k; vy += (at[1] - vy) * k;
      if (dwell >= s.noticeDelay) a = Math.min(a + dt / s.awareRise, 1);
    } else a = Math.max(a - dt / afterglow, 0);
    clock += dt;
    return { clock, viewerX: vx, viewerY: vy, aware: a * a * (3 - 2 * a), widthStay: 0.22, heightStay: 0.76, ragged: 0.12, widthWobble: 0.25, tilt: 0.1 };
  };
}

// ---- A small world: dots on wavy ribbons streaming left to right at 0.04-0.11 half-heights per second, plus still far dust.
function world(count = 12000, seed = 1) {
  let rs = seed * 9301 + 49297;
  const rnd = () => { rs = (rs * 1103515245 + 12345) % 2147483648; return rs / 2147483648; };
  const ribbons = [
    { r: 2, y: -0.42, th: 0.22, depthF: 0.0, ph: 3.1 }, { r: 3, y: 0.12, th: 0.1, depthF: 0.29, ph: 1.7 },
    { r: 4, y: 0.62, th: 0.16, depthF: 0.07, ph: 0.3 }, { r: 5, y: 0.95, th: 0.08, depthF: 0.36, ph: 4.0 },
  ];
  const dots = [];
  for (let i = 0; i < count; i++) {
    const dust = i % 6 === 0;
    const rb = ribbons[i % 4];
    dots.push({
      dust, rb, x0: rnd() * 4.4 - 2.2, u: 0.076 * (0.5 + rnd()), g: (rnd() + rnd() + rnd() - 1.5) / 1.5, y0: rnd() * 2.2 - 1.1,
      ribbon: dust ? 0 : rb.r, depthF: dust ? 0.95 : rb.depthF, stag: rnd(), phase: rnd(), rate: rnd(), respJ: rnd(),
      x: 0, y: 0, fx: 1, fy: 0, ox: 0, oy: 0, wx: 0, wy: 0, a: 0.22 + 0.2 * rnd(),
    });
  }
  // The idle place and flow direction at time t (pure, like Idle_Core): ribbons stream and wave, dust only sways a little.
  const place = (d, t) => {
    if (d.dust) { d.x = d.x0 + 0.03 * Math.sin(0.08 * t + d.y0 * 3); d.y = d.y0; d.fx = 1; d.fy = 0; return; }
    const x = ((d.x0 + d.u * t + 2.2) % 4.4 + 4.4) % 4.4 - 2.2;
    const c = (xx) => d.rb.y + 0.07 * Math.sin(1.3 * xx + d.rb.ph + 0.05 * t) + 0.04 * Math.sin(3.1 * xx + 2 * d.rb.ph - 0.11 * t);
    d.x = x; d.y = c(x) + d.g * d.rb.th;
    const sl = (c(x + 0.01) - c(x - 0.01)) / 0.02, l = Math.hypot(1, sl);
    d.fx = 1 / l; d.fy = sl / l;
  };
  return { dots, place };
}

// Runs the visit. dtAt(i) gives each step's dt; onStep(t, n, b, dots) sees every step. Returns stats.
function run({ count = 12000, until = 40, dtAt = () => 1 / 60, path = PATH, terms = BOTH, onStep } = {}) {
  const w = world(count);
  const ns = notice();
  let t = 0, i = 0, nan = 0, oMax = 0, wMax = 0, jump = 0;
  while (t < until) {
    const dt = dtAt(i++);
    t += dt;
    const n = ns(dt, pathAt(t, path));
    const b = body(n);
    for (const d of w.dots) {
      w.place(d, t);
      const ox = d.ox, oy = d.oy;
      step(d, b, n, dt, terms);
      if (!Number.isFinite(d.ox + d.oy + d.wx + d.wy)) nan++;
      oMax = Math.max(oMax, Math.hypot(d.ox, d.oy));
      wMax = Math.max(wMax, Math.hypot(d.wx, d.wy));
      // How fast the offset alone moved the dot this step (the idle motion is not ours to judge).
      jump = Math.max(jump, Math.hypot(d.ox - ox, d.oy - oy) / Math.max(Math.min(dt, K.DT_MAX), 1e-6));
    }
    if (onStep) onStep(t, n, b, w.dots);
  }
  return { nan, oMax, wMax, jump, dots: w.dots };
}

module.exports = { K, BOTH, body, field, step, PATH, pathAt, notice, world, run, smoothstep };

// ---------------------------------------------------------------------------------------------------------------------------
if (require.main === module) {
  let bad = 0;
  const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) bad++; };

  // 0. This copy and Notice_Flow.hlsl have the same constants (Notice_Flow_X <-> K.X; the shape ones come from Notice_Clear.hlsl).
  const src = require('fs').readFileSync(require('path').join(__dirname, '..', 'Assets', '_Project', 'Notice', 'Notice_Flow.hlsl'), 'utf8');
  const hl = Object.fromEntries([...src.matchAll(/#define Notice_Flow_(\w+) ([\d.]+)/g)].map((m) => [m[1], +m[2]]));
  for (const [k, re] of [['GAIN', /Notice_Flow_GAIN\[\w+\] = \{([^}]*)\}/], ['RESP', /Notice_Flow_RESP\[\w+\] = \{([^}]*)\}/]]) hl[k] = src.match(re)[1].split(',').map(Number);
  const clear = require('fs').readFileSync(require('path').join(__dirname, '..', 'Assets', '_Project', 'Notice', 'Notice_Clear.hlsl'), 'utf8');
  for (const [k, name] of [['WOBBLE', 'Notice_Clear_WOBBLE'], ['BREATH', 'Notice_Core_BREATH'], ['WANDER', 'Notice_Clear_WANDER']]) hl[k] = +clear.match(new RegExp('#define ' + name + ' ([\\d.]+)'))[1];
  const differ = Object.keys(K).filter((k) => JSON.stringify(hl[k]) !== JSON.stringify(K[k]));
  check(differ.length === 0, `Notice_Flow.hlsl / Notice_Clear.hlsl and this copy agree on all ${Object.keys(K).length} constants${differ.length ? ' (differ: ' + differ.join(', ') + ')' : ''}`);

  // 1. The linear core alone (a constant push, then nothing): stable and lightly overshooting at every dt, including past DT_MAX.
  // Past DT_MAX the step is clamped, so a very slow frame rate reacts slower than real time (that is the point: no blow-up).
  for (const dt of [1 / 240, 1 / 60, 1 / 30, 0.1, 0.25]) {
    for (const resp of [0.6, 1.4 * K.FAR_SLOW * 1.2]) {
      const q = { ox: 0, oy: 0, wx: 0, wy: 0 };
      const ret = Math.max(K.RETURN, K.RETURN_RATIO * resp);
      let peak = 0, under = 0;
      for (let t = 0; t < 40; t += dt) {
        const d = Math.min(dt, K.DT_MAX);
        const target = (t < 10 ? 0.1 : 0) - q.ox / ret;
        q.wx += (target - q.wx) * (1 - Math.exp(-d / resp));
        q.ox += q.wx * d;
        if (t < 10) peak = Math.max(peak, q.ox);
        else under = Math.min(under, q.ox);
      }
      const steady = 0.1 * ret;
      check(peak < steady * 1.15 && -under < steady * 0.15 && Number.isFinite(q.ox),
        `linear: dt ${dt.toFixed(4)} resp ${resp.toFixed(2)}: overshoot ${(peak / steady * 100 - 100).toFixed(1)}%, undershoot after release ${(-under / steady * 100).toFixed(1)}%`);
    }
  }

  // 2. The whole field along the scripted visit, at several frame rates and with a ragged frame rate.
  const runs = {};
  for (const [name, dtAt] of [['144 Hz', () => 1 / 144], ['60 Hz', () => 1 / 60], ['30 Hz', () => 1 / 30], ['10 Hz', () => 0.1],
    ['ragged 5-100 ms', (i) => 0.005 + 0.095 * ((Math.sin(i * 12.9898) * 43758.5453) % 1 + 1) % 1]]) {
    const samples = {};
    const r = run({ count: 4000, dtAt, onStep: (t, n, b, dots) => {
      for (const at of [7, 10, 15, 23, 26, 30, 38]) if (!samples[at] && t >= at) samples[at] = dots.reduce((s, d) => s + Math.hypot(d.ox, d.oy), 0) / dots.length;
    } });
    runs[name] = samples;
    check(r.nan === 0 && r.oMax <= K.O_MAX + 1e-9 && r.wMax <= K.W_MAX + 1e-9,
      `${name}: no NaN, |o| max ${r.oMax.toFixed(3)} <= ${K.O_MAX}, |w| max ${r.wMax.toFixed(3)} <= ${K.W_MAX}`);
    check(r.jump <= K.W_MAX + 1e-6, `${name}: the offset never moves a dot faster than W_MAX (fastest ${r.jump.toFixed(3)} half-heights/s)`);
    check(samples[38] < 0.002, `${name}: 14 s after leaving the mean offset is back to ${samples[38].toFixed(4)} (< 0.002)`);
  }
  // The same visit at different frame rates should look the same: mean offset within 15% of the 144 Hz run once settled. (Not
  // during the first second: a slow frame rate samples the entry up to two frames late, which shifts the onset, not the reaction.)
  for (const name of Object.keys(runs)) {
    const worst = Math.max(...[10, 15, 23].map((at) => Math.abs(runs[name][at] - runs['144 Hz'][at]) / Math.max(runs['144 Hz'][at], 1e-6)));
    check(worst < 0.15, `${name}: mean offset within ${(worst * 100).toFixed(1)}% of 144 Hz at 10 / 15 / 23 s`);
  }

  // 3. A jump of the viewer (snap to the other side of the screen) and fast in-out: offsets stay continuous and bounded.
  const jumpy = [{ t: 0, at: null }, { t: 2, at: [-0.4, 0] }, { t: 8, at: [-0.4, 0] }, { t: 8.0001, at: [0.4, 0.2] }, { t: 12, at: [0.4, 0.2] }];
  for (let k = 0; k < 10; k++) jumpy.push({ t: 12 + k * 0.6, at: k % 2 ? null : [0.1 * k - 0.4, 0] });
  jumpy.push({ t: 18, at: null }, { t: 40, at: null });
  const rj = run({ count: 4000, path: jumpy });
  check(rj.nan === 0 && rj.oMax <= K.O_MAX + 1e-9 && rj.jump <= K.W_MAX + 1e-6,
    `viewer snap + fast in-out: no NaN, |o| max ${rj.oMax.toFixed(3)}, fastest offset move ${rj.jump.toFixed(3)} half-heights/s`);

  // 4. A long stay (60 s): settles, no dot pinned at O_MAX, and the core keeps dots (not a hole).
  const long = [{ t: 0, at: [-0.15, -0.05] }, { t: 70, at: [-0.15, -0.05] }];
  let pinned = 0, inside = 0, insideIdle = 0;
  run({ count: 12000, until: 65, path: long, onStep: (t, n, b, dots) => {
    if (t < 60) return;
    for (const d of dots) {
      if (Math.hypot(d.ox, d.oy) > K.O_MAX * 0.99) pinned++;
      if (field(d.x + d.ox, d.y + d.oy, b, n).s < 0) inside++;
      if (field(d.x, d.y, b, n).s < 0) insideIdle++;
    }
  } });
  const keep = inside / Math.max(insideIdle, 1);
  check(pinned === 0, `long stay: ${pinned} dot-steps pinned at O_MAX in the last 5 s`);
  check(keep > 0.3 && keep < 0.9, `long stay: the body keeps ${(keep * 100).toFixed(0)}% of its idle dots (between 30% and 90%: thinner, not empty)`);

  // 5. A dot aimed at the middle of the body is turned: compare its path with and without the field.
  const aimed = (terms) => {
    const w = world(1);
    const d = Object.assign(w.dots[0], { dust: false, rb: { y: -0.05, th: 0, ph: 0 }, x0: -1.4, u: 0.076, g: 0, ribbon: 2, depthF: 0, stag: 0, phase: 0, rate: 0, respJ: 0.5 });
    const ns = notice();
    let maxOff = 0;
    for (let t = 0; t < 26; t += 1 / 60) {
      const n = ns(1 / 60, [-0.15, -0.05]);
      w.place(d, t);
      step(d, body(n), n, 1 / 60, terms);
      maxOff = Math.max(maxOff, Math.hypot(d.ox, d.oy));
    }
    return maxOff;
  };
  for (const [name, terms] of [['avoid only', { avoid: true, slide: false }], ['slide only', { avoid: false, slide: true }], ['both', BOTH]])
    check(aimed(terms) > 0.05, `${name}: a dot aimed at the middle is moved off its idle path by up to ${aimed(terms).toFixed(3)} half-heights`);

  console.log(bad ? `${bad} check(s) failed` : 'all checks passed');
  process.exit(bad ? 1 : 0);
}
