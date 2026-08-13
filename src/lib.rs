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
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn generate_circom_plonk_proof(
    zkey_path: String,
    json_input_str: String,
) -> Result<PlonkProofResult, MoproError> {
    let (plonk_proof, signals) = co_plonk_bridge::prove_plonk(
        WitnessFn::RustWitness(witness::ledger_witness),
        json_input_str,
        zkey_path,
    )
    .map_err(|e| MoproError::CircomError(e.to_string()))?;

    println!("{:?}", plonk_proof);

    let proofs = co_plonk_bridge::extract_proof_values(&plonk_proof)
        .map_err(|e| MoproError::CircomError(e.to_string()))?;

    Ok(PlonkProofResult {
        proof: proofs,
        inputs: signals.into_iter().map(|i| i.to_string()).collect(),
    })
}

// Exported to Flutter
#[macro_use]
mod circom;
pub use circom::{
    generate_circom_proof, verify_circom_proof, CircomProof, CircomProofResult, PlonkProofResult,
    ProofLib, G1, G2,
};
mod witness {
    rust_witness::witness!(ledger);
}

crate::set_circom_circuits! {
    ("ledger_final.zkey", circom_prover::witness::WitnessFn::RustWitness(witness::ledger_witness)),
}

#[cfg(test)]
mod circom_tests {
    use crate::generate_circom_plonk_proof;
    // use std::str::FromStr;
    // use crate::generate_plonk_proof;

    const ZKEY_PATH: &str = "./test-vectors/circom/ledger_final.zkey";

    #[test]
    fn test_plonk() {
        let circuit_inputs = r#"{"parentPriv":["1","0","0","1","1","1","0","1","0","1","0","0","1","1","1","1","1","1","1","0","0","0","0","0","1","0","0","1","0","1","1","0","0","1","1","0","1","0","0","1","0","1","1","1","0","0","1","0","0","1","1","0","1","0","0","0","0","1","1","0","0","0","0","1","1","0","0","1","1","0","0","1","0","1","0","0","1","0","0","1","0","1","0","0","1","1","1","1","0","0","1","0","0","0","0","0","0","1","0","0","0","1","0","1","1","0","0","0","1","1","1","1","0","0","0","1","1","1","0","1","1","1","1","1","0","1","0","1","0","1","0","1","0","0","0","1","0","1","0","0","1","1","0","0","0","1","1","1","1","0","0","0","0","0","1","0","1","1","1","0","1","0","1","1","1","0","1","0","0","0","0","1","0","1","0","1","1","0","0","0","0","1","1","0","1","1","1","0","0","1","0","0","0","1","1","1","0","1","1","1","0","1","1","0","0","1","1","1","0","0","1","1","0","1","1","1","1","1","0","1","0","0","1","0","0","0","0","1","1","0","1","1","1","1","1","0","1","0","1","1","1","0","1","0","1","1","0","0","0","1","0","1","0","0","0","1"],"parentCC":["1","0","1","0","1","0","1","0","0","1","0","1","0","0","0","0","0","0","1","0","0","1","1","1","0","0","0","1","1","0","0","0","1","0","0","1","0","1","1","1","1","1","0","1","0","0","0","1","1","1","1","0","0","1","0","0","0","1","1","1","1","1","0","1","1","1","1","0","1","1","1","1","0","1","0","0","1","1","0","0","0","1","0","1","0","0","0","1","0","1","0","1","0","0","1","1","1","1","1","0","0","1","1","1","0","1","0","0","0","0","0","1","1","1","0","1","0","1","0","0","0","1","1","1","0","1","1","1","0","1","1","0","0","0","0","0","0","0","1","0","1","0","1","1","1","1","1","0","1","1","1","1","1","1","0","0","1","0","1","0","0","1","1","0","1","0","1","0","0","1","0","0","1","1","1","0","1","1","1","0","1","0","0","1","0","0","0","1","1","0","0","0","0","0","0","1","0","1","1","0","1","1","0","0","1","0","1","1","1","0","0","1","0","0","1","0","1","0","1","0","0","0","0","0","1","0","0","1","1","0","0","1","0","0","0","0","1","0","0","0","1","0","0","1","1","0","0","0","1","1","0","0","0","1","1","0"],"expectedAddr":["594091409465972267269143250280589291679441903583"],"newAddr":["394365017111200287840249441287420187482473354350"],"domain":["33333"]}"#.to_string();
        let result = generate_circom_plonk_proof(ZKEY_PATH.to_string(), circuit_inputs);
        assert!(result.is_ok());
        // let result = result.unwrap();
        println!("PlonkProof: {result:?}");
        // assert!(verify_circom_proof(ZKEY_PATH.to_string(), proof, ProofLib::Arkworks).is_ok());
    }
}

// HALO2_TEMPLATE
halo2_stub!();

// NOIR_TEMPLATE
noir_stub!();

// GNARK_TEMPLATE
gnark_stub!();
