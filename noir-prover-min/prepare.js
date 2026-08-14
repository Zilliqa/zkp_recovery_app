// Local only. Run OFFLINE. MINIMAL Noir circuit: the seed -> m/44'/313'/n'/0' parent node is
// derived OFF-circuit; the circuit proves only the final hardened step (0') -> address.
// Writes Prover.toml (the nargo input file). Mnemonic from $MNEMONIC (preferred; hidden) or argv.
// usage: node prepare.js [<mnemonic>] <oldAddr 0x..|zil1..> <newAddr> <domain dec|0x> [passphrase]
const bip39 = require('@scure/bip39');
let bip39c = null; try { bip39c = require('bip39'); } catch (e) {} // classic lib for checksum (optional)
const { HDKey } = require('@scure/bip32');
const crypto = require('crypto');
const fs = require('fs');
const pathFull = n => `m/44'/313'/${n}'/0'/0'`;   // full account path (to find which account matches)
const pathParent = n => `m/44'/313'/${n}'/0'`;    // the level-4 parent node fed to the circuit
const MAX_ACCT = 100;
const P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

const envMn = process.env.MNEMONIC;
const a = process.argv.slice(2);
let mnemonic, oldA, newA, domArg, pass;
if (envMn) { mnemonic = envMn; [oldA, newA, domArg, pass] = a; pass = process.env.PASSPHRASE || pass || ''; }
else { [mnemonic, oldA, newA, domArg, pass] = a; pass = pass || ''; }
if (!mnemonic || !oldA || !newA || !domArg) {
  console.error('usage: node prepare.js [<mnemonic>] <oldAddr> <newAddr> <domain dec|0x> [passphrase]  (or set $MNEMONIC)');
  process.exit(1);
}
const mn = mnemonic.trim().replace(/\s+/g, ' ');
if (bip39c && !bip39c.validateMnemonic(mn)) {
  console.error('ERROR: BIP-39 checksum invalid — likely a typo. Aborting.'); process.exit(1);
}
const CH = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
function bech32dec(s){const dp=s.toLowerCase().split('1').pop();const v=[...dp].map(c=>CH.indexOf(c)).slice(0,-6);let acc=0,bits=0,out=[];for(const x of v){acc=(acc<<5)|x;bits+=5;while(bits>=8){bits-=8;out.push((acc>>bits)&0xff);}}return Buffer.from(out);}
function addr20(x){x=x.trim();let w;if(x.startsWith('0x')||/^[0-9a-fA-F]{40}$/.test(x))w=Buffer.from(x.replace(/^0x/,''),'hex');else w=bech32dec(x);if(w.length!==20){console.error('bad address: '+x);process.exit(1);}return w;}
function domField(s){let v=BigInt(s);return ((v % P) + P) % P;}

const wantOld = addr20(oldA), wantNew = addr20(newA), dom = domField(domArg);
const seed = bip39.mnemonicToSeedSync(mn, pass);
const master = HDKey.fromMasterSeed(seed);
const addrAt = n => crypto.createHash('sha256').update(Buffer.from(master.derive(pathFull(n)).publicKey)).digest().subarray(12);
let acct = -1;
for (let n = 0; n < MAX_ACCT; n++) { if (Buffer.compare(addrAt(n), wantOld) === 0) { acct = n; break; } }
if (acct < 0) { console.error(`ERROR: this seed does not derive OLD address 0x${wantOld.toString('hex')} in accounts 0..${MAX_ACCT - 1}.`); process.exit(1); }
const parent = master.derive(pathParent(acct));
const arr = b => '[' + [...b].map(x => `"${x}"`).join(', ') + ']';
fs.writeFileSync('Prover.toml',
  `parent_priv = ${arr(Buffer.from(parent.privateKey))}\n` +
  `parent_cc = ${arr(Buffer.from(parent.chainCode))}\n` +
  `expected_addr = "${BigInt('0x' + wantOld.toString('hex')).toString()}"\n` +
  `new_addr = "${BigInt('0x' + wantNew.toString('hex')).toString()}"\n` +
  `domain = "${dom.toString()}"\n`);
console.error(`old (expected): 0x${wantOld.toString('hex')}  account ${acct}  (parent m/44'/313'/${acct}'/0')`);
console.error(`new (dest)    : 0x${wantNew.toString('hex')}`);
console.error(`domain (field): ${dom.toString()}`);
console.error('Prover.toml written (contains the parent node — sensitive; shred after use).');
