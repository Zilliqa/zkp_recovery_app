// FULL minimal circuit (Noir): parent node (m/44'/313'/n'/0') --final hardened CKD 0'-->
// account key --secp256k1--> pubkey --SHA-256[-20:]--> address == expected, bound to new+domain.
// Public inputs: [expected_addr, new_addr, domain] (3 fields) - matches the Groth16 uint256[3] interface.
use bignum::{BigNum, Secp256k1_Fr};
use noir_bigcurve::BigCurve;
use noir_bigcurve::curves::secp256k1::{Secp256k1, Secp256k1Scalar};

fn hmac_sha512(key: [u8; 32], msg: [u8; 37]) -> [u8; 64] {
    let mut kpad: [u8; 128] = [0; 128];
    for i in 0..32 { kpad[i] = key[i]; }
    let mut inner_in: [u8; 165] = [0; 165];
    for i in 0..128 { inner_in[i] = kpad[i] ^ 0x36; }
    for i in 0..37 { inner_in[128 + i] = msg[i]; }
    let inner = sha512::sha512::digest(inner_in);
    let mut outer_in: [u8; 192] = [0; 192];
    for i in 0..128 { outer_in[i] = kpad[i] ^ 0x5c; }
    for i in 0..64 { outer_in[128 + i] = inner[i]; }
    sha512::sha512::digest(outer_in)
}

fn main(
    parent_priv: [u8; 32],
    parent_cc: [u8; 32],
    expected_addr: pub Field,
    new_addr: pub Field,
    domain: pub Field,
) {
    let mut msg: [u8; 37] = [0; 37];
    for i in 0..32 { msg[1 + i] = parent_priv[i]; }
    msg[33] = 0x80; // ser32(0x80000000) big-endian, hardened index 0'
    let ii = hmac_sha512(parent_cc, msg);
    let mut il: [u8; 32] = [0; 32];
    for i in 0..32 { il[i] = ii[i]; }
    let child_fr = Secp256k1_Fr::from_be_bytes(il) + Secp256k1_Fr::from_be_bytes(parent_priv);
    let pk = Secp256k1::one().mul(Secp256k1Scalar::from_bignum(child_fr));
    let x: [u8; 32] = pk.x.to_be_bytes();
    let y: [u8; 32] = pk.y.to_be_bytes();
    let mut comp: [u8; 33] = [0; 33];
    comp[0] = if (y[31] & 1) == 1 { 0x03 } else { 0x02 };
    for i in 0..32 { comp[1 + i] = x[i]; }
    let h = sha256::digest(comp);
    // pack derived address (last 20 bytes) into a field and bind to expected
    let mut acc: Field = 0;
    for i in 0..20 { acc = acc * 256 + (h[12 + i] as Field); }
    assert(acc == expected_addr);
    // bind destination + domain (reject zero; keeps them constrained in the public inputs)
    assert(new_addr != 0);
    assert(domain != 0);
}
