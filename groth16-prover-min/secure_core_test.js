// Self-test of the secure crypto path on a THROWAWAY, publicly-known test mnemonic
// (the canonical BIP-39 all-zero vector — holds no funds). Proves three things:
//   1. the Ledger all-hardened path (isHardened=1) verifies,
//   2. the standard BIP-44 non-hardened path (isHardened=0, addrIndex>0) verifies,
//   3. proofs are genuinely BOUND: verifying against a tampered new/domain FAILS.
// MINIMAL configurable circuit: proves the final CKD step from the level-4 parent node.
// Needs circuit_final.zkey in this folder (download from the bucket).  Run: node secure_core_test.js
const snarkjs = require('snarkjs');
const bip39s = require('@scure/bip39');
const { HDKey } = require('@scure/bip32');
const crypto = require('crypto');
const fs = require('fs');
const P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;
const MN = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const dom = 32769n % P;                                    // Zilliqa EVM mainnet chainId as domain
const newF = BigInt('0x00112233445566778899aabbccddeeff00112233'); // arbitrary throwaway destination
const msb = b => { let a = []; for (const x of b) for (let i = 7; i >= 0; i--) a.push((x >> i) & 1); return a; };
const sha20 = node => crypto.createHash('sha256').update(Buffer.from(node.publicKey)).digest().subarray(12);

(async () => {
  const master = HDKey.fromMasterSeed(bip39s.mnemonicToSeedSync(MN, ''));
  const vk = JSON.parse(fs.readFileSync('vk.json'));

  // Build the circuit input for a given wallet style, deriving old = the leaf address.
  function mk(isHardened, acct, idx) {
    const leaf   = isHardened ? master.derive(`m/44'/313'/${acct}'/0'/0'`) : master.derive(`m/44'/313'/${acct}'/0/${idx}`);
    const parent = isHardened ? master.derive(`m/44'/313'/${acct}'/0'`)    : master.derive(`m/44'/313'/${acct}'/0`);
    const old = sha20(leaf);
    return {
      old,
      input: {
        parentPriv: msb(Buffer.from(parent.privateKey)),
        parentCC:   msb(Buffer.from(parent.chainCode)),
        addrIndex:  String(isHardened ? 0 : idx),
        isHardened: String(isHardened),
        expectedAddr: BigInt('0x' + old.toString('hex')).toString(),
        newAddr: newF.toString(), domain: dom.toString(),
      },
    };
  }

  async function proveVerify(tag, isHardened, acct, idx) {
    const { old, input } = mk(isHardened, acct, idx);
    console.log(`\n[${tag}] old ${'0x' + old.toString('hex')}  isHardened=${isHardened} addrIndex=${input.addrIndex}`);
    const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, 'circuit_js/circuit.wasm', 'circuit_final.zkey');
    // public signals order: [old, new, domain, isHardened]
    const okGood = await snarkjs.groth16.verify(vk, publicSignals, proof);
    const tNew = publicSignals.slice(); tNew[1] = (BigInt(tNew[1]) ^ 1n).toString();
    const tDom = publicSignals.slice(); tDom[2] = (BigInt(tDom[2]) ^ 1n).toString();
    const okTNew = await snarkjs.groth16.verify(vk, tNew, proof);
    const okTDom = await snarkjs.groth16.verify(vk, tDom, proof);
    console.log('  signals [old,new,domain,isHardened]:', publicSignals);
    console.log('  correct verifies :', okGood, ' | tampered NEW rejected:', okTNew === false, ' | tampered DOMAIN rejected:', okTDom === false);
    return okGood && okTNew === false && okTDom === false;
  }

  const a = await proveVerify('Ledger  hardened   ', 1, 0, 0);   // m/44'/313'/0'/0'/0'
  const b = await proveVerify('BIP-44  non-hardened', 0, 0, 3);  // m/44'/313'/0'/0/3
  const pass = a && b;
  console.log(pass ? '\nSELF-TEST PASSED — both derivation modes prove & binding confirmed.' : '\nSELF-TEST FAILED');
  process.exit(pass ? 0 : 1);
})();
