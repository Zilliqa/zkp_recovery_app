// Generate N real production-key proofs for the sheet-based anvil demo. Uses the PUBLIC all-zero BIP-39
// test vector; each example is a different account index (n) → different legacy source address, paying a
// different destination + amount. domain=32769 (anvil --chain-id 32769). Writes examples.json and prints
// the calldata to paste into the Google Form/Sheet.
const BASE = process.env.PROVER || '../../groth16-prover-min';
const snarkjs = require(BASE + '/node_modules/snarkjs');
const bip39s = require(BASE + '/node_modules/@scure/bip39');
const { HDKey } = require(BASE + '/node_modules/@scure/bip32');
const crypto = require('crypto'); const fs = require('fs');
const MN = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const DOMAIN = 32769n;
const WASM = process.env.WASM || (BASE + '/circuit_js/circuit.wasm');
const ZKEY = process.env.ZKEY || (BASE + '/circuit_final.zkey'); // production key: download it, or set ZKEY=
const VK   = process.env.VK   || (BASE + '/vk.json');
const EXAMPLES = [
  { account: 0, newAddr: '0x1111111111111111111111111111111111111111', amountEth: '1' },
  { account: 1, newAddr: '0x2222222222222222222222222222222222222222', amountEth: '2' },
  { account: 2, newAddr: '0x3333333333333333333333333333333333333333', amountEth: '3' },
];
const msb = (b) => { let a = []; for (const x of b) for (let i = 7; i >= 0; i--) a.push((x >> i) & 1); return a; };
const sha20 = (n) => crypto.createHash('sha256').update(Buffer.from(n.publicKey)).digest().subarray(12);
const pad = (h) => BigInt(h).toString(16).padStart(64, '0');
(async () => {
  const m = HDKey.fromMasterSeed(bip39s.mnemonicToSeedSync(MN, ''));
  const vk = JSON.parse(fs.readFileSync(VK));
  const out = [];
  for (const ex of EXAMPLES) {
    const leaf = m.derive(`m/44'/313'/${ex.account}'/0'/0'`);
    const parent = m.derive(`m/44'/313'/${ex.account}'/0'`);
    const old = sha20(leaf);
    const newBig = BigInt(ex.newAddr);
    const input = {
      parentPriv: msb(Buffer.from(parent.privateKey)), parentCC: msb(Buffer.from(parent.chainCode)),
      addrIndex: '0', isHardened: '1', expectedAddr: BigInt('0x' + old.toString('hex')).toString(),
      newAddr: newBig.toString(), domain: DOMAIN.toString(),
    };
    const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, WASM, ZKEY);
    if (!(await snarkjs.groth16.verify(vk, publicSignals, proof))) throw new Error(`verify failed (account ${ex.account})`);
    const [a, b, c, pub] = JSON.parse('[' + (await snarkjs.groth16.exportSolidityCallData(proof, publicSignals)) + ']');
    const words = [a[0], a[1], b[0][0], b[0][1], b[1][0], b[1][1], c[0], c[1], ...pub];
    const calldata = '0xcf1c9461' + words.map(pad).join('');
    const entry = {
      oldAddr: '0x' + old.toString('hex'),
      newAddr: '0x' + newBig.toString(16).padStart(40, '0'),
      amountWei: (BigInt(ex.amountEth) * 10n ** 18n).toString(),
      calldata,
    };
    out.push(entry);
    console.log(`account ${ex.account}: old ${entry.oldAddr}  new ${entry.newAddr}  amount ${ex.amountEth} ZIL`);
    console.log(`  calldata (${(calldata.length - 2) / 2} bytes): ${calldata}`);
  }
  fs.writeFileSync('examples.json', JSON.stringify(out, null, 2));
  console.log(`\nwrote examples.json with ${out.length} claims`);
})().catch((e) => { console.error(e); process.exit(1); });
