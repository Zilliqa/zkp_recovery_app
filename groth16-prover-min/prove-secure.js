// HARDENED local prover (MINIMAL circuit). Run OFFLINE. Mnemonic via masked stdin; never argv/env/file.
// Off-circuit: PBKDF2 + derive the level-4 parent node (auto-detecting the wallet's derivation style).
// In-circuit: only the final CKD step (hardened Ledger 0', or non-hardened BIP-44 /i) -> address,
// bound to newAddr + domain.  usage (via run-proof-secure.sh): node prove-secure.js <oldAddr> <newAddr> <domain>
const snarkjs = require('snarkjs');
const bip39s = require('@scure/bip39');
const { validateMnemonic } = bip39s;
const { HDKey } = require('@scure/bip32');
const { bech32 } = require('@scure/base');
let classic = null; try { classic = require('bip39'); } catch (e) {}
const crypto = require('crypto');
// Every BIP-39 wordlist @scure/bip39 ships. Checksum validation is MANDATORY and wordlist-agnostic:
// a mnemonic is accepted only if it checksums against exactly one of these (see F-2026-19003).
const WORDLISTS = {
  czech:                 require('@scure/bip39/wordlists/czech.js').wordlist,
  english:               require('@scure/bip39/wordlists/english.js').wordlist,
  french:                require('@scure/bip39/wordlists/french.js').wordlist,
  italian:               require('@scure/bip39/wordlists/italian.js').wordlist,
  japanese:              require('@scure/bip39/wordlists/japanese.js').wordlist,
  korean:                require('@scure/bip39/wordlists/korean.js').wordlist,
  portuguese:            require('@scure/bip39/wordlists/portuguese.js').wordlist,
  spanish:               require('@scure/bip39/wordlists/spanish.js').wordlist,
  'simplified-chinese':  require('@scure/bip39/wordlists/simplified-chinese.js').wordlist,
  'traditional-chinese': require('@scure/bip39/wordlists/traditional-chinese.js').wordlist,
};
function detectMnemonicLanguages(mnemonic) {
  return Object.entries(WORDLISTS).filter(([, wl]) => validateMnemonic(mnemonic, wl)).map(([name]) => name);
}
const fs = require('fs');
const MAX_ACCT = 100;   // Ledger:  scan account n in m/44'/313'/n'/0'/0'
const STD_ACCT = 5;     // BIP-44:   scan account a in m/44'/313'/a'/0/i
const STD_IDX  = 100;   // BIP-44:   scan address_index i in m/44'/313'/a'/0/i
const P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

const oldArg = (process.argv[2] || '').trim();
const newArg = (process.argv[3] || '').trim();
const domArg = (process.argv[4] || '').trim();
if (!oldArg || !newArg || !domArg) { console.error('usage: ./run-proof-secure.sh <oldAddr> <newAddr> <domain>   (mnemonic typed at a hidden prompt)'); process.exit(1); }

// Decode a Zilliqa bech32 address with FULL checksum + HRP validation (BIP-173). @scure/base's
// bech32.decodeToBytes throws on a bad checksum, invalid character, or non-canonical padding; we then
// require the 'zil' HRP so a valid address from another network can't be silently accepted. F-2026-18999.
function bech32dec(s){
  const { prefix, bytes } = bech32.decodeToBytes(s);
  if (prefix !== 'zil') throw new Error(`expected a "zil" address, got HRP "${prefix}"`);
  return Buffer.from(bytes);
}
function addr20(a){
  const isHex = a.startsWith('0x') || /^[0-9a-fA-F]{40}$/.test(a);
  let w;
  try { w = isHex ? Buffer.from(a.replace(/^0x/,''),'hex') : bech32dec(a); }
  catch(e){ console.error('ERROR: bad address "'+a+'": '+(e && e.message ? e.message : e)); process.exit(1); }
  if(!w||w.length!==20){console.error('ERROR: bad address "'+a+'": expected 20 bytes, got '+(w?w.length:0));process.exit(1);}
  return w;
}
function domField(s){let v;try{v=BigInt(s);}catch(e){console.error('ERROR: bad domain: '+s);process.exit(1);}return((v%P)+P)%P;}

function askHidden(promptText){return new Promise((resolve,reject)=>{const stdin=process.stdin;
  // Only masks input when stdin is a real interactive terminal. If it isn't (piped/redirected, or a
  // non-native TTY like Windows Git Bash/MinTTY), typed characters would be ECHOED IN CLEARTEXT, so we
  // REFUSE rather than silently expose the mnemonic — unless explicitly overridden for automated tests
  // (ALLOW_ECHOED_MNEMONIC=1). See F-2026-19001.
  const canMask=!!stdin.isTTY && typeof stdin.setRawMode==='function';
  if(!canMask && !process.env.ALLOW_ECHOED_MNEMONIC){
    reject(new Error('Refusing to prompt: stdin is not an interactive terminal (TTY), so the mnemonic '+
      'would be echoed in cleartext. Run this in a real terminal, or set ALLOW_ECHOED_MNEMONIC=1 to '+
      'proceed anyway (e.g. for automated tests).'));return;}
  process.stderr.write(promptText);
  if(canMask)stdin.setRawMode(true);stdin.resume();stdin.setEncoding('utf8');let buf='';
  const finish=()=>{if(canMask)stdin.setRawMode(false);stdin.pause();stdin.removeListener('data',onData);process.stderr.write('\n');resolve(buf);};
  const onData=chunk=>{for(const ch of chunk){const c=ch.charCodeAt(0);
    if(c===13||c===10||c===4){finish();return;}else if(c===3){if(canMask)stdin.setRawMode(false);process.stderr.write('\n');process.exit(1);}
    else if(c===127||c===8){buf=buf.slice(0,-1);}else buf+=ch;}};
  stdin.on('data',onData);});}

(async () => {
  const wantOld = addr20(oldArg), wantNew = addr20(newArg), dom = domField(domArg);
  const mnemonic = (await askHidden('Enter mnemonic (hidden): ')).trim().replace(/\s+/g, ' ');
  const languages = detectMnemonicLanguages(mnemonic);
  if (languages.length === 0) {
    console.error(`ERROR: BIP-39 checksum invalid in every supported wordlist (${Object.keys(WORDLISTS).join(', ')}) - likely a typo. Aborting.`);
    process.exit(1);
  }
  if (languages.length > 1) {
    console.error(`ERROR: mnemonic validates against multiple wordlists (${languages.join(', ')}) - ambiguous. Aborting.`);
    process.exit(1);
  }
  const pass = await askHidden('Passphrase (blank if none): ');

  const seed = bip39s.mnemonicToSeedSync(mnemonic, pass);
  const master = HDKey.fromMasterSeed(seed);
  const sha20 = node => crypto.createHash('sha256').update(Buffer.from(node.publicKey)).digest().subarray(12);

  // Auto-detect the derivation style. Ledger (all-hardened) first, then standard BIP-44.
  let found = null;
  for (let n = 0; n < MAX_ACCT && !found; n++) {
    if (Buffer.compare(sha20(master.derive(`m/44'/313'/${n}'/0'/0'`)), wantOld) === 0)
      found = { isHardened: 1, parent: master.derive(`m/44'/313'/${n}'/0'`), addrIndex: 0, label: `m/44'/313'/${n}'/0'/0' (Ledger, all-hardened)` };
  }
  for (let a = 0; a < STD_ACCT && !found; a++) for (let i = 0; i < STD_IDX && !found; i++) {
    if (Buffer.compare(sha20(master.derive(`m/44'/313'/${a}'/0/${i}`)), wantOld) === 0)
      found = { isHardened: 0, parent: master.derive(`m/44'/313'/${a}'/0`), addrIndex: i, label: `m/44'/313'/${a}'/0/${i} (standard BIP-44)` };
  }
  if (!found) { console.error(`ERROR: this seed does not derive the given OLD address (Ledger n<${MAX_ACCT}, or BIP-44 a<${STD_ACCT}/i<${STD_IDX}).`); process.exit(1); }
  const parent = found.parent;

  const msb = b => { let a = []; for (const x of b) for (let i = 7; i >= 0; i--) a.push((x >> i) & 1); return a; };
  const input = {
    parentPriv: msb(Buffer.from(parent.privateKey)),
    parentCC: msb(Buffer.from(parent.chainCode)),
    addrIndex: String(found.addrIndex),
    isHardened: String(found.isHardened),
    expectedAddr: BigInt('0x' + wantOld.toString('hex')).toString(),
    newAddr: BigInt('0x' + wantNew.toString('hex')).toString(),
    domain: dom.toString()
  };
  console.error('checksum OK (' + languages[0] + ' wordlist) + address matched.');
  console.error('  old (proven)  : 0x' + wantOld.toString('hex'));
  console.error('  matched path  : ' + found.label + '   (isHardened=' + found.isHardened + ')');
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
})().catch((e) => { console.error('ERROR:', e && e.message ? e.message : e); process.exit(1); });
