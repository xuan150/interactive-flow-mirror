// Diagnosis of Flow vs Clear on the real idle shape (idle.js). Usage: node diag.js <react: flow|avoid|slide|clear|hybrid|hybrid2|hybrid3> <hold: live|shape|all> [count] [until]
// Prints JSON stats for two windows of the scripted visit: during the hush (7-10.5 s) and after it (11.5-17 s).
'use strict';
const { M, rand, idle, screen, noticeState, clearPush, CAM_Z, TANH } = require('./idle.js');
const K = M.K;

const [react = 'flow', hold = 'live', countArg = '20000'] = process.argv.slice(2);
const N = +countArg, dt = 1 / 30, UNTIL = +(process.argv[5] || 17.01);
const terms = react === 'avoid' ? { avoid: true, slide: false } : react === 'slide' ? { avoid: false, slide: true } : M.BOTH;
const flow = react !== 'clear';
const hyb = react === 'hybrid';
const { hybridStep, hybrid2Step, hybrid3Step } = require('./hybrid.js');
const hyb3 = react === 'hybrid3';
let nPrev = null;
const hyb2 = react === 'hybrid2';
const sampleAt = [];
for (let t = 7; t <= 10.51; t += 0.5) sampleAt.push(+t.toFixed(2));
for (let t = 11.5; t <= 17.01; t += 0.5) sampleAt.push(+t.toFixed(2));
for (let t = 18; t <= 40; t += 1) sampleAt.push(t);
for (const t of [5, 6]) sampleAt.push(t);
const isSample = (t) => sampleAt.some((s) => Math.abs(t - s) < dt / 2);
const willSample = (t) => sampleAt.some((s) => Math.abs(t + dt - s) < dt / 2);

const ids = [];
for (let id = 0; ids.length < N; id++) if (rand(id, 8) >= 0.07) ids.push(id);
const st = ids.map(() => ({ x: 0, y: 0, fx: 1, fy: 0, ox: 0, oy: 0, wx: 0, wy: 0, ribbon: 0, depthF: 0, stag: 0, phase: 0, rate: 0, respJ: 0 }));
ids.forEach((id, i) => Object.assign(st[i], { stag: rand(id, 320), phase: rand(id, 321), rate: rand(id, 322), respJ: rand(id, 323) }));
const prev = new Float64Array(N * 2).fill(NaN);

// Zones by the signed distance to the (fixed-size) body edge; A = 0.22.
const ZONES = [['core (s < -0.6A)', -9, -0.132], ['inner band (-0.6A..0)', -0.132, 0], ['shell (0..0.2)', 0, 0.2], ['near (0.2..0.6)', 0.2, 0.6]];
const zoneOf = (s) => ZONES.findIndex(([, a, b]) => s >= a && s < b);
// A screen grid around the viewer's first spot (x -1.3..0.7, y -1..1), cells of 2/GN half-heights.
const GN = 16;
const cell = (x, y) => { const i = Math.floor((x + 1.3) / 2 * GN), j = Math.floor((y + 1) / 2 * GN); return i >= 0 && j >= 0 && i < GN && j < GN ? j * GN + i : -1; };
const win = (t) => (t < 7 || t > 17.2 ? 'timeline' : t < 11 ? 'hush' : 'after');
const acc = {};
const A = (w) => acc[w] || (acc[w] = { n: 0, Wi: ZONES.map(() => 0), Wf: ZONES.map(() => 0), series: [], off: [], vel: [], along: [], cross: [], spd: [],
  gh: [], tA: 0, tS: 0, tR: 0, tRr: 0, tRt: 0, gR: 0, gT: 0, offR: [], eqR: [], cntT: 0, inR: 0, moved3: 0, moved10: 0 });

const ns = noticeState();
let t = 0;
const T0 = 0;
while (t < UNTIL) {
  t += dt;
  const n = ns(dt, M.pathAt(t));
  const clock = hold === 'live' ? n.clock : T0;
  const shapeAge = clock, streamAge = hold === 'shape' ? t : clock;
  const nn = { ...n, clock };
  const b = M.body(nn);
  const sampling = isSample(t), pre = willSample(t);
  if (!flow && !sampling && !pre) continue;
  const a = sampling ? A(win(t)) : null;
  const Wi = ZONES.map(() => 0), Wf = ZONES.map(() => 0);
  const Gi = new Float64Array(GN * GN), Gf = new Float64Array(GN * GN);
  for (let i = 0; i < N; i++) {
    const id = ids[i], P = idle(id, shapeAge, streamAge);
    const scale = (P.z - CAM_Z) * TANH;
    const q = st[i];
    q.x = P.x / scale; q.y = P.y / scale; q.fx = P.fx; q.fy = P.fy; q.ribbon = P.r;
    q.depthF = Math.min(Math.max((P.z - 4) / 14, 0), 1);
    let spd = NaN;
    if (sampling) spd = Math.hypot(q.x - prev[2 * i], q.y - prev[2 * i + 1]) / dt;
    prev[2 * i] = q.x; prev[2 * i + 1] = q.y;
    let fin = { x: P.x, y: P.y, z: P.z }, kc = 1;
    if (hyb3) {
      const r3 = hybrid3Step(q, P, id, nn, nPrev, b, dt);
      kc = r3.k;
      fin.x += r3.dx * scale; fin.y += r3.dy * scale;
    } else if (hyb2) {
      const r2 = hybrid2Step(q, P, id, nn, b, dt);
      kc = 1 + (r2.k - 1) * r2.w;
      fin.x += r2.dx * scale; fin.y += r2.dy * scale;
    } else if (hyb) {
      kc = hybridStep(q, P, id, nn, b, dt);
      fin.x += q.ox * scale; fin.y += q.oy * scale;
    } else if (flow) {
      if (sampling && nn.aware > 0) {
        // The terms of the goal, before the step (same formulas as M.step).
        const aw = M.smoothstep(q.stag * K.STAGGER, q.stag * K.STAGGER + 1 - K.STAGGER, nn.aware);
        const gain = K.GAIN[q.ribbon] * (1 + (K.FAR_GAIN - 1) * q.depthF) * (1 + K.JITTER * Math.sin(6.2831853 * (q.phase + b.t * (0.04 + 0.08 * q.rate))));
        const resp = K.RESP[q.ribbon] * (1 + (K.FAR_SLOW - 1) * q.depthF) * (0.8 + 0.4 * q.respJ);
        const ret = Math.max(K.RETURN, K.RETURN_RATIO * resp), g = aw * gain;
        const f = M.field(q.x + q.ox, q.y + q.oy, b, nn);
        const h = f.s > 0 ? 1 - M.smoothstep(0, K.REACH, f.s) : M.smoothstep(-K.INNER * b.A, 0, f.s);
        if (g > 0 && h > 0) {
          const ex = f.ny, ey = -f.nx;
          const along = Math.tanh((ex * q.fx + ey * (q.fy + K.FALLBACK * Math.tanh(Math.min(Math.max(f.h, -4), 4)))) / K.SIGN_BAND);
          const Av = terms.avoid ? g * K.AVOID * h : 0, Sv = terms.slide ? g * K.SLIDE * h * along : 0;
          const oR = q.ox * f.nx + q.oy * f.ny, oT = q.ox * ex + q.oy * ey;
          a.tA += Math.abs(Av); a.tS += Math.abs(Sv); a.tR += Math.hypot(q.ox, q.oy) / ret; a.tRr += Math.abs(oR) / ret; a.tRt += Math.abs(oT) / ret;
          a.gR += Math.abs(Av - oR / ret); a.gT += Math.abs(Sv - oT / ret); a.cntT++;
          a.gh.push(g * h);
          if (terms.avoid) { a.offR.push(oR); a.eqR.push(ret * Av); }
        }
      }
      M.step(q, b, nn, dt, terms);
      fin.x += q.ox * scale; fin.y += q.oy * scale;
    } else if (sampling) kc = clearPush(fin, id, nn);
    if (!sampling) continue;
    const [ix, iy, ki] = screen(P.x, P.y, P.z, shapeAge);
    const [fx, fy, kf] = screen(fin.x, fin.y, fin.z, shapeAge);
    const si = M.field(ix, iy, b, nn).s, sf = M.field(fx, fy, b, nn).s;
    const zi = zoneOf(si), zf = zoneOf(sf);
    if (zi >= 0) Wi[zi] += P.alpha * ki;
    if (zf >= 0) Wf[zf] += P.alpha * kc * kf;
    const ci = cell(ix, iy), cf = cell(fx, fy);
    if (ci >= 0) Gi[ci] += P.alpha * ki;
    if (cf >= 0) Gf[cf] += P.alpha * kc * kf;
    if (si < K.REACH) {
      a.inR++;
      a.spd.push(spd);
      const fd = Math.hypot(fx - ix, fy - iy);
      if (fd > 0.03) a.moved3++;
      if (fd > 0.1) a.moved10++;
      a.off.push(fd);
      if (flow) {
        a.vel.push(Math.hypot(q.wx, q.wy));
        a.along.push(Math.abs(q.ox * q.fx + q.oy * q.fy)); a.cross.push(Math.abs(q.ox * q.fy - q.oy * q.fx));
      }
    }
  }
  nPrev = nn;
  if (sampling) { a.n++; ZONES.forEach((_, z) => { a.Wi[z] += Wi[z]; a.Wf[z] += Wf[z]; }); a.series.push({ t, Wi, Wf, Gi, Gf }); }
}

const q = (arr, p) => { if (!arr.length) return NaN; const s = Float64Array.from(arr.filter(Number.isFinite)).sort(); return s[Math.min(s.length - 1, Math.floor(p * s.length))]; };
const mean = (arr) => arr.reduce((s, x) => s + x, 0) / Math.max(arr.length, 1);
const out = { react, hold, N };
for (const [w, a] of Object.entries(acc)) {
  // How much the idle alone changes each zone in 2 s (mean |W(t+2) - W(t)| / mean W), against the change the reaction makes.
  const bg = ZONES.map((_, z) => {
    const s = a.series, d = [];
    for (let i = 0; i < s.length; i++) for (let j = i + 1; j < s.length; j++) if (Math.abs(s[j].t - s[i].t - 2) < 0.01) d.push(Math.abs(s[j].Wi[z] - s[i].Wi[z]));
    return mean(d) / (a.Wi[z] / a.n);
  });
  // Local contrast on the grid: how different the reaction makes the picture from the idle at the same moment, against how much the
  // idle alone changes in 1 s and 2 s. Both as sum |difference| / sum of the idle weight.
  const sum = (g) => g.reduce((x, y) => x + y, 0);
  const effect = mean(a.series.map((r) => sum(r.Gf.map((v, k) => Math.abs(v - r.Gi[k]))) / sum(r.Gi)));
  const lag = (L) => { const d = []; const s = a.series; for (let i = 0; i < s.length; i++) for (let j = i + 1; j < s.length; j++) if (Math.abs(s[j].t - s[i].t - L) < 0.01) d.push(sum(s[j].Gi.map((v, k) => Math.abs(v - s[i].Gi[k]))) / sum(s[i].Gi)); return mean(d); };
  // Does the pattern the reaction makes stay put? Correlation of (Gf - Gi) across the grid between t and t + 2 s (1 = the same
  // pattern in the same place; 0 = unrelated).
  const corr = (x, y) => { const mx = mean(x), my = mean(y); let a = 0, b = 0, c = 0; for (let k = 0; k < x.length; k++) { a += (x[k] - mx) * (y[k] - my); b += (x[k] - mx) ** 2; c += (y[k] - my) ** 2; } return a / Math.sqrt(b * c + 1e-12); };
  const pers = []; { const s = a.series; for (let i = 0; i < s.length; i++) for (let j = i + 1; j < s.length; j++) if (Math.abs(s[j].t - s[i].t - 2) < 0.01) pers.push(corr(Array.from(s[i].Gf, (v, k) => v - s[i].Gi[k]), Array.from(s[j].Gf, (v, k) => v - s[j].Gi[k]))); }
  out[w] = {
    contrast: +mean(a.series.map((r) => ((r.Wf[0] + r.Wf[1]) / r.Wf[3]) / ((r.Wi[0] + r.Wi[1]) / r.Wi[3]))).toFixed(3),
    grid: { persist2s: +mean(pers).toFixed(3), effect: +effect.toFixed(3), idle1s: +lag(1).toFixed(3), idle2s: +lag(2).toFixed(3) },
    density: Object.fromEntries(ZONES.map(([name], z) => [name, +(a.Wf[z] / a.Wi[z]).toFixed(3)])),
    idleChange2s: Object.fromEntries(ZONES.map(([name], z) => [name, +bg[z].toFixed(3)])),
    region: { dots: Math.round(a.inR / a.n), moved_gt_0_03: +(a.moved3 / a.inR).toFixed(3), moved_gt_0_1: +(a.moved10 / a.inR).toFixed(3),
      shift_med: +q(a.off, 0.5).toFixed(3), shift_p90: +q(a.off, 0.9).toFixed(3), idleSpeed_med: +q(a.spd, 0.5).toFixed(3), idleSpeed_p90: +q(a.spd, 0.9).toFixed(3) },
  };
  if (flow) Object.assign(out[w], {
    offset: { vel_med: +q(a.vel, 0.5).toFixed(3), vel_p90: +q(a.vel, 0.9).toFixed(3), along_mean: +mean(a.along).toFixed(3), cross_mean: +mean(a.cross).toFixed(3) },
    terms: { pushed: a.cntT ? +(a.cntT / a.inR).toFixed(3) : 0, gh_med: +q(a.gh, 0.5).toFixed(3), avoid: +(a.tA / a.cntT).toFixed(4), slide: +(a.tS / a.cntT).toFixed(4),
      spring: +(a.tR / a.cntT).toFixed(4), springOut: +(a.tRr / a.cntT).toFixed(4), springAlong: +(a.tRt / a.cntT).toFixed(4),
      goalOut: +(a.gR / a.cntT).toFixed(4), goalAlong: +(a.gT / a.cntT).toFixed(4),
      offOut_mean: +mean(a.offR).toFixed(4), eqOut_mean: +mean(a.eqR).toFixed(4) },
  });
}
out.timeline = acc.timeline ? acc.timeline.series.map((r) => [+r.t.toFixed(1), +(((r.Wf[0] + r.Wf[1]) / r.Wf[3]) / ((r.Wi[0] + r.Wi[1]) / r.Wi[3])).toFixed(2)]) : [];
console.log(JSON.stringify(out));
