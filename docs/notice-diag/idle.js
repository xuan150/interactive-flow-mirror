// Port of the idle veil's place of each dot (Idle_Veil.hlsl: Idle_Rand, Idle_Z0, Idle_Center, Idle_At, the ribbon pick, the dust),
// plus NoticeState's clock and weights and Notice_Body's Clear push. Leaves out: the transfer (hops between ribbons, width follow),
// the condense and fly-by events, the horizon-line dots. Values are Main's Inspector values (Depth Drift Period 90, Horizon -0.8).
'use strict';
const M = require('../notice-flow-check.js');

const TAU = 6.2831853, CAM_Z = -14, TANH = 0.3153, HORIZON = -0.8, WAVE = 0.1, SLOPE = -HORIZON * TANH, ZPERIOD = 90;
const ZC = [17, 16, 4, 8, 5, 9], ZA = [1, 1, 4, 4, 4, 4], ZP = [3, 3, 1, 1, 1, 1], RY = [9.3, 12.8, 2.27, 5.55, 6.89, 10.9];
const RW = [5, 5, 9, 9, 9, 9], WM = [3, 3, 1, 1, 1, 1], AM = [3.6, 3.6, 1, 1, 1, 1], SP = [0.3, 0.3, 1, 1, 1, 1];
const RW_SUM = 46, WIDTH = 2.4, THICK = 0.25, TWIST = 1, MOTION = 0.5, FLOW = 0.015, HALO = 2, LINE_SHARE = 0.07;
const DEPTH_Z = 18, FAR_ALPHA = 0.55, MARGIN = 0.25;

const sat = (x) => Math.min(Math.max(x, 0), 1);
const lerp = (a, b, t) => a + (b - a) * t;
const ss = M.smoothstep;
const frac = (x) => x - Math.floor(x);

function pcg(v) {
  const s = (Math.imul(v, 747796405) + 2891336453) >>> 0;
  const w = Math.imul(((s >>> ((s >>> 28) + 4)) ^ s) >>> 0, 277803737) >>> 0;
  return ((w >>> 22) ^ w) >>> 0;
}
const rand = (id, k) => (pcg((Math.imul(id, 9781) + Math.imul(k, 6271)) >>> 0) & 0xffffff) / 16777216;

function z0(r, age) {
  const k = r * 131 + 977, p = age / (ZPERIOD * ZP[r]);
  const a = TAU * (p * (0.8 + 0.4 * rand(k, 1)) + rand(k, 2));
  const b = TAU * (p * (1.9 + 0.6 * rand(k, 3)) + rand(k, 4));
  return ZC[r] + ZA[r] * (0.7 * Math.sin(a) + 0.3 * Math.sin(b));
}
function center(u, r, t, zb) {
  const s = lerp(0.9, 1, sat(zb / 8)), k = zb - CAM_Z;
  const x = (u - 0.5) * 1.6 * k;
  const z = zb + 0.9 * s * Math.sin(TAU * (0.8 * u + 0.3 * r + 0.04 * t));
  const ry = RY[r] * k / (ZC[r] - CAM_Z);
  const y = -SLOPE * (z - CAM_Z) + ry + s * (1.5 * Math.sin(TAU * (0.55 * u + 0.17 * r + 0.05 * t)) + 0.6 * Math.sin(TAU * (1.3 * u - 0.11 * t + 0.37 * r)));
  return [x, y, z];
}
const line = (nx, time) => HORIZON + WAVE * (0.6 * Math.sin(2.1 * nx + 0.05 * time) + 0.4 * Math.sin(5.3 * nx - 0.08 * time + 1.7));

// Idle place of dot id. shapeAge drives the ribbons' shape, depth, twist and the dust's sway; streamAge drives the dots along their
// ribbon (u). Both are the world clock normally. Returns null for a horizon-line dot.
function idle(id, shapeAge, streamAge) {
  if (rand(id, 8) < LINE_SHARE) return null;
  let pick = rand(id, 0) * RW_SUM, r = 0;
  for (; r < 5; r++) { if (pick < RW[r]) break; pick -= RW[r]; }
  const u = frac(rand(id, 1) + streamAge * FLOW * SP[r] * (0.5 + rand(id, 2)));
  const halo = HALO * Math.pow(rand(id, 9), 6);
  const dust = r < 2;
  let x, y, z, fx = 1, fy = 0;
  const tc = shapeAge * MOTION * SP[r], zb = z0(r, shapeAge);
  if (dust) {
    const sx = rand(id, 70) * 2 - 1, sy = rand(id, 71) * 2 - 1, ph = rand(r, 72);
    const nx = sx + 0.12 * Math.sin(TAU * (0.6 * sy + 0.012 * shapeAge + ph)) + 0.06 * Math.sin(TAU * (1.3 * sy - 0.02 * shapeAge + 2 * ph));
    const ny = sy + 0.15 * Math.sin(TAU * (0.5 * sx + 0.015 * shapeAge + 3 * ph));
    z = 17 + 13 * rand(id, 73);
    const dd = z - CAM_Z, scr = lerp(line(nx, shapeAge), 1.05, sat(0.5 + 0.5 * ny));
    x = nx * dd * TANH * 2 * 1.05; y = scr * dd * TANH;
  } else {
    const si = Math.floor(rand(id, 3) * 24);
    const sc = si + 0.5 + 0.8 * (rand(r * 31 + si, 74) - 0.5);
    const v = (((sc + 0.5 * (rand(id, 4) - 0.5)) / 24) * 2 - 1) * (1 + halo);
    const s = lerp(0.9, 1, sat(zb / 8));
    const c = center(u, r, tc, zb), cp = center(u + 0.01, r, tc, zb), cm = center(u - 0.01, r, tc, zb);
    let T = [cp[0] - cm[0], cp[1] - cm[1], cp[2] - cm[2]]; const tl = Math.hypot(...T); T = T.map((q) => q / tl);
    let A = [T[1], -T[0], 0]; const al = Math.hypot(A[0], A[1]); A = [A[0] / al, A[1] / al, 0];
    const B = [T[1] * A[2] - T[2] * A[1], T[2] * A[0] - T[0] * A[2], T[0] * A[1] - T[1] * A[0]];
    const phi = TAU * (TWIST * u + 0.2 * r + 0.06 * tc);
    const W = [0, 1, 2].map((i) => Math.cos(phi) * A[i] + Math.sin(phi) * B[i]);
    const N = [T[1] * W[2] - T[2] * W[1], T[2] * W[0] - T[0] * W[2], T[0] * W[1] - T[1] * W[0]];
    const pinch = 0.5 + 0.5 * Math.sin(TAU * (1.1 * u + 0.23 * r - 0.07 * tc));
    const h = WIDTH * s * WM[r] * (0.3 + 0.7 * pinch);
    const nn = (rand(id, 5) - 0.5) * THICK * s;
    x = c[0] + W[0] * v * h + N[0] * nn; y = c[1] + W[1] * v * h + N[1] * nn; z = c[2] + W[2] * v * h + N[2] * nn;
    // Notice_FlowDir: the middle line's direction on the screen.
    const dx = cp[0] / (cp[2] - CAM_Z) - cm[0] / (cm[2] - CAM_Z), dy = cp[1] / (cp[2] - CAM_Z) - cm[1] / (cm[2] - CAM_Z), dl = Math.hypot(dx, dy);
    if (dl > 1e-6) { fx = dx / dl; fy = dy / dl; }
  }
  const f = sat(z / DEPTH_Z);
  const fade = dust ? 1 : ss(0, 0.12, u) * ss(1, 0.88, u);
  const alpha = fade * (0.6 + 0.4 * rand(id, 6)) * (1 - 0.5 * sat(halo / HALO)) * lerp(1, FAR_ALPHA, f) * AM[r];
  return { x, y, z, r, u, dust, fx, fy, alpha };
}

// The horizon rule (after the notice): a dot that would sink is eased onto the line. Returns the screen place [x, y] and the alpha factor.
function screen(x, y, z, age) {
  const d = z - CAM_Z, lineY = line(x / (d * TANH * 2), age) * d * TANH;
  let sd = y - lineY, k = 1;
  if (sd < MARGIN) { const sd2 = MARGIN * Math.exp((sd - MARGIN) / MARGIN); k = Math.exp(-0.6 * (MARGIN - sd) / MARGIN); y += sd2 - sd; }
  return [x / (d * TANH), y / (d * TANH), k];
}

// NoticeState.Step, default settings.
function noticeState() {
  const S = { noticeDelay: 0.5, hushRise: 1.5, hushHold: 1.5, hushFall: 2.5, hushSlow: 0.25, passingMax: 3, longAfter: 10, rampTime: 4,
    afterglowPerDwell: 0.5, afterglowMin: 1, afterglowMax: 20, viewerLag: 0.6, wakeLag: 2.5, awareRise: 1 };
  let was = false, dwell = 0, hushT = 0, holdT = 0, falling = true, h = 0, a = 0, afterglow = 0, clock = 0, stay = 0, longStay = 0;
  let vx = 0, vy = 0, wx = 0, wy = 0;
  const sm = (x) => x * x * (3 - 2 * x), cl = (v) => Math.min(Math.max(v, -1), 1);
  const approach = (v, tg, up, dn) => (v < tg ? Math.min(v + up, tg) : Math.max(v - dn, tg));
  return (dt, at) => {
    const present = !!at, tx = at ? at[0] : 0, ty = at ? at[1] : 0;
    if (present && !was) { dwell = 0; hushT = 0; holdT = 0; falling = false; vx = cl(tx); vy = cl(ty); wx = vx; wy = vy; }
    else if (!present && was) { afterglow = Math.min(Math.max(dwell * S.afterglowPerDwell, S.afterglowMin), S.afterglowMax); falling = true; }
    was = present;
    if (present) {
      dwell += dt;
      const f = 1 - Math.exp(-dt / S.viewerLag), g = 1 - Math.exp(-dt / S.wakeLag);
      vx += (cl(tx) - vx) * f; vy += (cl(ty) - vy) * f; wx += (cl(tx) - wx) * g; wy += (cl(ty) - wy) * g;
    }
    if (!falling) hushT += dt;
    if (falling || hushT <= S.noticeDelay) h = Math.max(h - dt / S.hushFall, 0);
    else if (h < 1) h = Math.min(h + dt / S.hushRise, 1);
    else { holdT += dt; if (holdT >= S.hushHold) falling = true; }
    const hush = sm(h);
    if (!present) a = Math.max(a - dt / Math.max(afterglow, 1e-4), 0);
    else if (dwell > S.noticeDelay) a = Math.min(a + dt / S.awareRise, 1);
    clock += dt * (1 + (S.hushSlow - 1) * hush);
    const up = dt / S.rampTime, down = dt / (present ? S.rampTime : afterglow);
    stay = approach(stay, present && dwell >= S.passingMax ? 1 : 0, up, down);
    longStay = approach(longStay, present && dwell >= S.longAfter ? 1 : 0, up, down);
    return { clock, stay, longStay, viewerX: vx, viewerY: vy, wakeX: wx, wakeY: wy, aware: sm(a), hush, present,
      widthStay: 0.22, heightStay: 0.76, widthLong: 0.27, heightLong: 0.95, ragged: 0.12, widthWobble: 0.25, tilt: 0.1,
      rim: 0.25, rimEven: 0.2, coreKeep: 0.05, deflect: 0.6 };
  };
}

// Same as Notice_Warp / Notice_WidthScale / Notice_BoxSdf.
const warp = (x, y, t, amp) => [(0.6 * Math.sin(2.7 * y + 0.41 * t + 0.3) + 0.4 * Math.sin(4.9 * y - 0.29 * t + 2.1)) * amp,
  (0.6 * Math.sin(3.1 * x - 0.37 * t + 1.1) + 0.4 * Math.sin(5.7 * x + 0.23 * t + 4.0)) * amp];
const widthScale = (y, b, t, wob) => { const k = y / Math.max(b, 1e-3); return Math.min(Math.max(1 + wob * (0.6 * Math.sin(1.9 * k + 0.31 * t) + 0.4 * Math.sin(3.3 * k - 0.23 * t + 1.7)), 0.5), 1.6); };
const boxSdf = (px, py, ex, ey, r) => { const qx = Math.abs(px) - (ex - r), qy = Math.abs(py) - (ey - r); return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r; };

// Notice_Body with only the Clear bit (Main's orbit shares are 0; the wake band is left out: it only dims while the viewer moves).
// p: { x, y, z } world, moved in place. Returns the alpha factor.
function clearPush(p, id, n) {
  if (n.stay <= 0 && n.longStay <= 0) return 1;
  const t = n.clock, sw = ss(0, 1, n.stay), lw = ss(0, 1, n.longStay);
  const A = lerp(n.widthStay, n.widthLong, lw) * sw * (1 + 0.12 * Math.sin(0.37 * t + 0.6));
  let B = lerp(n.heightStay, n.heightLong, lw) * sw * (1 + 0.12 * Math.sin(0.29 * t + 2.4));
  if (A < 1e-3) return 1;
  B = Math.max(B, 1e-3);
  const scale = (p.z - CAM_Z) * TANH;
  const cx = n.viewerX * 2 + 0.1 * Math.sin(0.21 * t + 1), cy = n.viewerY + 0.1 * Math.sin(0.17 * t + 2);
  const depthF = sat((p.z - 4) / 14);
  const ang = n.tilt * Math.sin(0.23 * t + 1.3), sn = Math.sin(ang), cs = Math.cos(ang);
  const r = Math.min(A * (1 - 0.1 * (0.5 + 0.5 * Math.sin(0.31 * t + 0.9))), 0.9 * B);
  const stayer = rand(id, 310) < n.coreKeep * lerp(1, 3, depthF);
  const takes = lerp(1, 0.8, depthF);
  const slide = Math.min(Math.max(n.deflect, 0), 1.5) * lerp(1, 0.5, depthF) * (1 + 0.25 * (2 * rand(id, 311) - 1));
  const L = A / Math.min(Math.max(n.rim, 0.05), 0.8), D0 = A / 3;
  const px = p.x / scale - cx, py = p.y / scale - cy;
  const prx = cs * px + sn * py, pry = -sn * px + cs * py;
  const wv = widthScale(pry, B, t, n.widthWobble);
  const psx = prx / wv, psy = pry, [wx, wy] = warp(psx, psy, t, n.ragged);
  const pwx = psx + wx * sw, pwy = psy + wy * sw;
  const s = boxSdf(pwx, pwy, A, B, r);
  const d = Math.max(s + A, 0);
  const dp = d < D0 ? A * Math.pow(d / D0, 1 / 3) : d + (A - D0) * (1 - ss(0, 1, (d - D0) / (L - D0)));
  const fs = stayer ? ss(0, 1, d / A) : 1;
  const sgx = pwx >= 0 ? 1 : -1, sgy = pwy >= 0 ? 1 : -1;
  const qx = Math.abs(pwx) - (A - r), qy = Math.abs(pwy) - (B - r), qox = Math.max(qx, 0), qoy = Math.max(qy, 0);
  let nx, ny;
  if (qox + qoy > 0) { const l = Math.hypot(qox, qoy); nx = qox / l * sgx; ny = qoy / l * sgy; } else if (qx > qy) { nx = sgx; ny = 0; } else { nx = 0; ny = sgy; }
  const up = ss(0, 1, 0.5 - nx);
  const shear = -Math.tanh(pwy / (0.5 * B)) * slide * lerp(0.5, 1, up);
  const push = (dp - d) * takes * fs * lerp(0.85, 1, up);
  const wayx = nx + shear * -ny, wayy = ny + shear * nx;
  const xs = sat((d - D0) / (L - D0)), fp = 1 - takes * (A - D0) / (L - D0) * 6 * xs * (1 - xs);
  let k = Math.min(Math.max(Math.pow(Math.max(fp, 1e-3), n.rimEven), 0.4), 1);
  if (stayer) k *= 1 - 0.55 * (1 - fs);
  const drx = wayx * wv * push, dry = wayy * push;
  p.x += (cs * drx - sn * dry) * scale; p.y += (sn * drx + cs * dry) * scale;
  return k;
}

module.exports = { M, rand, idle, screen, noticeState, clearPush, CAM_Z, TANH, sat, lerp };
