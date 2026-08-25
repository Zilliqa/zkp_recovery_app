pragma circom 2.0.2;
include "bip32lib.circom";
include "ecdsa.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/sha256/sha256.circom";
// MINIMAL variant: proves the FINAL BIP-32 CKD step from the level-4 parent node (private) to the
// account address. The seed -> ... -> parent derivation is done off-circuit. The final step is
// CONFIGURABLE by the public `isHardened` bit:
//   isHardened=1 : Ledger, all-hardened path   m/44'/313'/n'/0'/0'   (parent = m/44'/313'/n'/0')
//   isHardened=0 : standard BIP-44 (hot wallets) m/44'/313'/n'/0/i    (parent = m/44'/313'/n'/0)
// The two modes differ ONLY in the HMAC-SHA512 preimage (private key vs public key) and one index
// bit; everything after HMAC (child key -> pubkey -> SHA-256[-20:] address) is identical.
// Same address / newAddr / domain bindings.

// compressed secp256k1 pubkey (33 bytes = 264 bits, MSB-first) from 256-bit private-key bits
template CompressedPub(){
    signal input privBits[256]; signal output comp[264];
    component lb[4]; signal privLimb[4];
    for (var j=0;j<4;j++){ lb[j]=Bits2Num(64);
        for (var i=0;i<64;i++) lb[j].in[i] <== privBits[(3-j)*64+(63-i)]; privLimb[j] <== lb[j].out; }
    component p2p = ECDSAPrivToPub(64,4);
    for (var j=0;j<4;j++) p2p.privkey[j] <== privLimb[j];
    component xb[4]; signal xbits[256];
    for (var j=0;j<4;j++){ xb[j]=Num2Bits(64); xb[j].in <== p2p.pubkey[0][3-j];
        for (var i=0;i<64;i++) xbits[j*64+i] <== xb[j].out[63-i]; }
    component yb0=Num2Bits(64); yb0.in <== p2p.pubkey[1][0]; signal parity; parity <== yb0.out[0];
    // compressed prefix byte = 0x02 | y_parity  ==  bits [0,0,0,0,0,0,1,parity]  (MSB-first)
    comp[0]<==0;comp[1]<==0;comp[2]<==0;comp[3]<==0;comp[4]<==0;comp[5]<==0;comp[6]<==1;comp[7]<==parity;
    for (var i=0;i<256;i++) comp[8+i] <== xbits[i];
}
template PrivBitsToAddr(){
    signal input privBits[256]; signal output addr[160];
    component cp = CompressedPub();
    for (var i=0;i<256;i++) cp.privBits[i] <== privBits[i];
    component sha=Sha256(264);
    for (var i=0;i<264;i++) sha.in[i] <== cp.comp[i];
    for (var i=0;i<160;i++) addr[i] <== sha.out[96+i];
}
// Final CKD step, index = addrIndex, hardened XOR non-hardened (runtime-selected by isHardened).
//   hardened     preimage: 0x00 || parentPriv        (33 bytes; uses the PRIVATE key)
//   non-hardened preimage: compress(parentPriv * G)  (33 bytes; uses the PUBLIC key)
// serialized index (32 bits, MSB-first) = [isHardened (the 2^31 hardened bit)] ++ 31-bit addrIndex.
template CKDFinalStep(){
    signal input parentPriv[256]; signal input parentCC[256];
    signal input isHardened;            // {0,1}
    signal input addrIndex;             // final path component: 0 for Ledger, address_index for BIP-44; < 2^31
    signal output childPriv[256];
    isHardened*(isHardened-1) === 0;
    // hardened preimage Ph = 0x00 || parentPriv
    signal Ph[264];
    for (var i=0;i<8;i++)   Ph[i]   <== 0;
    for (var i=0;i<256;i++) Ph[8+i] <== parentPriv[i];
    // non-hardened preimage Pn = compress(parentPriv * G)
    component cp = CompressedPub();
    for (var i=0;i<256;i++) cp.privBits[i] <== parentPriv[i];
    // mux both 264-bit preimages: P = isHardened ? Ph : Pn
    signal P[264];
    for (var i=0;i<264;i++) P[i] <== cp.comp[i] + isHardened*(Ph[i]-cp.comp[i]);
    // HMAC-SHA512(key=parentCC, msg = P(264 bits) || serialized-index(32 bits)) = 296-bit msg
    component h=Hmac512(256,296);
    for(var i=0;i<256;i++) h.key[i]<==parentCC[i];
    for(var i=0;i<264;i++) h.msg[i]<==P[i];
    component nb=Num2Bits(31); nb.in<==addrIndex;          // 0 <= addrIndex < 2^31 (keeps the hardened bit clean)
    h.msg[264] <== isHardened;                             // the 2^31 hardened bit
    for(var k=0;k<31;k++) h.msg[265+k] <== nb.out[30-k];   // 31-bit index, MSB-first
    // childPriv = (I_L + parentPriv) mod n
    component madd=ModAddN();
    for(var i=0;i<256;i++){ madd.a[i]<==parentPriv[255-i]; madd.b[i]<==h.out[255-i]; }
    for(var i=0;i<256;i++) childPriv[i]<==madd.c[255-i];
    // --- BIP-32 conformance: reject the step if IL >= n or childPriv == 0 (F-2026-19024) ---
    // (1) IL < n : compare the raw HMAC-SHA512 left half (IL = h.out[0..255], MSB-first) against the
    //     secp256k1 group order n, as 4 little-endian 64-bit limbs (same limb order as CompressedPub).
    component ilLimb[4]; signal ilVal[4];
    for (var j=0;j<4;j++){ ilLimb[j]=Bits2Num(64);
        for (var i=0;i<64;i++) ilLimb[j].in[i] <== h.out[(3-j)*64+(63-i)];
        ilVal[j] <== ilLimb[j].out; }
    var order[4] = [0xbfd25e8cd0364141, 0xbaaedce6af48a03b, 0xfffffffffffffffe, 0xffffffffffffffff];
    component ilLt = BigLessThan(64,4);
    for (var j=0;j<4;j++){ ilLt.a[j] <== ilVal[j]; ilLt.b[j] <== order[j]; }
    ilLt.out === 1;                                        // require IL < n
    // (2) childPriv != 0 : sum of the (boolean) child-key bits is 0 iff the key is 0.
    var cpAcc = 0; for (var i=0;i<256;i++) cpAcc += childPriv[i];
    signal cpSum; cpSum <== cpAcc;
    component cpZero = IsZero(); cpZero.in <== cpSum; cpZero.out === 0;   // require childPriv != 0
}
template SeedOwnershipMin(){
    signal input parentPriv[256];   // private: level-4 parent-node priv key bits (MSB-first)
    signal input parentCC[256];     // private: its chain code bits (MSB-first)
    signal input addrIndex;         // private: final path index (0 for Ledger)
    // Public inputs — declared in the order they appear in publicSignals: [old, new, domain, isHardened].
    // (circom orders public signals by declaration order, so keep isHardened last.)
    signal input expectedAddr;
    signal input newAddr;
    signal input domain;
    signal input isHardened;        // public: 1 = Ledger all-hardened, 0 = standard BIP-44
    // Binary-constrain every prover-supplied bit input: b*(b-1)===0. Without this the "bits"
    // could be arbitrary field elements (under-constrained), enabling a forged proof.
    for (var i=0;i<256;i++){ parentPriv[i]*(parentPriv[i]-1) === 0; parentCC[i]*(parentCC[i]-1) === 0; }
    component ckd = CKDFinalStep();
    for (var i=0;i<256;i++){ ckd.parentPriv[i] <== parentPriv[i]; ckd.parentCC[i] <== parentCC[i]; }
    ckd.isHardened <== isHardened;
    ckd.addrIndex  <== addrIndex;
    component a = PrivBitsToAddr();
    for (var i=0;i<256;i++) a.privBits[i] <== ckd.childPriv[i];
    component pack = Bits2Num(160);
    for (var i=0;i<160;i++) pack.in[i] <== a.addr[159-i];
    expectedAddr === pack.out;
    // Range-check newAddr to 160 bits, mirroring expectedAddr's implicit bound (via pack.out < 2^160),
    // so the proof's committed destination matches the on-chain address(uint256) truncation. Num2Bits
    // also references newAddr in a constraint, so snarkjs won't prune the public signal. (F-2026-19026)
    component newAddrBits = Num2Bits(160); newAddrBits.in <== newAddr;
    // domain is a domain-separator (chainId, or keccak(chainId,claimContract) reduced mod p) — NOT a
    // 160-bit address — so it gets no range check; square it only to keep the public signal alive.
    signal db; db <== domain*domain;
}
component main {public [expectedAddr, newAddr, domain, isHardened]} = SeedOwnershipMin();
