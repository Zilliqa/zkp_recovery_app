// Local only. Run offline. MINIMAL circuit: the seed -> ... -> level-4 parent node is derived
// OFF-circuit; the circuit proves only the final CKD step (hardened OR non-hardened) -> address.
// Auto-detects the wallet's derivation style and emits `isHardened` + `addrIndex` accordingly:
//   Ledger (all-hardened)  m/44'/313'/n'/0'/0'  -> isHardened=1, parent m/44'/313'/n'/0', addrIndex 0
//   standard BIP-44        m/44'/313'/a'/0/i    -> isHardened=0, parent m/44'/313'/a'/0,   addrIndex i
// usage: node prepare.js "<mnemonic>" <oldAddr 0x..|zil1..> <newAddr> <domain dec|0x> [passphrase]
const bip39=require('@scure/bip39'); const {HDKey}=require('@scure/bip32');
const { bech32 } = require('@scure/base');
const crypto=require('crypto'); const fs=require('fs');
const MAX_ACCT=100;   // Ledger:  scan account n in m/44'/313'/n'/0'/0'
const STD_ACCT=5;     // BIP-44:   scan account a in m/44'/313'/a'/0/i
const STD_IDX=100;    // BIP-44:   scan address_index i in m/44'/313'/a'/0/i
const P=21888242871839275222246405745257275088548364400416034343698204186575808495617n;
const mnemonic=process.argv[2]; const oldA=(process.argv[3]||'').trim(); const newA=(process.argv[4]||'').trim();
const domArg=(process.argv[5]||'').trim(); const pass=process.argv[6]||'';
if(!mnemonic||!oldA||!newA||!domArg){console.error('usage: node prepare.js "<mnemonic>" <oldAddr> <newAddr> <domain dec|0x> [passphrase]');process.exit(1);}
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
  if(w.length!==20){console.error('ERROR: bad address "'+a+'": expected 20 bytes, got '+w.length);process.exit(1);}
  return w;
}
function domField(s){let v=BigInt(s);v=((v%P)+P)%P;return v;}
const wantOld=addr20(oldA); const wantNew=addr20(newA); const dom=domField(domArg);
const seed=bip39.mnemonicToSeedSync(mnemonic,pass);                 // PBKDF2, off-circuit
const master=HDKey.fromMasterSeed(seed);
const sha20=node=>crypto.createHash('sha256').update(Buffer.from(node.publicKey)).digest().subarray(12);

// Find which derivation matches the OLD address. Ledger (all-hardened) first, then standard BIP-44.
let found=null;
for(let n=0;n<MAX_ACCT && !found;n++){
  if(Buffer.compare(sha20(master.derive(`m/44'/313'/${n}'/0'/0'`)),wantOld)===0)
    found={isHardened:1,parent:master.derive(`m/44'/313'/${n}'/0'`),addrIndex:0,label:`m/44'/313'/${n}'/0'/0'  (Ledger, all-hardened)`};
}
for(let a=0;a<STD_ACCT && !found;a++)for(let i=0;i<STD_IDX && !found;i++){
  if(Buffer.compare(sha20(master.derive(`m/44'/313'/${a}'/0/${i}`)),wantOld)===0)
    found={isHardened:0,parent:master.derive(`m/44'/313'/${a}'/0`),addrIndex:i,label:`m/44'/313'/${a}'/0/${i}  (standard BIP-44, non-hardened)`};
}
if(!found){console.error(`ERROR: old address 0x${wantOld.toString('hex')} not found as a Ledger account (n<${MAX_ACCT}) or BIP-44 leaf (a<${STD_ACCT}, i<${STD_IDX}).`);process.exit(1);}
const parent=found.parent;
const msb=b=>{let a=[];for(const x of b)for(let i=7;i>=0;i--)a.push((x>>i)&1);return a;};
fs.writeFileSync('circuit_in.json',JSON.stringify({
  parentPriv:msb(Buffer.from(parent.privateKey)),
  parentCC:msb(Buffer.from(parent.chainCode)),
  addrIndex:String(found.addrIndex),
  isHardened:String(found.isHardened),
  expectedAddr:BigInt('0x'+wantOld.toString('hex')).toString(),
  newAddr:BigInt('0x'+wantNew.toString('hex')).toString(),
  domain:dom.toString()
}));
console.log('old (expected) : 0x'+wantOld.toString('hex'));
console.log('matched path   : '+found.label);
console.log('isHardened     : '+found.isHardened+'   (public input; 1=Ledger, 0=BIP-44)');
console.log('parent -> circ : priv+chaincode of the level-4 node; final step done in-circuit');
console.log('derived==old   : true');
console.log('new (dest)     : 0x'+wantNew.toString('hex'));
console.log('domain (field) : '+dom.toString());
