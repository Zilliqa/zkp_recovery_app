pragma circom 2.0.2;
include "bip32lib.circom";
include "ecdsa.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/sha256/sha256.circom";
// MINIMAL variant: proves only the FINAL hardened CKD (index 0') from the m/44'/313'/n'/0'
// parent node (private) to the account address. The seed->...->parent derivation is done
// off-circuit. Same public bindings (expectedAddr, newAddr, domain).
template PrivBitsToAddr(){
    signal input privBits[256]; signal output addr[160];
    component lb[4]; signal privLimb[4];
    for (var j=0;j<4;j++){ lb[j]=Bits2Num(64);
        for (var i=0;i<64;i++) lb[j].in[i] <== privBits[(3-j)*64+(63-i)]; privLimb[j] <== lb[j].out; }
    component p2p = ECDSAPrivToPub(64,4);
    for (var j=0;j<4;j++) p2p.privkey[j] <== privLimb[j];
    component xb[4]; signal xbits[256];
    for (var j=0;j<4;j++){ xb[j]=Num2Bits(64); xb[j].in <== p2p.pubkey[0][3-j];
        for (var i=0;i<64;i++) xbits[j*64+i] <== xb[j].out[63-i]; }
    component yb0=Num2Bits(64); yb0.in <== p2p.pubkey[1][0]; signal parity; parity <== yb0.out[0];
    component sha=Sha256(264);
    sha.in[0]<==0;sha.in[1]<==0;sha.in[2]<==0;sha.in[3]<==0;sha.in[4]<==0;sha.in[5]<==0;sha.in[6]<==1;sha.in[7]<==parity;
    for (var i=0;i<256;i++) sha.in[8+i] <== xbits[i];
    for (var i=0;i<160;i++) addr[i] <== sha.out[96+i];
}
template SeedOwnershipMin(){
    signal input parentPriv[256];   // private: m/44'/313'/n'/0' priv key bits (MSB-first)
    signal input parentCC[256];     // private: its chain code bits (MSB-first)
    signal input expectedAddr;
    signal input newAddr;
    signal input domain;
    // Binary-constrain every prover-supplied bit input: b*(b-1)===0. Without this the "bits"
    // could be arbitrary field elements (under-constrained), enabling a forged proof.
    for (var i=0;i<256;i++){ parentPriv[i]*(parentPriv[i]-1) === 0; parentCC[i]*(parentCC[i]-1) === 0; }
    component ckd = CKDHardened(2147483648);   // final hardened step, index 0'
    for (var i=0;i<256;i++){ ckd.parentPriv[i] <== parentPriv[i]; ckd.parentCC[i] <== parentCC[i]; }
    component a = PrivBitsToAddr();
    for (var i=0;i<256;i++) a.privBits[i] <== ckd.childPriv[i];
    component pack = Bits2Num(160);
    for (var i=0;i<160;i++) pack.in[i] <== a.addr[159-i];
    expectedAddr === pack.out;
    signal nb; nb <== newAddr*newAddr;
    signal db; db <== domain*domain;
}
component main {public [expectedAddr, newAddr, domain]} = SeedOwnershipMin();
