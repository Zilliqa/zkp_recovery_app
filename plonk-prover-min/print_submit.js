// Prints instructions to submit proof.json/public.json to the on-chain PLONK verifier / claim contract.
// Address/RPC are read from env (ZIL_VERIFIER, ZIL_RPC) so you can set them after deploy.
// Public signals order: [expectedAddr(old), newAddr, domain]
// PLONK verifier signature: verifyProof(uint256[24] _proof, uint256[3] _pubSignals)
const snarkjs = require('snarkjs');
const fs = require('fs');
(async () => {
  if (!fs.existsSync('proof.json') || !fs.existsSync('public.json')) {
    console.error('proof.json / public.json not found — run a proof first.'); process.exit(1);
  }
  const proof = JSON.parse(fs.readFileSync('proof.json'));
  const pub = JSON.parse(fs.readFileSync('public.json'));
  const cd = await snarkjs.plonk.exportSolidityCallData(proof, pub);
  fs.writeFileSync('calldata.txt', cd);
  // snarkjs PLONK returns the two arrays concatenated: "[<24 proof values>][<pub values>]"
  // (no comma between them, unlike groth16). Insert the separator before JSON-parsing.
  const [pProof, pS] = JSON.parse('[' + cd.replace(/\]\s*\[/, '],[') + ']');
  const addr = process.env.ZIL_VERIFIER || '<VERIFIER_ADDRESS>';
  const rpc = process.env.ZIL_RPC || '<RPC_URL>';
  const aProof = `[${pProof.join(',')}]`;
  const aPub = `[${pS.join(',')}]`;
  const toHexAddr = f => '0x' + BigInt(f).toString(16).padStart(40, '0');
  const L = s => console.log(s);
  L('\n================ SUBMIT YOUR PROOF (PLONK) ================');
  L('Verifier contract : ' + addr + (addr.startsWith('0x') ? '' : '   (set ZIL_VERIFIER=0x... to fill in)'));
  L('Public inputs (order matters):');
  L('   [0] old  (proven) : ' + pS[0] + '   (= ' + toHexAddr(pS[0]) + ')');
  L('   [1] new  (bound)  : ' + pS[1] + '   (= ' + toHexAddr(pS[1]) + ')');
  L('   [2] domain (bound): ' + pS[2]);
  L('');
  L('A) Read-only check that the proof verifies on-chain (Foundry cast):');
  L('   cast call ' + addr + ' \\');
  L('     "verifyProof(uint256[24],uint256[3])(bool)" \\');
  L("     '" + aProof + "' '" + aPub + "' \\");
  L('     --rpc-url ' + rpc);
  L('   (returns true only for THIS exact (old,new,domain) triple)');
  L('');
  L('B) Or paste the contents of calldata.txt into verifyProof(...) in Remix.');
  L('');
  L('C) To actually SUBMIT a claim (state-changing), call your remediation/claim contract');
  L('   with the proof + public-signal arrays above. The contract MUST read old/new/domain');
  L('   from the public-signal array (do NOT pass a destination as a separate, unbound');
  L('   argument — that would reintroduce the redirection hole the binding closes). e.g.:');
  L('     cast send <CLAIM_CONTRACT> \\');
  L('       "claim(uint256[24],uint256[3])" \\');
  L("       '" + aProof + "' '" + aPub + "' \\");
  L('       --rpc-url ' + rpc + ' --private-key <KEY>');
  L('   Inside claim(): require(_pubSignals[2]==DOMAIN); verifyProof(...); then migrate');
  L('   funds of address(_pubSignals[0]) -> address(_pubSignals[1]).');
  L('');
  L('Set env before running to auto-fill:  ZIL_VERIFIER=0x...  ZIL_RPC=https://...');
  L('Files: proof.json, public.json, calldata.txt');
  L('==========================================================\n');
  process.exit(0); // snarkjs PLONK leaves curve worker threads alive; exit explicitly so we don't hang
})();
