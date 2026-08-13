// Local only. Run offline. MINIMAL circuit: the seed -> ... -> m/44'/313'/n'/0' parent node is
// derived OFF-circuit; the circuit proves only the final hardened step (0') -> address.
// usage: node prepare.js "<mnemonic>" <oldAddr 0x..|zil1..> <newAddr> <domain dec|0x> [passphrase]
const bip39=require('@scure/bip39'); const {HDKey}=require('@scure/bip32');
const crypto=require('crypto'); const fs=require('fs');
const pathFull  =n=>`m/44'/313'/${n}'/0'/0'`;   // full account path (to find which account matches)
const pathParent=n=>`m/44'/313'/${n}'/0'`;      // the level-4 parent node fed to the circuit
const MAX_ACCT=100;
const P=21888242871839275222246405745257275088548364400416034343698204186575808495617n;
const mnemonic=process.argv[2]; const oldA=(process.argv[3]||'').trim(); const newA=(process.argv[4]||'').trim();
const domArg=(process.argv[5]||'').trim(); const pass=process.argv[6]||'';
if(!mnemonic||!oldA||!newA||!domArg){console.error('usage: node prepare.js "<mnemonic>" <oldAddr> <newAddr> <domain dec|0x> [passphrase]');process.exit(1);}
const CH="qpzry9x8gf2tvdw0s3jn54khce6mua7l";
function bech32dec(s){const dp=s.toLowerCase().split('1').pop();const v=[...dp].map(c=>CH.indexOf(c)).slice(0,-6);
  let acc=0,bits=0,out=[];for(const x of v){acc=(acc<<5)|x;bits+=5;while(bits>=8){bits-=8;out.push((acc>>bits)&0xff);}}return Buffer.from(out);}
function addr20(a){let w;if(a.startsWith('0x')||/^[0-9a-fA-F]{40}$/.test(a))w=Buffer.from(a.replace(/^0x/,''),'hex');else w=bech32dec(a);
  if(w.length!==20){console.error('bad address: '+a);process.exit(1);}return w;}
function domField(s){let v=BigInt(s);v=((v%P)+P)%P;return v;}
const wantOld=addr20(oldA); const wantNew=addr20(newA); const dom=domField(domArg);
const seed=bip39.mnemonicToSeedSync(mnemonic,pass);                 // PBKDF2, off-circuit
const master=HDKey.fromMasterSeed(seed);
const addrAt=n=>crypto.createHash('sha256').update(Buffer.from(master.derive(pathFull(n)).publicKey)).digest().subarray(12);
let acct=-1;
for(let n=0;n<MAX_ACCT;n++){ if(Buffer.compare(addrAt(n),wantOld)===0){acct=n;break;} }
if(acct<0){console.error(`ERROR: old address 0x${wantOld.toString('hex')} not found in accounts 0..${MAX_ACCT-1}.`);process.exit(1);}
const parent=master.derive(pathParent(acct));                      // level-4 node: private input
const msb=b=>{let a=[];for(const x of b)for(let i=7;i>=0;i--)a.push((x>>i)&1);return a;};
fs.writeFileSync('circuit_in.json',JSON.stringify({
  parentPriv:msb(Buffer.from(parent.privateKey)),
  parentCC:msb(Buffer.from(parent.chainCode)),
  expectedAddr:BigInt('0x'+wantOld.toString('hex')).toString(),
  newAddr:BigInt('0x'+wantNew.toString('hex')).toString(),
  domain:dom.toString()
}));
console.log('old (expected) : 0x'+wantOld.toString('hex'));
console.log('account index  : '+acct+"   (parent node m/44'/313'/"+acct+"'/0' fed to circuit)");
console.log('derived==old   : true');
console.log('new (dest)     : 0x'+wantNew.toString('hex'));
console.log('domain (field) : '+dom.toString());
