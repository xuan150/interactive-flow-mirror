// Renders Idle / Clear / Flow at one moment of the scripted visit on the real idle shape (idle.js), one row per hold mode.
// Usage: node render.js <out.png> [at=15] [holds=live,all] [count=93000]
'use strict';
const fs = require('fs'), zlib = require('zlib');
const { M, rand, idle, screen, noticeState, clearPush, CAM_Z, TANH } = require('./idle.js');
const [out, atArg = '15', holdsArg = 'live,all', countArg = '93000'] = process.argv.slice(2);
const AT = +atArg, holds = holdsArg.split(','), N = +countArg, dt = 1 / 30;

const CRC = new Uint32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc32 = (b) => { let c = 0xffffffff; for (const x of b) c = CRC[(c ^ x) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const chunk = (type, data) => { const l = Buffer.alloc(4); l.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([l, td, c]); };
function writePng(file, w, h, rgb) {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3);
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}
// Idle_Palette, with the ribbon's place in it (Color Spread 0.8 in Main).
const PAL = [[0.137, 0.227, 0.475], [0.396, 0.655, 0.922], [0.639, 0.545, 0.910], [0.851, 0.647, 0.859], [0.945, 0.722, 0.773], [1.0, 0.835, 0.647]];
const RC = [0.12, 0.22, 0.52, 0.8, 0.3, 0.95];
const pal = (x) => { x = Math.min(Math.max(x, 0), 1) * 5; const i = Math.min(Math.floor(x), 4), f = x - i; return [0, 1, 2].map((c) => PAL[i][c] + (PAL[i + 1][c] - PAL[i][c]) * f); };
const colOf = (r, dust) => { const c = pal(0.5 + (RC[r] - 0.5) * 0.8); if (!dust) return c; const g = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]; return c.map((v) => v + (g - v) * 0.6); };

const { hybrid3Step } = require('./hybrid.js');
const PW = 640, PH = 320, COLS = 4;
const W = PW * COLS, H = PH * holds.length;
const img = new Float32Array(W * H * 3);
const ids = [];
for (let id = 0; ids.length < N; id++) if (rand(id, 8) >= 0.07) ids.push(id);

holds.forEach((hold, row) => {
  const hy = ids.map((id) => ({ x: 0, y: 0, fx: 1, fy: 0, ox: 0, oy: 0, wx: 0, wy: 0, ribbon: 0, depthF: 0, stag: rand(id, 320), phase: rand(id, 321), rate: rand(id, 322), respJ: rand(id, 323) }));
  const st = ids.map((id) => ({ x: 0, y: 0, fx: 1, fy: 0, ox: 0, oy: 0, wx: 0, wy: 0, ribbon: 0, depthF: 0, stag: rand(id, 320), phase: rand(id, 321), rate: rand(id, 322), respJ: rand(id, 323) }));
  const ns = noticeState();
  let t = 0, n, nn, nPrev = null;
  while (t < AT - 1e-6) {
    t += dt;
    n = ns(dt, M.pathAt(t));
    const clock = hold === 'live' ? n.clock : 0;
    nn = { ...n, clock };
    const b = M.body(nn), last = t >= AT - 1e-6, prevN = nPrev;
    nPrev = nn;
    ids.forEach((id, i) => {
      const P = idle(id, clock, hold === 'shape' ? t : clock);
      const scale = (P.z - CAM_Z) * TANH, q = st[i];
      q.x = P.x / scale; q.y = P.y / scale; q.fx = P.fx; q.fy = P.fy; q.ribbon = P.r; q.depthF = Math.min(Math.max((P.z - 4) / 14, 0), 1);
      M.step(q, b, nn, dt);
      const h = hy[i]; Object.assign(h, { x: q.x, y: q.y, fx: q.fx, fy: q.fy, ribbon: q.ribbon, depthF: q.depthF });
      const h3 = hybrid3Step(h, P, id, nn, prevN, b, dt), hk = h3.k;
      if (!last) return;
      const c = clearPos(P, id, nn);
      const shots = [[P.x, P.y, 1], [c.x, c.y, c.k], [P.x + q.ox * scale, P.y + q.oy * scale, 1], [P.x + h3.dx * scale, P.y + h3.dy * scale, hk]];
      const col = colOf(P.r, P.dust);
      shots.forEach(([x, y, k], col_i) => {
        const [sx, sy, kh] = screen(x, y, P.z, clock);
        const px = Math.floor((sx + 2) / 4 * PW), py = Math.floor((1 - sy) / 2 * PH);
        if (px < 0 || py < 0 || px >= PW || py >= PH) return;
        const a = P.alpha * k * kh * 0.5, o = ((row * PH + py) * W + col_i * PW + px) * 3;
        img[o] += col[0] * a; img[o + 1] += col[1] * a; img[o + 2] += col[2] * a;
      });
    });
  }
  // A small yellow cross where the world thinks the viewer is (not drawn in Unity).
  for (let c = 0; c < COLS; c++) {
    const px = Math.floor((nn.viewerX * 2 + 2) / 4 * PW), py = Math.floor((1 - nn.viewerY) / 2 * PH);
    for (let d = -4; d <= 4; d++) for (const [dx, dy] of [[d, 0], [0, d]]) { const o = ((row * PH + py + dy) * W + c * PW + px + dx) * 3; img[o] += 0.8; img[o + 1] += 0.7; }
  }
});
function clearPos(P, id, n) { const p = { x: P.x, y: P.y, z: P.z }; const k = clearPush(p, id, n); return { x: p.x, y: p.y, k }; }

const rgb = Buffer.alloc(W * H * 3), bg = [8, 10, 22];
for (let i = 0; i < W * H; i++) for (let c = 0; c < 3; c++) rgb[i * 3 + c] = Math.min(255, bg[c] + 255 * (1 - Math.exp(-img[i * 3 + c] * 1.4)));
for (let y = 0; y < H; y++) for (let c = 1; c < COLS; c++) { const o = (y * W + c * PW) * 3; rgb[o] = rgb[o + 1] = rgb[o + 2] = 90; }
for (let r = 1; r < holds.length; r++) for (let x = 0; x < W; x++) { const o = (r * PH * W + x) * 3; rgb[o] = rgb[o + 1] = rgb[o + 2] = 90; }
writePng(out, W, H, rgb);
console.log('wrote', out, 'columns: idle, clear, flow, blend; rows:', holds.join(', '));
