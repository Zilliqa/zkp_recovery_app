// Formats the UltraHonk proof + public inputs for on-chain submission to the HonkVerifier and
// the claim contract, and writes calldata_proof.txt / calldata_pubs.txt. Prints instructions only.
const fs = require('fs');
if (!fs.existsSync('target/proof') || !fs.existsSync('target/public_inputs')) {
  console.error('target/proof / target/public_inputs not found — run a proof first.'); process.exit(1);
}
const proof = fs.readFileSync('target/proof');
const pi = fs.readFileSync('target/public_inputs'); // 96 bytes = 3 x bytes32
const proofHex = '0x' + proof.toString('hex');
const pubs = [0, 1, 2].map(i => '0x' + pi.subarray(i * 32, (i + 1) * 32).toString('hex'));
fs.writeFileSync('calldata_proof.txt', proofHex);
fs.writeFileSync('calldata_pubs.txt', '[' + pubs.join(',') + ']');

const V = process.env.ZIL_VERIFIER || '<VERIFIER_ADDRESS>';
const RPC = process.env.ZIL_RPC || '<RPC_URL>';
const L = console.log;
L('\n================ SUBMIT YOUR PROOF (UltraHonk) ================');
L('Verifier (HonkVerifier) : ' + V + (V.startsWith('0x') ? '' : '   (set ZIL_VERIFIER=0x... to fill in)'));
L('Public inputs [expectedOld, newAddr, domain]:');
pubs.forEach((p, i) => L('  [' + i + '] ' + p));
L('Wrote calldata_proof.txt (' + proof.length + ' bytes proof) and calldata_pubs.txt.');
L('\nA) Read-only verify:');
L('     cast call ' + V + ' \\');
L('       "verify(bytes,bytes32[])(bool)" \\');
L('       "$(cat calldata_proof.txt)" "$(cat calldata_pubs.txt)" \\');
L('       --rpc-url ' + RPC);
L('\nB) Or paste calldata_proof.txt / calldata_pubs.txt into verify(...) in Remix.');
L('\nC) To CLAIM (state-changing): call your remediation/claim contract, which MUST read');
L('   old/new/domain from the public inputs (pubs[0..2]) and call verify() itself —');
L('   never accept the destination as a separate, unbound argument:');
L('     cast send <CLAIM_CONTRACT> "claim(bytes,bytes32[])" \\');
L('       "$(cat calldata_proof.txt)" "$(cat calldata_pubs.txt)" \\');
L('       --rpc-url ' + RPC + ' --private-key <KEY>');
L('   Inside claim(): require(pubs[2]==DOMAIN); require(verify(proof,pubs)); migrate old -> new.');
L('\nCost note: UltraHonk verify() is ~2.58M gas + calldata (~14.7 KB proof). One-time per claim.');
L('calldata files reveal nothing about the seed and are safe to move to a networked machine.');
