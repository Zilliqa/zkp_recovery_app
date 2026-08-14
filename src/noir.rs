// Real Noir adapter (replaces noir_stub!()): UltraHonk-keccak via noir-rs (Barretenberg).
// Signatures MUST match the stub so the already-generated FFI bindings keep working.
use crate::error::MoproError;
use noir_rs::barretenberg::prove::prove_ultra_honk_keccak;
use noir_rs::barretenberg::srs::setup_srs_from_bytecode;
use noir_rs::barretenberg::verify::{get_ultra_honk_keccak_verification_key, verify_ultra_honk_keccak};
use noir_rs::utils::proof_utils::{
    combine_proof_and_public_inputs, get_num_public_inputs_from_circuit, parse_proof_with_public_inputs,
};
use noir_rs::witness::from_vec_str_to_witness_map;
use std::fs;
use std::sync::Mutex;

fn load_bytecode(circuit_path: &str) -> Result<String, MoproError> {
    let s = fs::read_to_string(circuit_path)
        .map_err(|e| MoproError::NoirError(format!("read {circuit_path}: {e}")))?;
    let v: serde_json::Value =
        serde_json::from_str(&s).map_err(|e| MoproError::NoirError(format!("parse circuit json: {e}")))?;
    v["bytecode"]
        .as_str()
        .map(|s| s.to_string())
        .ok_or_else(|| MoproError::NoirError("circuit json has no .bytecode".into()))
}

// get_vk -> prove -> verify are 3 separate FFI calls, each of which used to re-run the SRS
// setup (download + load). The SRS is a process-global keyed only by circuit size, and all
// three use the same circuit, so we set it up once per process. Retries on failure (e.g. a
// dropped download) since the flag is only latched after success. If srs_path is Some, that
// pre-bundled SRS is used and no download happens (mobile: ship it as an asset).
static SRS_READY: Mutex<bool> = Mutex::new(false);

fn ensure_srs(bytecode: &str, srs_path: Option<&str>) -> Result<(), MoproError> {
    let mut ready = SRS_READY.lock().unwrap();
    if *ready {
        return Ok(());
    }
    setup_srs_from_bytecode(bytecode, srs_path, false).map_err(MoproError::NoirError)?;
    *ready = true;
    Ok(())
}

#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn get_noir_verification_key(
    circuit_path: String,
    srs_path: Option<String>,
    _on_chain: bool,
    low_memory_mode: bool,
) -> Result<Vec<u8>, MoproError> {
    let bytecode = load_bytecode(&circuit_path)?;
    ensure_srs(&bytecode, srs_path.as_deref())?;
    get_ultra_honk_keccak_verification_key(&bytecode, false, low_memory_mode).map_err(MoproError::NoirError)
}

#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn generate_noir_proof(
    circuit_path: String,
    srs_path: Option<String>,
    inputs: Vec<String>,
    _on_chain: bool,
    vk: Vec<u8>,
    low_memory_mode: bool,
) -> Result<Vec<u8>, MoproError> {
    let bytecode = load_bytecode(&circuit_path)?;
    ensure_srs(&bytecode, srs_path.as_deref())?;
    let iw = from_vec_str_to_witness_map(inputs.iter().map(|s| s.as_str()).collect())
        .map_err(MoproError::NoirError)?;
    prove_ultra_honk_keccak(&bytecode, iw, vk, false, low_memory_mode).map_err(MoproError::NoirError)
}

#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn verify_noir_proof(
    circuit_path: String,
    proof: Vec<u8>,
    _on_chain: bool,
    vk: Vec<u8>,
    _low_memory_mode: bool,
) -> Result<bool, MoproError> {
    let bytecode = load_bytecode(&circuit_path)?;
    ensure_srs(&bytecode, None)?;
    let npi = get_num_public_inputs_from_circuit(&bytecode).map_err(MoproError::NoirError)?;
    let ppi = parse_proof_with_public_inputs(&proof, npi).map_err(MoproError::NoirError)?;
    let combined = combine_proof_and_public_inputs(ppi.proof, ppi.public_inputs);
    verify_ultra_honk_keccak(combined, vk, false).map_err(MoproError::NoirError)
}
