// Timing check of Hybrid (Assets/_Project/Notice/Notice_Hybrid.hlsl plus NoticeSensor's letting go): a JS copy of its step, run on
// the real idle shape (idle.js) over the scripted visit, keep the two in step. Run: node docs/notice-diag/hybrid-check.js
// Measures the thin region where the viewer is (alpha-weighted density inside the body, against the plain idle; 1 = the idle) and
// where it is thinnest (the viewer x at which the body zone is emptiest), and checks the four stages:
//   standing: thin, not empty;  walking: the region trails the viewer by 0.5 - 1.5 s and stays thin;
//   stopping: settled within 2.5 s;  leaving: back to 0.9 within 6 s, starting at once (Keep Space off) or after Keep Time (on).
// The idle part leaves out the transfer, the condense, the fly-by and Clear's wake band (see idle.js).
'use strict';
const { M, rand, idle, screen, noticeState, clearPush, CAM_Z, TANH } = require('./idle.js');
const assert = require('assert');

// Notice_Hybrid_* and the Notice_Flow_* it uses; Main's Settings defaults for the timing.
const H = { SHARE_MIN: 0.75, SPRING: 1.5, RESP_REF: 0.8, STAGGER: 0.6, FAR_SLOW: 1.5, DT_MAX: 0.1, O_MAX: 0.8, RESP: [1.4, 1.4, 0.6, 1.0, 0.8, 1.2] };
const S = { follow: 0.25, afterglow: 1, keepTime: 2 };
const ss = M.smoothstep;

// Clear's push for field n at the idle place P, times the dot's share w. Returns the screen-space push and the alpha factor.
function push(P, id, n, w) {
  const scale = (P.z - CAM_Z) * TANH, p = { x: P.x, y: P.y, z: P.z };
  const k = clearPush(p, id, n);
  return { x: (p.x - P.x) / scale * w, y: (p.y - P.y) / scale * w, k: 1 + (k - 1) * w };
}
// One update of one dot, as Notice_Hybrid. q: { ox, oy, wx, wy } (the stored lag and its speed). Returns the final offset and alpha.
function step(q, P, id, n, prev, dt) {
  dt = Math.min(Math.max(dt, 0), H.DT_MAX);
  const depthF = Math.min(Math.max((P.z - 4) / 14, 0), 1), stag = rand(id, 320) * H.STAGGER;
  const share = H.SHARE_MIN + (1 - H.SHARE_MIN) * (0.5 + 0.5 * Math.sin(6.2831853 * (rand(id, 321) + n.clock * (0.04 + 0.08 * rand(id, 322)))));
  const T = push(P, id, n, share * ss(stag, stag + 1 - H.STAGGER, n.stay));
  const Tp = push(P, id, { ...prev, clock: n.clock }, share * ss(stag, stag + 1 - H.STAGGER, prev.stay));
  q.ox -= T.x - Tp.x; q.oy -= T.y - Tp.y;
  const pace = n.stay > 0 || n.longStay > 0 ? S.follow : S.afterglow;
  const resp = Math.max(pace, 1e-3) * H.RESP[P.r] / H.RESP_REF * (1 + (H.FAR_SLOW - 1) * depthF) * (0.8 + 0.4 * rand(id, 323));
  const spring = Math.max(H.SPRING * resp, dt), k = 1 - Math.exp(-dt / resp);
  q.wx += (-q.ox / spring - q.wx) * k; q.wy += (-q.oy / spring - q.wy) * k;
  q.ox += q.wx * dt; q.oy += q.wy * dt;
  const ol = Math.hypot(q.ox, q.oy);
  if (ol > H.O_MAX) { q.ox *= H.O_MAX / ol; q.oy *= H.O_MAX / ol; }
  return { dx: T.x + q.ox, dy: T.y + q.oy, k: T.k };
}

// The scripted visit with NoticeSensor's letting go. Returns rows { t, raw, holeX, atViewer } every 0.25 s from 15 to 32 s.
function run(keepSpace, N = 5000, dt = 1 / 30) {
  const ids = [];
  for (let id = 0; ids.length < N; id++) if (rand(id, 8) >= 0.07) ids.push(id);
  const st = ids.map(() => ({ ox: 0, oy: 0, wx: 0, wy: 0 }));
  const CX = []; for (let x = -0.3; x <= 0.36; x += 0.015) CX.push(+x.toFixed(3));
  const ns = noticeState();
  let t = 0, prev = null, absent = 0, keptStay = 0, keptLong = 0, lastAt = null;
  const rows = [];
  while (t < 32.01) {
    t += dt;
    const at = M.pathAt(t);
    if (at) lastAt = at;
    const o = ns(dt, at);
    absent = o.present ? 0 : absent + dt;
    if (o.present) { keptStay = o.stay; keptLong = o.longStay; }
    const kept = keepSpace && absent < S.keepTime;
    const n = o.present ? o : { ...o, stay: kept ? keptStay : 0, longStay: kept ? keptLong : 0 };
    if (!prev) prev = { ...n, stay: 0, longStay: 0 };
    const sampling = t > 14.99 && Math.abs(t * 4 - Math.round(t * 4)) < dt * 2;
    const bodies = sampling ? CX.map((cx) => M.body({ ...o, viewerX: cx, viewerY: lastAt[1] })) : null;
    const Wi = CX.map(() => 0), Wf = CX.map(() => 0);
    for (let i = 0; i < N; i++) {
      const id = ids[i], P = idle(id, n.clock, n.clock), r = step(st[i], P, id, n, prev, dt);
      if (!sampling) continue;
      const scale = (P.z - CAM_Z) * TANH;
      const [ix, iy, ki] = screen(P.x, P.y, P.z, n.clock), [fx, fy, kf] = screen(P.x + r.dx * scale, P.y + r.dy * scale, P.z, n.clock);
      CX.forEach((_, j) => {
        if (M.field(ix, iy, bodies[j], o).s < 0) Wi[j] += P.alpha * ki;
        if (M.field(fx, fy, bodies[j], o).s < 0) Wf[j] += P.alpha * r.k * kf;
      });
    }
    prev = n;
    if (!sampling) continue;
    const ratio = CX.map((_, j) => Wf[j] / Math.max(Wi[j], 1e-9));
    let jb = 0; ratio.forEach((v, j) => { if (v < ratio[jb]) jb = j; });
    const jv = CX.findIndex((cx) => Math.abs(cx - lastAt[0]) < 0.0075);
    rows.push({ t: +t.toFixed(2), raw: at ? at[0] : null, holeX: CX[jb], atViewer: ratio[jv] });
  }
  return rows;
}

const at = (rows, t) => rows.find((r) => Math.abs(r.t - t) < 0.01);
const off = run(false);
const standing = (at(off, 16).atViewer + at(off, 16.5).atViewer + at(off, 17).atViewer) / 3;
// While walking (0.09 viewer x per second), how far behind the thinnest place is, in seconds.
const walk = off.filter((r) => r.t >= 18.49 && r.t <= 20.01).map((r) => (r.raw - r.holeX) / 0.09);
const lag = walk.reduce((a, b) => a + b, 0) / walk.length;
const settled = off.find((r) => r.t > 20 && r.atViewer <= standing + 0.05);
const back = off.find((r) => r.t > 24 && r.atViewer >= 0.9);
console.log(`standing ${standing.toFixed(2)}; walking: trails by ${lag.toFixed(2)} s (up to ${Math.max(...off.filter((r) => r.t >= 18.49 && r.t <= 20.01).map((r) => r.atViewer)).toFixed(2)} on the viewer's own spot, which is ahead of it)`);
console.log(`stopped at 20 s: settled at ${settled && settled.t} s; left at 24 s: 25 s ${at(off, 25).atViewer.toFixed(2)}, back to 0.9 at ${back && back.t} s`);
assert(standing > 0.3 && standing < 0.65, 'standing: thin but not empty');
assert(lag > 0.5 && lag < 1.5, 'walking: trails the viewer by 0.5 - 1.5 s');
assert(settled && settled.t <= 22.5, 'stopping: settled within 2.5 s');
assert(at(off, 25).atViewer > at(off, 24).atViewer + 0.05, 'leaving: starts filling in at once');
assert(back && back.t <= 30, 'leaving: back to 0.9 within 6 s');

const keep = run(true);
const backK = keep.find((r) => r.t > 24 && r.atViewer >= 0.9);
console.log(`Keep Space on (${S.keepTime} s): 25.5 s ${at(keep, 25.5).atViewer.toFixed(2)}, back to 0.9 at ${backK && backK.t} s`);
assert(at(keep, 25.5).atViewer < standing + 0.1, 'Keep Space: the space is still there before Keep Time is over');
assert(backK && backK.t <= 24 + S.keepTime + 6, 'Keep Space: back to 0.9 within 6 s of letting go');
console.log('all checks passed');
