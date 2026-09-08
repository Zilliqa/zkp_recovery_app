#!/usr/bin/env node
// Sheet-based anvil demo: deploy the escrow and lodge for the 3 committed example claims, so you can
// paste their calldata into the Google Form/Sheet and drive the REAL relay.js against anvil.
//   setup:   node sheet_demo.js            (deploy + lodge; prints the 3 calldata + escrow address)
//   verify:  node sheet_demo.js --verify   (assert each destination got paid)
// Requires anvil on chain id 32769 and `(cd ../e2e && forge build)` first.
import { ethers } from 'ethers';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:8545';
const DEPLOYER_PK = process.env.DEPLOYER_PK || '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const ART = path.join(HERE, '..', 'e2e', 'out', 'escrow_v1.sol', 'EscrowInit.json');
const PROXY_ART = path.join(HERE, '..', 'e2e', 'out', 'ERC1967Proxy.sol', 'ERC1967Proxy.json');
const EXAMPLES = path.join(HERE, 'examples.json');
const DEMO = path.join(HERE, '.demo.json');
const VERIFY = process.argv.includes('--verify');

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const net = await provider.getNetwork();
  if (net.chainId !== 32769n) throw new Error(`anvil chain id is ${net.chainId}, expected 32769 — anvil --chain-id 32769`);
  const art = JSON.parse(fs.readFileSync(ART, 'utf8'));

  if (VERIFY) {
    const demo = JSON.parse(fs.readFileSync(DEMO, 'utf8'));
    const escrow = new ethers.Contract(demo.escrow, art.abi, provider);
    let ok = true;
    for (const c of demo.claims) {
      const drained = (await escrow.balanceOf(c.oldAddr)) === 0n;
      const delta = (await provider.getBalance(c.newAddr)) - BigInt(c.dstBefore);
      const pass = drained && delta === BigInt(c.amountWei);
      ok &&= pass;
      console.log(`${c.newAddr}: +${ethers.formatEther(delta)} ZIL (want ${ethers.formatEther(c.amountWei)}), src drained=${drained} -> ${pass ? 'OK' : 'FAIL'}`);
    }
    if (!ok) { console.error('\n❌ verify FAILED'); process.exit(1); }
    console.log('\n✅ all claims paid out to their proof-bound destinations');
    return;
  }

  for (const p of [ART, PROXY_ART]) if (!fs.existsSync(p)) throw new Error(`missing ${p} — run: (cd ../e2e && forge build)`);
  const claims = JSON.parse(fs.readFileSync(EXAMPLES, 'utf8'));
  const proxyArt = JSON.parse(fs.readFileSync(PROXY_ART, 'utf8'));

  // Deploy like production: impl + ERC1967 proxy (empty init data).
  const deployer = new ethers.NonceManager(new ethers.Wallet(DEPLOYER_PK, provider));
  const impl = await new ethers.ContractFactory(art.abi, art.bytecode.object, deployer).deploy();
  await impl.waitForDeployment();
  const proxy = await new ethers.ContractFactory(proxyArt.abi, proxyArt.bytecode.object, deployer)
    .deploy(await impl.getAddress(), '0x');
  await proxy.waitForDeployment();
  const escrowAddr = await proxy.getAddress();
  const escrow = new ethers.Contract(escrowAddr, art.abi, deployer);

  // Lodge each example's amount for its legacy source address (impersonated).
  const demo = { escrow: escrowAddr, claims: [] };
  for (const c of claims) {
    await provider.send('anvil_setBalance', [c.oldAddr, ethers.toBeHex(BigInt(c.amountWei) + ethers.parseEther('1'))]);
    await provider.send('anvil_impersonateAccount', [c.oldAddr]);
    const s = await provider.getSigner(c.oldAddr);
    await (await escrow.connect(s).lodge({ value: BigInt(c.amountWei) })).wait();
    await provider.send('anvil_stopImpersonatingAccount', [c.oldAddr]);
    const dstBefore = (await provider.getBalance(c.newAddr)).toString();
    demo.claims.push({ oldAddr: c.oldAddr, newAddr: c.newAddr, amountWei: c.amountWei, dstBefore });
    console.log(`lodged ${ethers.formatEther(c.amountWei)} ZIL for ${c.oldAddr} -> dst ${c.newAddr}`);
  }
  fs.writeFileSync(DEMO, JSON.stringify(demo, null, 2));

  console.log(`\nescrow (proxy): ${escrowAddr}`);
  console.log('\n1) Paste each of these into the Google Form (one submission each):');
  for (const c of claims) console.log(`   ${c.calldata}`);
  console.log('\n2) Run the relayer against your sheet + this escrow:');
  console.log(`   RPC_URL=${RPC_URL} ESCROW_ADDRESS=${escrowAddr} \\`);
  console.log(`   RELAYER_PRIVATE_KEY=${DEPLOYER_PK} \\`);
  console.log('   SHEET_ID=<id> SHEET_GID=<gid> CALLDATA_COL=B CURSOR_FILE=$(mktemp) node ../relay.js');
  console.log('\n3) Verify payouts:  node sheet_demo.js --verify');
}
main().catch((e) => { console.error('sheet_demo failed:', e.message || e); process.exit(1); });
