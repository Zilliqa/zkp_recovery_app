// HARDENED local prover (MINIMAL circuit). Run OFFLINE. Mnemonic via masked stdin; never argv/env/file.
// Off-circuit: PBKDF2 + derive the m/44'/313'/n'/0' parent node (auto-scanning n to match oldAddr).
// In-circuit: only the final hardened step (0') -> address, bound to newAddr + domain.
// usage (via run-proof-secure.sh): node prove-secure.js <oldAddr> <newAddr> <domain>
const snarkjs = require('snarkjs');
const bip39s = require('@scure/bip39');
const { HDKey } = require('@scure/bip32');
let classic = null; try { classic = require('bip39'); } catch (e) {}
const crypto = require('crypto');
const fs = require('fs');
const pathFull = n => `m/44'/313'/${n}'/0'/0'`;
const pathParent = n => `m/44'/313'/${n}'/0'`;
const MAX_ACCT = 100;
const P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

const oldArg = (process.argv[2] || '').trim();
const newArg = (process.argv[3] || '').trim();
const domArg = (process.argv[4] || '').trim();
if (!oldArg || !newArg || !domArg) { console.error('usage: ./run-proof-secure.sh <oldAddr> <newAddr> <domain>   (mnemonic typed at a hidden prompt)'); process.exit(1); }

const CH = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
function bech32dec(s){const dp=s.toLowerCase().split('1').pop();const v=[...dp].map(c=>CH.indexOf(c)).slice(0,-6);
  let acc=0,bits=0,out=[];for(const x of v){acc=(acc<<5)|x;bits+=5;while(bits>=8){bits-=8;out.push((acc>>bits)&0xff);}}return Buffer.from(out);}
function addr20(a){let w;try{w=(a.startsWith('0x')||/^[0-9a-fA-F]{40}$/.test(a))?Buffer.from(a.replace(/^0x/,''),'hex'):bech32dec(a);}catch(e){}
  if(!w||w.length!==20){console.error('ERROR: bad address: '+a);process.exit(1);}return w;}
function domField(s){let v;try{v=BigInt(s);}catch(e){console.error('ERROR: bad domain: '+s);process.exit(1);}return((v%P)+P)%P;}

function askHidden(promptText){return new Promise(resolve=>{const stdin=process.stdin;process.stderr.write(promptText);
  const raw=!!stdin.setRawMode;if(raw)stdin.setRawMode(true);stdin.resume();stdin.setEncoding('utf8');let buf='';
  const finish=()=>{if(raw)stdin.setRawMode(false);stdin.pause();stdin.removeListener('data',onData);process.stderr.write('\n');resolve(buf);};
  const onData=chunk=>{for(const ch of chunk){const c=ch.charCodeAt(0);
    if(c===13||c===10||c===4){finish();return;}else if(c===3){if(raw)stdin.setRawMode(false);process.stderr.write('\n');process.exit(1);}
    else if(c===127||c===8){buf=buf.slice(0,-1);}else buf+=ch;}};
  stdin.on('data',onData);});}

(async () => {
  const wantOld = addr20(oldArg), wantNew = addr20(newArg), dom = domField(domArg);
  const mnemonic = (await askHidden('Enter mnemonic (hidden): ')).trim().replace(/\s+/g, ' ');
  if (classic && !classic.validateMnemonic(mnemonic)) { console.error('ERROR: BIP-39 checksum invalid - likely a typo. Aborting.'); process.exit(1); }
  const pass = await askHidden('Passphrase (blank if none): ');

  const seed = bip39s.mnemonicToSeedSync(mnemonic, pass);
  const master = HDKey.fromMasterSeed(seed);
  const addrAt = n => crypto.createHash('sha256').update(Buffer.from(master.derive(pathFull(n)).publicKey)).digest().subarray(12);
  let acct = -1;
  for (let n = 0; n < MAX_ACCT; n++) { if (Buffer.compare(addrAt(n), wantOld) === 0) { acct = n; break; } }
  if (acct < 0) { console.error(`ERROR: this seed does not derive the given OLD address in accounts 0..${MAX_ACCT - 1}.`); process.exit(1); }
  const parent = master.derive(pathParent(acct));

  const msb = b => { let a = []; for (const x of b) for (let i = 7; i >= 0; i--) a.push((x >> i) & 1); return a; };
  const input = {
    parentPriv: msb(Buffer.from(parent.privateKey)),
    parentCC: msb(Buffer.from(parent.chainCode)),
    expectedAddr: BigInt('0x' + wantOld.toString('hex')).toString(),
    newAddr: BigInt('0x' + wantNew.toString('hex')).toString(),
    domain: dom.toString()
  };
  console.error('checksum + address OK.');
  console.error('  old (proven)  : 0x' + wantOld.toString('hex') + '  (account index ' + acct + ')');
  console.error('  new (bound)   : 0x' + wantNew.toString('hex'));
  console.error('  domain (bound): ' + dom.toString());
  console.error('proving in memory (seed/parent node never hit disk)...');

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, 'circuit_js/circuit.wasm', 'circuit_final.zkey');
  const ok = await snarkjs.groth16.verify(JSON.parse(fs.readFileSync('vk.json')), publicSignals, proof);
  fs.writeFileSync('proof.json', JSON.stringify(proof));
  fs.writeFileSync('public.json', JSON.stringify(publicSignals));
  Buffer.from(seed).fill(0);
  console.log('RESULT:', ok ? 'PROOF VERIFIED - seed ownership of OLD addr, bound to NEW addr + domain' : 'VERIFY FAILED');
  console.log('saved proof.json + public.json (non-sensitive).');
  if (ok) { try { require('child_process').execSync('node print_submit.js', { stdio: 'inherit' }); } catch (e) {} }
  process.exit(ok ? 0 : 1);
})();
