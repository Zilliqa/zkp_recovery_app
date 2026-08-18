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
// NB: this circuit does the final CKD step inline in circuit.circom's CKDFinalStep template
// (hardened/non-hardened, MUX-selected). This library intentionally exposes only the two
// primitives that step needs — Hmac512 and ModAddN — plus BitAdd (used by ModAddN).
