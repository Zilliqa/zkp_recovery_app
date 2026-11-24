#!/usr/bin/env node
// verify_calldata.js — standalone offline validator for escrow claim() calldata from the ZKP app.
//
// Give it ONE claim() calldata string. It mirrors exactly what the on-chain escrow claim() checks:
//   1) chain-id binding : pubSignals[2] == <mainnet chainId>   (the escrow's "Invalid domain" gate)
//   2) proof validity   : verifyProof(a,b,c,pubSignals) against the PRODUCTION ceremony VK
//      (the bundled vk.json — all 26 constants identical to the ZQ2 escrow verifier.sol on-chain)
// Both must hold for the calldata to be accepted. No network, no files to prepare.
//
// Usage:
//   node verify_calldata.js <0xcf1c9461...>
//   node verify_calldata.js <0xcf1c9461...> --domain 33101   # check against a different chain id (e.g. testnet)
//   node verify_calldata.js <0xcf1c9461...> --vk ./other.json # verify with a different key
//   node verify_calldata.js <0xcf1c9461...> --json            # machine-readable output
//
// Exit code: 0 only if BOTH the domain binding holds AND the proof verifies; 1 otherwise; 2 on usage error.

const fs = require('fs');
const path = require('path');

// snarkjs: own node_modules first (after `npm install`), then fall back to sibling prover copies in the repo.
function loadSnarkjs() {
  const candidates = [
    path.join(__dirname, 'node_modules', 'snarkjs'),
    path.join(__dirname, '..', 'ceremony', 'node_modules', 'snarkjs'),
    path.join(__dirname, '..', 'groth16-prover-min', 'node_modules', 'snarkjs'),
    'snarkjs',
  ];
  for (const p of candidates) { try { return require(require.resolve(p)); } catch (_) {} }
  throw new Error('snarkjs not found — run `npm install` in this folder first.');
}

const SELECTOR = 'cf1c9461'; // claim(uint256[2],uint256[2][2],uint256[2],uint256[4])
const MAINNET_DOMAIN = '32769'; // ZQ2 mainnet chain id (0x8001)

function parseArgs(argv) {
  const o = { domain: MAINNET_DOMAIN, vk: path.join(__dirname, 'vk.json'), json: false, calldata: null };
  const rest = [];
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--domain') o.domain = argv[++i];
    else if (a === '--vk') o.vk = argv[++i];
    else if (a === '--json') o.json = true;
    else if (a === '-h' || a === '--help') o.help = true;
    else rest.push(a);
  }
  o.calldata = rest[0] || null;
  if (rest.length > 1) throw new Error(`expected a single calldata argument, got ${rest.length}. Quote it as one string.`);
  return o;
}

const USAGE =
  'Usage: node verify_calldata.js <0xcf1c9461...calldata>  [--domain <chainId>] [--vk <path>] [--json]\n' +
  '  Verifies ONE escrow claim() calldata string offline: chain-id binding (default ' + MAINNET_DOMAIN +
  ' = ZQ2 mainnet) + Groth16 proof against the bundled production verification key.';

// Split the claim() calldata into the four ABI arguments, undoing snarkjs' exportSolidityCallData layout.
function decodeCalldata(raw) {
  let hex = String(raw).trim().replace(/\s+/g, '').toLowerCase();
  if (hex.startsWith('0x')) hex = hex.slice(2);
  if (!hex.startsWith(SELECTOR)) throw new Error(`calldata does not start with the claim() selector 0x${SELECTOR}`);
  hex = hex.slice(SELECTOR.length);
  if (hex.length !== 12 * 64) throw new Error(`expected 12 x 32-byte words (${12 * 64} hex chars) after the selector, got ${hex.length}`);
  if (!/^[0-9a-f]+$/.test(hex)) throw new Error('calldata contains non-hex characters');
  const w = [];
  for (let i = 0; i < 12; i++) w.push(BigInt('0x' + hex.slice(i * 64, i * 64 + 64)).toString());

  // word order: [0,1]=a  [2,3,4,5]=b  [6,7]=c  [8,9,10,11]=pubSignals
  // exportSolidityCallData SWAPS each G2 (Fp2) coefficient pair; undo it to rebuild the snarkjs proof.
  const proof = {
    pi_a: [w[0], w[1], '1'],
    pi_b: [[w[3], w[2]], [w[5], w[4]], ['1', '0']],
    pi_c: [w[6], w[7], '1'],
    protocol: 'groth16',
    curve: 'bn128',
  };
  return { proof, publicSignals: [w[8], w[9], w[10], w[11]] };
}

const toAddr = (dec) => '0x' + BigInt(dec).toString(16).padStart(40, '0');

(async () => {
  let o;
  try { o = parseArgs(process.argv); } catch (e) { console.error('ERROR:', e.message, '\n\n' + USAGE); process.exit(2); }
  if (o.help || !o.calldata) { console.error(USAGE); process.exit(o.help ? 0 : 2); }

  const snarkjs = loadSnarkjs();
  const vk = JSON.parse(fs.readFileSync(o.vk, 'utf8'));
  const { proof, publicSignals } = decodeCalldata(o.calldata);

  const domainOnProof = publicSignals[2];
  const domainOk = domainOnProof === String(o.domain);
  const proofOk = await snarkjs.groth16.verify(vk, publicSignals, proof);
  const ok = domainOk && proofOk;

  if (o.json) {
    console.log(JSON.stringify({
      ok, proofValid: proofOk,
      domainBinding: { expected: String(o.domain), onProof: domainOnProof, ok: domainOk },
      oldAddr: toAddr(publicSignals[0]), newAddr: toAddr(publicSignals[1]),
      domain: domainOnProof, isHardened: publicSignals[3], vk: path.basename(o.vk),
    }));
    process.exit(ok ? 0 : 1);
  }

  console.log('old  (proven)  :', toAddr(publicSignals[0]));
  console.log('new  (bound)   :', toAddr(publicSignals[1]));
  console.log('domain (bound) :', domainOnProof, domainOk ? '== expected ' + o.domain + '  OK' : '!= expected ' + o.domain + '  <-- BINDING FAILS');
  console.log('isHardened     :', publicSignals[3]);
  console.log('proof valid    :', proofOk ? 'YES' : 'NO', '(vk: ' + path.basename(o.vk) + ')');
  console.log('RESULT         :', ok ? 'ACCEPT — would pass on-chain claim()' : 'REJECT');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error('ERROR:', e && e.message ? e.message : e); process.exit(1); });
