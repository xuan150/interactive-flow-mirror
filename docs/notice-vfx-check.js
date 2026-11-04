// Checks the idle VFX files after Unity has imported them (docs/notice.md, "怎麼接的"). Run: node docs/notice-vfx-check.js
// Why: if Idle_Veil.hlsl has a syntax error in an entry function signature when Unity imports, Unity can no longer find that function,
// quietly points the Custom HLSL block at another one (IdleFly), drops the other input slots and SAVES the file. Fixing the HLSL
// afterwards does not bring the wiring back, and HasFloat still says the exposed properties exist. So check the file itself:
//   1. the block calls the expected function, 2. its input slots are in the same order as the function's parameters,
//   3. every slot is linked to an exposed parameter (noticeDt: to a Delta Time (VFX) node),
//   4. the stored attributes Flow keeps (noticeOffset, noticeVelocity) are declared as Vector2 custom attributes of the graph, or the
//      block does not compile, and 5. no HLSL writes the built-in velocity: that would switch on the Update's own Euler integration
//      (position += velocity * dt) on top of the position the block works out.
// Also useful: git diff --numstat on the .vfx should show almost only added lines, not a re-save.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'Assets', '_Project', 'Idle');
const hlsl = fs.readFileSync(path.join(root, 'Idle_Veil.hlsl'), 'utf8');
const expected = { 'Idle_Veil.vfx': 'IdleVeil', 'Idle_Reflect.vfx': 'IdleVeilReflect', 'Idle_Fly.vfx': 'IdleFly' };
const stored = { 'Idle_Veil.vfx': ['noticeOffset', 'noticeVelocity'], 'Idle_Reflect.vfx': ['noticeOffset', 'noticeVelocity'] };

const params = (fn) => {
  const m = hlsl.match(new RegExp('void ' + fn + '\\(([\\s\\S]*?)\\)\\s*\\{'));
  if (!m) throw new Error('cannot parse the signature of ' + fn + ' in Idle_Veil.hlsl (a syntax error such as "voidName"?)');
  return m[1].split(',').map((s) => s.trim()).filter(Boolean).map((s) => s.split(/\s+/).pop()).slice(1);
};

let bad = 0;
for (const [file, fn] of Object.entries(expected)) {
  const parts = fs.readFileSync(path.join(root, file), 'utf8').split(/(?=^--- !u!\d+ &\d+\n)/m);
  const idOf = (d) => (d.match(/^--- !u!\d+ &(\d+)\n/) || [])[1];
  const doc = new Map(parts.map((d) => [idOf(d), d]));
  const block = parts.find((d) => d.includes('UnityEditor.VFX.Block.CustomHLSL'));
  const selected = block.match(/selection: (\w+)/)[1];
  const slotIds = [...block.match(/m_InputSlots:\n((?:  - \{fileID: \d+\}\n)+)/)[1].matchAll(/fileID: (\d+)/g)].map((m) => m[1]);
  const want = params(fn);
  const problems = [];
  if (selected !== fn) problems.push(`the block calls ${selected}, expected ${fn}`);
  if (slotIds.length !== want.length) problems.push(`${slotIds.length} input slots, ${fn} has ${want.length} parameters`);
  slotIds.forEach((id, i) => {
    const d = doc.get(id);
    const name = (d.match(/^    name: (\S+)$/m) || [])[1];
    if (name !== '_' + want[i]) problems.push(`slot #${i} is ${name}, parameter is ${want[i]}`);
    const linked = d.match(/m_LinkedSlots:\n  - \{fileID: (\d+)\}/);
    const out = linked && doc.get(linked[1]);
    const owner = out && (out.match(/m_MasterData:\n    m_Owner: \{fileID: (\d+)\}/) || [])[1];
    const od = owner && doc.get(owner);
    if (name === '_noticeDt') {
      if (!od || !/VFXDynamicBuiltInParameter/.test(od) || !/m_BuiltInParameters: 1\n/.test(od)) problems.push('slot _noticeDt is not linked to a Delta Time (VFX) node');
    } else if (!od || !/m_ExposedName: /.test(od) && name !== '_vfx_enabled') problems.push(`slot ${name} is not linked to an exposed parameter`);
  });
  const list = (parts.find((d) => d.includes('m_CustomAttributes:')).match(/m_CustomAttributes:\n((?:  - \{fileID: \d+\}\n)*)/) || [0, ''])[1];
  const declared = [...list.matchAll(/fileID: (\d+)/g)].map((m) => doc.get(m[1]) || '');
  for (const a of stored[file] || [])
    if (!declared.some((d) => d.includes('m_AttributeName: ' + a + '\n') && /m_Type: 1\n/.test(d))) problems.push(`custom attribute ${a} (Vector2) is not declared`);
  console.log(`${file}: calls ${selected}, ${slotIds.length} slots, ${problems.length ? 'PROBLEMS' : 'ok'}`);
  problems.slice(0, 8).forEach((p) => console.log('  - ' + p));
  bad += problems.length;
}
const notice = path.join(__dirname, '..', 'Assets', '_Project', 'Notice');
const sources = [['Idle_Veil.hlsl', hlsl], ...fs.readdirSync(notice).filter((f) => f.endsWith('.hlsl')).map((f) => [f, fs.readFileSync(path.join(notice, f), 'utf8')])];
for (const [name, text] of sources)
  if (/attributes\.velocity\s*[-+*/]?=(?!=)/.test(text)) { console.log(`${name}: writes attributes.velocity (that adds the Update's Euler integration)`); bad++; }
console.log(`${sources.length} HLSL files: ${bad ? 'see above' : 'none writes attributes.velocity'}`);
process.exit(bad ? 1 : 0);
