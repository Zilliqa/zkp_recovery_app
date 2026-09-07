// Prints instructions to submit proof.json/public.json to the on-chain verifier / claim contract.
// Address/RPC are read from env (ZIL_VERIFIER, ZIL_RPC) so you can set them after deploy.
// Public signals order: [expectedAddr(old), newAddr, domain, isHardened]  (uint[4])
const snarkjs = require('snarkjs');
const fs = require('fs');
(async () => {
  if (!fs.existsSync('proof.json') || !fs.existsSync('public.json')) {
    console.error('proof.json / public.json not found — run a proof first.'); process.exit(1);
  }
  const proof = JSON.parse(fs.readFileSync('proof.json'));
  const pub = JSON.parse(fs.readFileSync('public.json'));
  const cd = await snarkjs.groth16.exportSolidityCallData(proof, pub);
  fs.writeFileSync('calldata.txt', cd);
  const [pA, pB, pC, pS] = JSON.parse('[' + cd + ']');
  const addr = process.env.ZIL_VERIFIER || '<VERIFIER_ADDRESS>';
  const rpc = process.env.ZIL_RPC || '<RPC_URL>';
  const a0 = `[${pA.join(',')}]`;
  const a1 = `[[${pB[0].join(',')}],[${pB[1].join(',')}]]`;
  const a2 = `[${pC.join(',')}]`;
  const a3 = `[${pS.join(',')}]`;
  const toHexAddr = f => '0x' + BigInt(f).toString(16).padStart(40, '0');
  const L = s => console.log(s);
  L('\n================ SUBMIT YOUR PROOF ================');
  L('Verifier contract : ' + addr + (addr.startsWith('0x') ? '' : '   (set ZIL_VERIFIER=0x... to fill in)'));
  L('Public inputs (order matters):');
  L('   [0] old  (proven) : ' + pS[0] + '   (= ' + toHexAddr(pS[0]) + ')');
  L('   [1] new  (bound)  : ' + pS[1] + '   (= ' + toHexAddr(pS[1]) + ')');
  L('   [2] domain (bound): ' + pS[2]);
  L('   [3] isHardened    : ' + pS[3] + '   (1 = Ledger all-hardened path, 0 = standard BIP-44)');
  L('');
  L('A) Read-only check that the proof verifies on-chain (Foundry cast):');
  L('   cast call ' + addr + ' \\');
  L('     "verifyProof(uint256[2],uint256[2][2],uint256[2],uint256[4])(bool)" \\');
  L("     '" + a0 + "' '" + a1 + "' '" + a2 + "' '" + a3 + "' \\");
  L('     --rpc-url ' + rpc);
  L('   (returns true only for THIS exact (old,new,domain) triple)');
  L('');
  L('B) Or paste the contents of calldata.txt into verifyProof(...) in Remix.');
  L('');
  L('C) To actually SUBMIT a claim (state-changing), call your remediation/claim contract');
  L('   with the 4 proof arguments above. The contract MUST read old/new/domain from the');
  L('   public-signal array (do NOT pass a destination as a separate, unbound argument —');
  L('   that would reintroduce the redirection hole this stage closes). e.g.:');
  L('     cast send <CLAIM_CONTRACT> \\');
  L('       "claim(uint256[2],uint256[2][2],uint256[2],uint256[4])" \\');
  L("       '" + a0 + "' '" + a1 + "' '" + a2 + "' '" + a3 + "' \\");
  L('       --rpc-url ' + rpc + ' --private-key <KEY>');
  L('   Inside claim(): require(_pubSignals[2]==DOMAIN); verifyProof(...); then migrate');
  L('   funds of address(_pubSignals[0]) -> address(_pubSignals[1]).');
  L('   _pubSignals[3] is isHardened: for a Ledger biased-nonce address (leaked key), you can');
  L('   require(_pubSignals[3]==1) so a weaker non-hardened proof cannot claim it.');
  L('');
  L('Set env before running to auto-fill:  ZIL_VERIFIER=0x...  ZIL_RPC=https://...');
  L('Files: proof.json, public.json, calldata.txt');
  L('===================================================\n');
})();
