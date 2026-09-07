#!/usr/bin/env node
// Anvil harness step 3: assert the relayer actually moved the funds.
//   - balances[oldAddr] in the escrow drained to 0
//   - the bound destination (newAddr) received exactly the lodged amount
import { ethers } from 'ethers';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:8545';
const LODGE_WEI = BigInt(process.env.LODGE_WEI || ethers.parseEther('1').toString());
const escrowAddr = fs.readFileSync(path.join(HERE, '.escrow_addr'), 'utf8').trim();
const { oldAddr, newAddr } = JSON.parse(fs.readFileSync(path.join(HERE, '..', 'e2e', 'claim.json'), 'utf8'));

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const escrow = new ethers.Contract(escrowAddr, ['function balanceOf(address) view returns (uint256)'], provider);
  const remaining = await escrow.balanceOf(oldAddr);
  const dstBal = await provider.getBalance(newAddr);

  const drained = remaining === 0n;
  const paid = dstBal === LODGE_WEI; // newAddr is a fresh address that started at 0
  console.log(`escrow.balances[${oldAddr}] = ${remaining} (want 0)      -> ${drained ? 'OK' : 'FAIL'}`);
  console.log(`balance(${newAddr}) = ${ethers.formatEther(dstBal)} ETH (want ${ethers.formatEther(LODGE_WEI)}) -> ${paid ? 'OK' : 'FAIL'}`);
  if (drained && paid) { console.log('\n✅ e2e PASS — relayer claimed and funds moved to the proof-bound destination'); }
  else { console.error('\n❌ e2e FAIL'); process.exit(1); }
}
main().catch((e) => { console.error('verify_payout failed:', e.message || e); process.exit(1); });
