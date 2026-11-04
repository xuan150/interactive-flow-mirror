// Checks the idle VFX files after Unity has imported them (docs/notice.md, "怎麼接的"). Run: node docs/notice-vfx-check.js
// Why: if Idle_Veil.hlsl has a syntax error in an entry function signature when Unity imports, Unity can no longer find that function,
// quietly points the Custom HLSL block at another one (IdleFly), drops the other input slots and SAVES the file. Fixing the HLSL
// afterwards does not bring the wiring back, and HasFloat still says the exposed properties exist. So check the file itself:
//   1. the block calls the expected function, 2. its input slots are in the same order as the function's parameters,
//   3. every slot is linked to an exposed parameter.
// Also useful: git diff --numstat on the .vfx should show almost only added lines, not a re-save.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'Assets', '_Project', 'Idle');
const hlsl = fs.readFileSync(path.join(root, 'Idle_Veil.hlsl'), 'utf8');
const expected = { 'Idle_Veil.vfx': 'IdleVeil', 'Idle_Reflect.vfx': 'IdleVeilReflect', 'Idle_Fly.vfx': 'IdleFly' };

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
    if (!owner || !doc.get(owner) || !/m_ExposedName: /.test(doc.get(owner)) && name !== '_vfx_enabled') problems.push(`slot ${name} is not linked to an exposed parameter`);
  });
  console.log(`${file}: calls ${selected}, ${slotIds.length} slots, ${problems.length ? 'PROBLEMS' : 'ok'}`);
  problems.slice(0, 8).forEach((p) => console.log('  - ' + p));
  bad += problems.length;
}
process.exit(bad ? 1 : 0);
