#[macro_use]
mod stubs;
mod error;
pub use error::MoproError;
use mimalloc::MiMalloc;

#[global_allocator]
static GLOBAL: MiMalloc = MiMalloc;

// Initializes the shared UniFFI scaffolding and defines the `MoproError` enum.
#[cfg(not(target_arch = "wasm32"))]
mopro_ffi::app!();
// Skip wasm_setup!() to avoid extern crate alias conflict
// Instead, we import wasm_bindgen directly when needed
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
use mopro_ffi::prelude::wasm_bindgen;

/// You can also customize the bindings by #[uniffi::export]
/// Reference: https://mozilla.github.io/uniffi-rs/latest/proc_macro/index.html
// #[cfg_attr(feature = "uniffi", uniffi::export)]

// Exported to Flutter
#[macro_use]
mod circom;
pub use circom::{
    generate_circom_proof, verify_circom_proof, CircomProof, CircomProofResult, ProofLib, G1, G2,
};
mod witness {
    rust_witness::witness!(groth);
}

crate::set_circom_circuits! {
    ("groth_final.zkey", circom_prover::witness::WitnessFn::RustWitness(witness::groth_witness)),
}

#[cfg(test)]
mod circom_tests {
    // use crate::generate_circom_plonk_proof;
    // use std::str::FromStr;
    use crate::generate_circom_proof;

    const ZKEY_PATH: &str = "./test-vectors/circom/groth_final.zkey";

    #[test]
    fn test_plonk() {
        let circuit_inputs = r#"{"parentPriv":["1","0","0","1","1","1","0","1","0","1","0","0","1","1","1","1","1","1","1","0","0","0","0","0","1","0","0","1","0","1","1","0","0","1","1","0","1","0","0","1","0","1","1","1","0","0","1","0","0","1","1","0","1","0","0","0","0","1","1","0","0","0","0","1","1","0","0","1","1","0","0","1","0","1","0","0","1","0","0","1","0","1","0","0","1","1","1","1","0","0","1","0","0","0","0","0","0","1","0","0","0","1","0","1","1","0","0","0","1","1","1","1","0","0","0","1","1","1","0","1","1","1","1","1","0","1","0","1","0","1","0","1","0","0","0","1","0","1","0","0","1","1","0","0","0","1","1","1","1","0","0","0","0","0","1","0","1","1","1","0","1","0","1","1","1","0","1","0","0","0","0","1","0","1","0","1","1","0","0","0","0","1","1","0","1","1","1","0","0","1","0","0","0","1","1","1","0","1","1","1","0","1","1","0","0","1","1","1","0","0","1","1","0","1","1","1","1","1","0","1","0","0","1","0","0","0","0","1","1","0","1","1","1","1","1","0","1","0","1","1","1","0","1","0","1","1","0","0","0","1","0","1","0","0","0","1"],"parentCC":["1","0","1","0","1","0","1","0","0","1","0","1","0","0","0","0","0","0","1","0","0","1","1","1","0","0","0","1","1","0","0","0","1","0","0","1","0","1","1","1","1","1","0","1","0","0","0","1","1","1","1","0","0","1","0","0","0","1","1","1","1","1","0","1","1","1","1","0","1","1","1","1","0","1","0","0","1","1","0","0","0","1","0","1","0","0","0","1","0","1","0","1","0","0","1","1","1","1","1","0","0","1","1","1","0","1","0","0","0","0","0","1","1","1","0","1","0","1","0","0","0","1","1","1","0","1","1","1","0","1","1","0","0","0","0","0","0","0","1","0","1","0","1","1","1","1","1","0","1","1","1","1","1","1","0","0","1","0","1","0","0","1","1","0","1","0","1","0","0","1","0","0","1","1","1","0","1","1","1","0","1","0","0","1","0","0","0","1","1","0","0","0","0","0","0","1","0","1","1","0","1","1","0","0","1","0","1","1","1","0","0","1","0","0","1","0","1","0","1","0","0","0","0","0","1","0","0","1","1","0","0","1","0","0","0","0","1","0","0","0","1","0","0","1","1","0","0","0","1","1","0","0","0","1","1","0"],"expectedAddr":["594091409465972267269143250280589291679441903583"],"newAddr":["394365017111200287840249441287420187482473354350"],"domain":["33333"]}"#.to_string();
        let result = generate_circom_proof(
            ZKEY_PATH.to_string(),
            circuit_inputs,
            crate::ProofLib::Arkworks,
        );
        assert!(result.is_ok());
        // let result = result.unwrap();
        println!("Proof: {result:?}");
        // assert!(verify_circom_proof(
        //     ZKEY_PATH.to_string(),
        //     result.unwrap().proof,
        //     crate::ProofLib::Arkworks
        // )
        // .is_ok());
    }
}

// HALO2_TEMPLATE
halo2_stub!();

// NOIR_TEMPLATE
noir_stub!();

// GNARK_TEMPLATE
gnark_stub!();
