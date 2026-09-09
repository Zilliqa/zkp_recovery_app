// Generate a REAL proof with dry-run/final.zkey and assemble the exact claim() calldata the Flutter
// app would emit (selector 0xcf1c9461 + a,b,c + 4 public inputs). domain=32769 to match anvil --chain-id 32769.
const base = '../../groth16-prover-min/node_modules';
const snarkjs = require(base + '/snarkjs');
const bip39s = require(base + '/@scure/bip39');
const { HDKey } = require(base + '/@scure/bip32');
const crypto = require('crypto'); const fs = require('fs');
const P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;
const MN = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const DOMAIN = 32769n;                                   // must equal block.chainid on anvil
const NEW = BigInt('0x00112233445566778899aabbccddeeff00112233'); // dstAddress to observe
const msb = b => { let a=[]; for (const x of b) for (let i=7;i>=0;i--) a.push((x>>i)&1); return a; };
const sha20 = n => crypto.createHash('sha256').update(Buffer.from(n.publicKey)).digest().subarray(12);
const WASM='../../groth16-prover-min/circuit_js/circuit.wasm';
const ZKEY=process.env.ZKEY || '../../groth16-prover-min/circuit_final.zkey'; // production key: download from the bucket, or set ZKEY=
const pad=h=>BigInt(h).toString(16).padStart(64,'0');
(async()=>{
  const m=HDKey.fromMasterSeed(bip39s.mnemonicToSeedSync(MN,''));
  const leaf=m.derive("m/44'/313'/0'/0'/0'"); const parent=m.derive("m/44'/313'/0'/0'");
  const old=sha20(leaf);
  const input={ parentPriv:msb(Buffer.from(parent.privateKey)), parentCC:msb(Buffer.from(parent.chainCode)),
    addrIndex:'0', isHardened:'1', expectedAddr:BigInt('0x'+old.toString('hex')).toString(),
    newAddr:NEW.toString(), domain:DOMAIN.toString() };
  const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, WASM, ZKEY);
  const cd = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  const [a,b,c,pub] = JSON.parse('['+cd+']');
  // flatten in the claim() ABI order: a[0],a[1], b[0][0],b[0][1],b[1][0],b[1][1], c[0],c[1], pub[0..3]
  const words=[a[0],a[1], b[0][0],b[0][1],b[1][0],b[1][1], c[0],c[1], ...pub];
  const calldata='0xcf1c9461'+words.map(pad).join('');
  const out={ oldAddr:'0x'+old.toString('hex'), newAddr:'0x'+NEW.toString(16).padStart(40,'0'),
    domain:DOMAIN.toString(), publicSignals, calldata };
  fs.writeFileSync('/tmp/escrow-e2e/claim.json', JSON.stringify(out,null,2));
  console.log('oldAddr  :', out.oldAddr, '(expect 0xb413df42a4e2d5236fe1b914a21c354eb86f133c)');
  console.log('newAddr  :', out.newAddr);
  console.log('pub      :', publicSignals);
  console.log('calldata :', calldata.slice(0,42)+'…('+((calldata.length-2)/2)+' bytes)');
  // sanity: verify off-chain
  const vk=JSON.parse(fs.readFileSync((process.env.VK || '../../groth16-prover-min/vk.json')));
  console.log('offchain verify:', await snarkjs.groth16.verify(vk, publicSignals, proof));
})().catch(e=>{console.error(e);process.exit(1);});
