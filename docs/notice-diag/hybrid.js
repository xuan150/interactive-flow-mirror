// Prototype of the Clear + Flow blend (proposal only): Clear's push, worked out at the dot's idle place, is the TARGET of the stored
// offset; Flow's dynamics (response time, spring) carry the dot there. Flow's avoid term is gone; its slide stays, only just outside
// the edge. One offset, nothing added on top. q: the Flow state of the dot (see notice-flow-check.js step()); P: its idle place;
// returns Clear's alpha factor at the idle place.
'use strict';
const { M, clearPush, CAM_Z, TANH } = require('./idle.js');
const K = M.K;
const H = { FOLLOW: 1.2, SHARE_MIN: 0.75, SLIDE: 0.12, SHELL: 0.35 };

function hybridStep(q, P, id, n, b, dt) {
  dt = Math.min(Math.max(dt, 0), K.DT_MAX);
  const scale = (P.z - CAM_Z) * TANH;
  const p = { x: P.x, y: P.y, z: P.z };
  const k = clearPush(p, id, n);
  const tx = (p.x - P.x) / scale, ty = (p.y - P.y) / scale;
  // Each dot takes its own, slowly breathing share of the target, so the thin region is never complete nor fixed.
  const share = H.SHARE_MIN + (1 - H.SHARE_MIN) * (0.5 + 0.5 * Math.sin(6.2831853 * (q.phase + b.t * (0.04 + 0.08 * q.rate))));
  const resp = K.RESP[q.ribbon] * (1 + (K.FAR_SLOW - 1) * q.depthF) * (0.8 + 0.4 * q.respJ);
  const follow = Math.max(H.FOLLOW, K.RETURN_RATIO * resp);
  let gx = (tx * share - q.ox) / follow, gy = (ty * share - q.oy) / follow;
  // The slide along the edge, the way the dot's own flow runs, only in a band just outside it.
  const aw = M.smoothstep(q.stag * K.STAGGER, q.stag * K.STAGGER + 1 - K.STAGGER, n.aware);
  const g = aw * K.GAIN[q.ribbon] * (1 + (K.FAR_GAIN - 1) * q.depthF);
  if (g > 0) {
    const f = M.field(q.x + q.ox, q.y + q.oy, b, n);
    const hs = f.s > 0 ? 1 - M.smoothstep(0, H.SHELL, f.s) : 0;
    if (hs > 0) {
      const ex = f.ny, ey = -f.nx;
      const along = Math.tanh((ex * q.fx + ey * (q.fy + K.FALLBACK * Math.tanh(Math.min(Math.max(f.h, -4), 4)))) / K.SIGN_BAND);
      gx += g * H.SLIDE * hs * along * ex; gy += g * H.SLIDE * hs * along * ey;
    }
  }
  const kk = 1 - Math.exp(-dt / resp);
  q.wx += (gx - q.wx) * kk; q.wy += (gy - q.wy) * kk;
  const wl = Math.hypot(q.wx, q.wy);
  if (wl > K.W_MAX) { q.wx *= K.W_MAX / wl; q.wy *= K.W_MAX / wl; }
  q.ox += q.wx * dt; q.oy += q.wy * dt;
  const ol = Math.hypot(q.ox, q.oy);
  if (ol > K.O_MAX) { const ux = q.ox / ol, uy = q.oy / ol; q.ox = ux * K.O_MAX; q.oy = uy * K.O_MAX; const o = q.wx * ux + q.wy * uy; if (o > 0) { q.wx -= o * ux; q.wy -= o * uy; } }
  return k;
}
module.exports = { hybridStep, H };

// Prototype 2: Clear places the dot (its push at the idle place, every frame, so the thin region stays put while the ribbons stream
// through it); Flow only decides how much of that push the dot takes now, w, with inertia. State: q.ox = w, q.wx = its rate.
// Final place = idle + w * push. One offset.
const H2 = { FOLLOW: 1.0, SHARE_MIN: 0.75 };
function hybrid2Step(q, P, id, n, b, dt) {
  dt = Math.min(Math.max(dt, 0), K.DT_MAX);
  const scale = (P.z - CAM_Z) * TANH;
  const p = { x: P.x, y: P.y, z: P.z };
  const k = clearPush(p, id, n);
  const tx = (p.x - P.x) / scale, ty = (p.y - P.y) / scale;
  const aw = M.smoothstep(q.stag * K.STAGGER, q.stag * K.STAGGER + 1 - K.STAGGER, n.aware);
  const share = H2.SHARE_MIN + (1 - H2.SHARE_MIN) * (0.5 + 0.5 * Math.sin(6.2831853 * (q.phase + b.t * (0.04 + 0.08 * q.rate))));
  const resp = K.RESP[q.ribbon] * (1 + (K.FAR_SLOW - 1) * q.depthF) * (0.8 + 0.4 * q.respJ);
  const follow = Math.max(H2.FOLLOW, K.RETURN_RATIO * resp);
  const goal = (aw * share - q.ox) / follow;
  q.wx += (goal - q.wx) * (1 - Math.exp(-dt / resp));
  q.ox = Math.min(Math.max(q.ox + q.wx * dt, 0), 1.2);
  q.oy = 0;
  // Report the offset it makes, in the q.ox / q.oy slots the caller reads, without losing w: return both.
  return { k, dx: q.ox * tx, dy: q.ox * ty, w: q.ox };
}
module.exports.hybrid2Step = hybrid2Step;

// Prototype 3: space from Clear, time from Flow. The dot sits at Clear's place for its idle spot (worked out every frame, so the thin
// region stays put while the ribbons stream through it) plus a lag e (the stored offset). When the FIELD changes (the viewer comes,
// moves, leaves, the body breathes), the dot does not follow at once: e takes the change (Clear's push at the same idle spot, now vs
// last frame) and then eases back to 0 with Flow's response time and spring, so it bends late and drifts home late. A dot that only
// streams through a still field gets no lag. Flow's slide stays, just outside the edge. Final place = idle + push + e; e is the
// dot's lag behind Clear, 0 once things settle, not a second push.
const H3 = { FOLLOW: 1.2, SHARE_MIN: 0.75, SLIDE: 0.12, SHELL: 0.35 };
function pushOf(P, id, n, q, t) {
  const scale = (P.z - CAM_Z) * TANH, p = { x: P.x, y: P.y, z: P.z };
  const k = clearPush(p, id, n);
  const share = H3.SHARE_MIN + (1 - H3.SHARE_MIN) * (0.5 + 0.5 * Math.sin(6.2831853 * (q.phase + t * (0.04 + 0.08 * q.rate))));
  return { x: (p.x - P.x) / scale * share, y: (p.y - P.y) / scale * share, k };
}
function hybrid3Step(q, P, id, n, nPrev, b, dt) {
  dt = Math.min(Math.max(dt, 0), K.DT_MAX);
  const T = pushOf(P, id, n, q, n.clock), Tp = nPrev ? pushOf(P, id, nPrev, q, nPrev.clock) : T;
  q.ox -= T.x - Tp.x; q.oy -= T.y - Tp.y;
  const resp = K.RESP[q.ribbon] * (1 + (K.FAR_SLOW - 1) * q.depthF) * (0.8 + 0.4 * q.respJ);
  const follow = Math.max(H3.FOLLOW, K.RETURN_RATIO * resp);
  let gx = -q.ox / follow, gy = -q.oy / follow;
  const aw = M.smoothstep(q.stag * K.STAGGER, q.stag * K.STAGGER + 1 - K.STAGGER, n.aware);
  const g = aw * K.GAIN[q.ribbon] * (1 + (K.FAR_GAIN - 1) * q.depthF);
  if (g > 0) {
    const f = M.field(q.x + T.x + q.ox, q.y + T.y + q.oy, b, n);
    const hs = f.s > 0 ? 1 - M.smoothstep(0, H3.SHELL, f.s) : 0;
    if (hs > 0) {
      const ex = f.ny, ey = -f.nx;
      const along = Math.tanh((ex * q.fx + ey * (q.fy + K.FALLBACK * Math.tanh(Math.min(Math.max(f.h, -4), 4)))) / K.SIGN_BAND);
      gx += g * H3.SLIDE * hs * along * ex; gy += g * H3.SLIDE * hs * along * ey;
    }
  }
  q.wx += (gx - q.wx) * (1 - Math.exp(-dt / resp)); q.wy += (gy - q.wy) * (1 - Math.exp(-dt / resp));
  const wl = Math.hypot(q.wx, q.wy);
  if (wl > K.W_MAX) { q.wx *= K.W_MAX / wl; q.wy *= K.W_MAX / wl; }
  q.ox += q.wx * dt; q.oy += q.wy * dt;
  const ol = Math.hypot(q.ox, q.oy);
  if (ol > K.O_MAX) { const ux = q.ox / ol, uy = q.oy / ol; q.ox = ux * K.O_MAX; q.oy = uy * K.O_MAX; const o = q.wx * ux + q.wy * uy; if (o > 0) { q.wx -= o * ux; q.wy -= o * uy; } }
  return { k: T.k, dx: T.x + q.ox, dy: T.y + q.oy };
}
module.exports.hybrid3Step = hybrid3Step;
