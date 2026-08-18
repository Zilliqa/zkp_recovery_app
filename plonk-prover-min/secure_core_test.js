// Self-test of the secure crypto path on a THROWAWAY, publicly-known test mnemonic
// (the canonical BIP-39 all-zero vector — holds no funds). Proves two things:
//   1. a correct (old,new,domain) triple produces a proof that verifies, and
//   2. the proof is genuinely BOUND: verifying it against a tampered new/domain FAILS.
// MINIMAL circuit, PLONK variant. Needs circuit_final.zkey in this folder (download from the bucket).
// PLONK proving is heavy — run with a large heap:  node --max-old-space-size=16384 secure_core_test.js
const snarkjs = require('snarkjs');
const bip39s = require('@scure/bip39');
const { HDKey } = require('@scure/bip32');
const crypto = require('crypto');
const fs = require('fs');
const ACCT = 0;
const P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;
const MN = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

(async () => {
  const seed = bip39s.mnemonicToSeedSync(MN, '');
  const master = HDKey.fromMasterSeed(seed);
  const account = master.derive(`m/44'/313'/${ACCT}'/0'/0'`); // account key (…/0'/0')
  const parent  = master.derive(`m/44'/313'/${ACCT}'/0'`);    // parent node fed to the circuit
  const old = crypto.createHash('sha256').update(Buffer.from(account.publicKey)).digest().subarray(12);
  const oldF = BigInt('0x' + old.toString('hex'));
  const newF = BigInt('0x00112233445566778899aabbccddeeff00112233'); // arbitrary throwaway destination
  const dom = 32769n % P; // Zilliqa EVM mainnet chainId as domain
  const msb = b => { let a = []; for (const x of b) for (let i = 7; i >= 0; i--) a.push((x >> i) & 1); return a; };
  const input = {
    parentPriv: msb(Buffer.from(parent.privateKey)),
    parentCC:   msb(Buffer.from(parent.chainCode)),
    expectedAddr: oldF.toString(), newAddr: newF.toString(), domain: dom.toString(),
  };

  console.log('old  addr : 0x' + old.toString('hex') + "  (account " + ACCT + ", parent m/44'/313'/" + ACCT + "'/0')");
  console.log('new  addr : 0x' + newF.toString(16).padStart(40, '0'));
  console.log('domain    : ' + dom.toString());
  console.log('proving (in memory, PLONK — slow)...');
  const { proof, publicSignals } = await snarkjs.plonk.fullProve(input, 'circuit_js/circuit.wasm', 'circuit_final.zkey');
  const vk = JSON.parse(fs.readFileSync('vk.json'));

  const okGood = await snarkjs.plonk.verify(vk, publicSignals, proof);
  const tNew = publicSignals.slice(); tNew[1] = (BigInt(tNew[1]) ^ 1n).toString();
  const okTamperNew = await snarkjs.plonk.verify(vk, tNew, proof);
  const tDom = publicSignals.slice(); tDom[2] = (BigInt(tDom[2]) ^ 1n).toString();
  const okTamperDom = await snarkjs.plonk.verify(vk, tDom, proof);

  console.log('public signals [old,new,domain]:', publicSignals);
  console.log('1) correct triple verifies :', okGood);
  console.log('2) tampered NEW rejected   :', okTamperNew === false);
  console.log('3) tampered DOMAIN rejected:', okTamperDom === false);
  const pass = okGood && okTamperNew === false && okTamperDom === false;
  console.log(pass ? '\nSELF-TEST PASSED — binding confirmed.' : '\nSELF-TEST FAILED');
  process.exit(pass ? 0 : 1);
})();
