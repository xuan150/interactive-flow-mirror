// How dark the idle alone makes a body-sized region now and then: body (s < 0) over its surroundings (0.2..0.6 outside), for the
// fixed-size body (no wobble) placed across the screen, every second from 5 to 35 s. Normalized by the median.
'use strict';
const { M, rand, idle, screen, CAM_Z, TANH } = require('./idle.js');
const N = 93000, ids = [];
for (let id = 0; ids.length < N; id++) if (rand(id, 8) >= 0.07) ids.push(id);
const n0 = { clock: 0, aware: 1, widthStay: 0.22, heightStay: 0.76, ragged: 0, widthWobble: 0, tilt: 0 };
const centers = [];
for (let x = -1.4; x <= 1.41; x += 0.35) for (const y of [-0.15, 0, 0.15]) centers.push([x / 2, y]);
const r = [];
for (let t = 5; t <= 35; t += 1) {
  const pts = ids.map((id) => { const P = idle(id, t, t); const [x, y] = screen(P.x, P.y, P.z, t); return [x, y, P.alpha]; });
  for (const [vx, vy] of centers) {
    const b = { t: 0, A: 0.22, B: 0.76, r: 0.22, cx: vx * 2, cy: vy, sn: 0, cs: 1 };
    let body = 0, near = 0;
    for (const [x, y, w] of pts) {
      if (Math.abs(x - b.cx) > 1 || Math.abs(y - b.cy) > 1.5) continue;
      const s = M.field(x, y, b, { ...n0, viewerX: vx, viewerY: vy }).s;
      if (s < 0) body += w; else if (s >= 0.2 && s < 0.6) near += w;
    }
    if (near > 0) r.push(body / near);
  }
}
const sorted = r.slice().sort((a, b) => a - b), med = sorted[Math.floor(sorted.length / 2)];
const pct = (p) => (sorted[Math.floor(p * (sorted.length - 1))] / med).toFixed(2);
console.log(JSON.stringify({ samples: r.length, p1: pct(0.01), p5: pct(0.05), p10: pct(0.1), p25: pct(0.25), p75: pct(0.75), p95: pct(0.95) }));
// The same ratio at the scripted viewer's spot only, over time (does the idle itself swing that much right there?).
