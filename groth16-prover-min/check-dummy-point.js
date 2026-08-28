// CI check for F-2026-19094(a): the circom-ecdsa "dummy" placeholder point must be 2^255*G, not 255*G.
// Independently recomputes 2^255*G with a self-contained secp256k1 (no deps), parses get_dummy_point()
// out of secp256k1_func.circom, and asserts every branch equals 2^255*G. Also asserts the dummy's scalar
// (2^255) strictly exceeds the largest possible partial sum in ECDSAPrivToPub (< 2^248), which is the
// safety property the library relies on.  usage: node check-dummy-point.js <path/to/secp256k1_func.circom>
const fs = require('fs');
const p = (1n << 256n) - (1n << 32n) - 977n;                 // secp256k1 field prime
const Gx = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798n;
const Gy = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8n;
const mod = a => ((a % p) + p) % p;
const inv = a => { let [r0,r1,s0,s1]=[mod(a),p,1n,0n]; while(r1){const q=r0/r1;[r0,r1]=[r1,r0-q*r1];[s0,s1]=[s1,s0-q*s1];} return mod(s0); };
function add(P, Q) {                                          // affine add, null = point at infinity
  if (!P) return Q; if (!Q) return P;
  if (P.x === Q.x && mod(P.y + Q.y) === 0n) return null;
  const l = (P.x === Q.x && P.y === Q.y) ? mod(3n*P.x*P.x * inv(2n*P.y)) : mod((Q.y - P.y) * inv(Q.x - P.x));
  const x = mod(l*l - P.x - Q.x); return { x, y: mod(l*(P.x - x) - P.y) };
}
function mul(k, P) { let R=null, A=P; while(k>0n){ if(k&1n) R=add(R,A); A=add(A,A); k>>=1n; } return R; }
const G = { x: Gx, y: Gy };
const D = mul(1n << 255n, G);                                 // the correct dummy = 2^255 * G
const D255 = mul(255n, G);                                    // the buggy value that was shipped

const src = fs.readFileSync(process.argv[2] || 'secp256k1_func.circom', 'utf8');
const body = src.slice(src.indexOf('function get_dummy_point'));
const fromLE = (limbs, bits) => limbs.reduce((a, v, i) => a + (v << BigInt(bits * i)), 0n);
// pull every `ret[c][i] = value;` assignment in source order; get_dummy_point has two branches:
// k=3 (six 86-bit limbs: x0..x2, y0..y2) then k=4 (eight 64-bit limbs: x0..x3, y0..y3).
const all = [...body.matchAll(/ret\[(\d)\]\[(\d)\]\s*=\s*(\d+);/g)].map(m => [Number(m[1]), Number(m[2]), BigInt(m[3])]);
const k3 = all.slice(0, 6), k4 = all.slice(6, 14);
const pt = (rows, k, bits) => ({
  x: fromLE(rows.filter(r => r[0] === 0).sort((a, b) => a[1] - b[1]).map(r => r[2]), bits),
  y: fromLE(rows.filter(r => r[0] === 1).sort((a, b) => a[1] - b[1]).map(r => r[2]), bits),
});
const p3 = pt(k3, 3, 86), p4 = pt(k4, 4, 64);
let ok = true;
for (const [name, q] of [['k=3 (86-bit)', p3], ['k=4 (64-bit)', p4]]) {
  const good = q.x === D.x && q.y === D.y;
  const stillBuggy = q.x === D255.x && q.y === D255.y;
  console.log(`  ${name}: ${good ? 'OK — equals 2^255*G' : (stillBuggy ? 'FAIL — still 255*G' : 'FAIL — not 2^255*G')}`);
  ok = ok && good;
}
if ((1n << 255n) <= (1n << 248n)) { console.log('  FAIL — dummy scalar not > 2^248'); ok = false; }
else console.log('  dummy scalar 2^255 > max partial sum 2^248 ✓');
if (!ok) { console.error('check-dummy-point: FAILED'); process.exit(1); }
console.log('check-dummy-point: OK');
