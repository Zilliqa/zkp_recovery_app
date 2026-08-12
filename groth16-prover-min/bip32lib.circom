pragma circom 2.0.0;
include "binsum.circom";
include "sha512.circom";
include "bitify.circom";

template Hmac512(nKeyBits,nMsgBits){
    signal input key[nKeyBits]; signal input msg[nMsgBits]; signal output out[512];
    component inner=Sha512(1024+nMsgBits); component outer=Sha512(1024+512);
    for(var i=0;i<1024;i++){
        var cip=(0x36>>(7-(i%8)))&1; var cop=(0x5c>>(7-(i%8)))&1;
        if(i<nKeyBits){ if(cip==1) inner.in[i]<==1-key[i]; else inner.in[i]<==key[i];
                        if(cop==1) outer.in[i]<==1-key[i]; else outer.in[i]<==key[i]; }
        else { inner.in[i]<==cip; outer.in[i]<==cop; } }
    for(var i=0;i<nMsgBits;i++) inner.in[1024+i]<==msg[i];
    for(var i=0;i<512;i++) outer.in[1024+i]<==inner.out[i];
    for(var i=0;i<512;i++) out[i]<==outer.out[i];
}
template BitAdd(N){
    signal input a[N]; signal input b[N]; signal output out[N+1];
    signal carry[N+1]; signal ab[N]; signal xab[N]; signal cx[N];
    carry[0]<==0;
    for(var i=0;i<N;i++){ ab[i]<==a[i]*b[i]; xab[i]<==a[i]+b[i]-2*ab[i]; cx[i]<==carry[i]*xab[i];
        carry[i+1]<==ab[i]+cx[i]; out[i]<==xab[i]+carry[i]-2*cx[i]; }
    out[N]<==carry[N];
}
template ModAddN(){
    signal input a[256]; signal input b[256]; signal output c[256];
    var Cc[257]=[1,1,1,1,1,1,0,1,0,1,1,1,1,1,0,1,1,0,0,1,0,0,1,1,1,1,1,1,0,1,0,0,1,1,0,0,1,1,1,0,1,0,0,0,0,1,0,1,1,0,1,1,0,1,0,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,1,1,1,1,1,1,1,0,1,0,1,1,1,0,1,1,0,1,0,0,0,0,1,0,1,0,1,0,0,1,1,0,0,0,1,1,0,0,0,1,0,0,1,0,0,0,1,0,1,0,1,0,1,0,0,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1];
    component s=BitAdd(256); for(var i=0;i<256;i++){s.a[i]<==a[i];s.b[i]<==b[i];}
    component t=BitAdd(257); for(var i=0;i<257;i++){t.a[i]<==s.out[i];t.b[i]<==Cc[i];}
    signal carry; carry<==t.out[257];
    for(var i=0;i<256;i++) c[i]<==carry*(t.out[i]-s.out[i])+s.out[i];
}
// hardened CKD: inputs MSB-first; index compile-time (0x80000000+i)
template CKDHardened(index){
    signal input parentPriv[256]; signal input parentCC[256];
    signal output childPriv[256];  signal output childCC[256];
    component h=Hmac512(256,296);
    for(var i=0;i<256;i++) h.key[i]<==parentCC[i];
    for(var i=0;i<8;i++)   h.msg[i]<==0;
    for(var i=0;i<256;i++) h.msg[8+i]<==parentPriv[i];
    for(var j=0;j<32;j++)  h.msg[264+j]<==(index>>(31-j))&1;
    for(var i=0;i<256;i++) childCC[i]<==h.out[256+i];              // IR
    component madd=ModAddN();
    for(var i=0;i<256;i++){ madd.a[i]<==parentPriv[255-i]; madd.b[i]<==h.out[255-i]; } // MSB->LSB, IL
    for(var i=0;i<256;i++) childPriv[i]<==madd.c[255-i];          // LSB->MSB
}
// hardened CKD with a VARIABLE index supplied as 32 bits (MSB-first, incl. the 0x80000000 hardened bit)
template CKDHardenedVar(){
    signal input parentPriv[256]; signal input parentCC[256]; signal input idxBits[32];
    signal output childPriv[256];  signal output childCC[256];
    component h=Hmac512(256,296);
    for(var i=0;i<256;i++) h.key[i]<==parentCC[i];
    for(var i=0;i<8;i++)   h.msg[i]<==0;
    for(var i=0;i<256;i++) h.msg[8+i]<==parentPriv[i];
    for(var j=0;j<32;j++)  h.msg[264+j]<==idxBits[j];
    for(var i=0;i<256;i++) childCC[i]<==h.out[256+i];
    component madd=ModAddN();
    for(var i=0;i<256;i++){ madd.a[i]<==parentPriv[255-i]; madd.b[i]<==h.out[255-i]; }
    for(var i=0;i<256;i++) childPriv[i]<==madd.c[255-i];
}
template LedgerDerive(){
    signal input masterPriv[256]; signal input masterCC[256];
    signal input accountIndex;                       // Ledger account n in m/44'/313'/n'/0'/0' (private)
    signal output childPriv[256]; signal output childCC[256];
    // accountIndex -> 32 hardened-index bits (0x80000000 | accountIndex), MSB-first
    component nb=Num2Bits(31); nb.in<==accountIndex;  // n < 2^31
    signal idxBits[32];
    idxBits[0]<==1;                                   // hardened top bit (2^31)
    for (var k=0;k<31;k++) idxBits[1+k]<==nb.out[30-k];
    component L0=CKDHardened(2147483692);             // 44'
    component L1=CKDHardened(2147483961);             // 313'
    component L2=CKDHardenedVar();                    // account'  (variable)
    component L3=CKDHardened(2147483648);             // 0'
    component L4=CKDHardened(2147483648);             // 0'
    for (var j=0;j<32;j++) L2.idxBits[j]<==idxBits[j];
    for (var i=0;i<256;i++){ L0.parentPriv[i]<==masterPriv[i]; L0.parentCC[i]<==masterCC[i]; }
    for (var i=0;i<256;i++){ L1.parentPriv[i]<==L0.childPriv[i]; L1.parentCC[i]<==L0.childCC[i]; }
    for (var i=0;i<256;i++){ L2.parentPriv[i]<==L1.childPriv[i]; L2.parentCC[i]<==L1.childCC[i]; }
    for (var i=0;i<256;i++){ L3.parentPriv[i]<==L2.childPriv[i]; L3.parentCC[i]<==L2.childCC[i]; }
    for (var i=0;i<256;i++){ L4.parentPriv[i]<==L3.childPriv[i]; L4.parentCC[i]<==L3.childCC[i]; }
    for (var i=0;i<256;i++){ childPriv[i]<==L4.childPriv[i]; childCC[i]<==L4.childCC[i]; }
}
