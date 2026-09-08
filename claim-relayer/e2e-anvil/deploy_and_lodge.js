#!/usr/bin/env node
// Anvil harness step 1: deploy the escrow on a local anvil chain (chain id 32769, matching the RELEASE
// app's hard-coded proof domain), then seed a balance for the legacy source address.
//
// Why impersonation: the escrow's lodge() credits msg.sender, and the source is a Zilliqa *legacy*
// (SHA-256[-20:]) address. On a real EVM chain msg.sender is Keccak-derived, so you could only credit
// that legacy address with a Zilliqa-style tx. Anvil lets us send AS the legacy address
// (anvil_impersonateAccount), which is exactly the "impossible on a real chain" bit this harness exists
// to simulate. (In production the balance is seeded by the zq2 escrow, not by an EVM lodge.)
import { ethers } from 'ethers';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:8545';
// Anvil's default account #0 — deployer + (later) relayer gas payer. Well-known test key, no secrets.
const DEPLOYER_PK = process.env.DEPLOYER_PK || '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const LODGE_WEI = BigInt(process.env.LODGE_WEI || ethers.parseEther('1').toString());
const ARTIFACT = path.join(HERE, '..', 'e2e', 'out', 'escrow_v1.sol', 'EscrowInit.json');
const CLAIM = path.join(HERE, '..', 'e2e', 'claim.json');

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const net = await provider.getNetwork();
  if (net.chainId !== 32769n) {
    throw new Error(`anvil chain id is ${net.chainId}, expected 32769 — start it with: anvil --chain-id 32769`);
  }
  if (!fs.existsSync(ARTIFACT)) throw new Error(`missing ${ARTIFACT} — run: (cd ../e2e && forge build)`);
  if (!fs.existsSync(CLAIM)) throw new Error(`missing ${CLAIM} — run: (cd ../e2e && ZKEY=<path> node gen_calldata.js)`);

  const { oldAddr, newAddr, domain, calldata } = JSON.parse(fs.readFileSync(CLAIM, 'utf8'));
  if (String(domain) !== '32769') throw new Error(`claim.json domain=${domain}, expected 32769`);

  // 1) Deploy the real zq2 escrow implementation (EscrowInit) directly — the proxy is only needed for
  //    upgrades, which this harness doesn't exercise; lodge/claim/balanceOf work on the impl as-is.
  const art = JSON.parse(fs.readFileSync(ARTIFACT, 'utf8'));
  const deployer = new ethers.Wallet(DEPLOYER_PK, provider);
  const factory = new ethers.ContractFactory(art.abi, art.bytecode.object, deployer);
  const escrow = await factory.deploy();
  await escrow.waitForDeployment();
  const escrowAddr = await escrow.getAddress();

  // 2) Seed a balance for the legacy source address, impersonating it so msg.sender == oldAddr.
  await provider.send('anvil_setBalance', [oldAddr, ethers.toBeHex(LODGE_WEI + ethers.parseEther('1'))]); // + gas buffer
  await provider.send('anvil_impersonateAccount', [oldAddr]);
  const oldSigner = await provider.getSigner(oldAddr);
  const lodgeTx = await escrow.connect(oldSigner).lodge({ value: LODGE_WEI });
  await lodgeTx.wait();
  await provider.send('anvil_stopImpersonatingAccount', [oldAddr]);

  const lodged = await escrow.balanceOf(oldAddr);
  if (lodged !== LODGE_WEI) throw new Error(`lodge failed: balanceOf(old)=${lodged}, expected ${LODGE_WEI}`);

  // 3) Emit outputs for the next steps (relay + verify). Snapshot the destination balance BEFORE the
  //    claim so verify_payout can assert the CHANGE — re-runs on shared anvil state then still pass.
  const dstBefore = await provider.getBalance(newAddr);
  fs.writeFileSync(path.join(HERE, '.escrow_addr'), escrowAddr);
  fs.writeFileSync(path.join(HERE, '.dst_before'), dstBefore.toString());
  fs.writeFileSync(path.join(HERE, 'calldata.txt'), calldata + '\n'); // paste-into-Form content / relay source

  console.log('escrow deployed :', escrowAddr);
  console.log('lodged          :', ethers.formatEther(LODGE_WEI), 'ZIL for src', oldAddr);
  console.log('dst (newAddr)   :', newAddr, '(currently', ethers.formatEther(dstBefore), 'ZIL)');
  console.log('calldata written:', path.join(HERE, 'calldata.txt'));
  console.log('\nNext: run relay.js against this escrow (see README), or paste calldata.txt into the Google Form.');
}
main().catch((e) => { console.error('deploy_and_lodge failed:', e.message || e); process.exit(1); });
