use noir_rs::{
    barretenberg::{
        prove::{prove_ultra_honk, prove_ultra_honk_keccak},
        srs::setup_srs_from_bytecode,
        verify::{
            get_ultra_honk_keccak_verification_key, get_ultra_honk_verification_key,
            verify_ultra_honk, verify_ultra_honk_keccak,
        },
    },
    witness::from_vec_str_to_witness_map,
};

use crate::MoproError;

/// Generates a Noir proof with automatic hash function selection
///
/// This is the main proof generation function that automatically chooses
/// the appropriate hash function based on the intended use case:
///
/// - `on_chain = true`: Uses Keccak hash for Solidity verifier compatibility
/// - `on_chain = false`: Uses Poseidon hash for better performance
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn generate_noir_proof(
    circuit_path: String,
    srs_path: Option<String>,
    inputs: Vec<String>,
    on_chain: bool,
    vk: Vec<u8>,
    low_memory_mode: bool,
) -> Result<Vec<u8>, MoproError> {
    let res = if on_chain {
        generate_noir_proof_with_keccak(circuit_path, srs_path, inputs, false, vk, low_memory_mode)
    } else {
        generate_noir_proof_with_poseidon(circuit_path, srs_path, inputs, vk, low_memory_mode)
    };

    res.map_err(|e| MoproError::NoirError(format!("Generate Proof error: {}", e)))
}

/// Verifies a Noir proof with automatic hash function selection
///
/// This function automatically uses the correct verification method based
/// on how the proof was generated:
///
/// - `on_chain = true`: Verifies Keccak-based proof (Solidity compatible)
/// - `on_chain = false`: Verifies Poseidon-based proof (performance optimized)
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn verify_noir_proof(
    circuit_path: String,
    proof: Vec<u8>,
    on_chain: bool,
    vk: Vec<u8>,
    low_memory_mode: bool,
) -> Result<bool, MoproError> {
    if on_chain {
        Ok(verify_noir_proof_with_keccak(
            circuit_path,
            proof,
            false,
            vk,
            low_memory_mode,
        ))
    } else {
        Ok(verify_noir_proof_with_poseidon(
            circuit_path,
            proof,
            vk,
            low_memory_mode,
        ))
    }
}

/// Generates a verification key with automatic hash function selection
///
/// This function automatically chooses the appropriate hash function based
/// on the intended use case:
///
/// - `on_chain = true`: Uses Keccak hash for Solidity verifier compatibility
/// - `on_chain = false`: Uses Poseidon hash for better performance
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn get_noir_verification_key(
    circuit_path: String,
    srs_path: Option<String>,
    on_chain: bool,
    low_memory_mode: bool,
) -> Result<Vec<u8>, MoproError> {
    let res = if on_chain {
        get_noir_verification_keccak_key(circuit_path, srs_path, false, low_memory_mode)
    } else {
        get_noir_verification_poseidon_key(circuit_path, srs_path, low_memory_mode)
    };

    res.map_err(|e| MoproError::NoirError(format!("Get Verification Key error: {}", e)))
}

/// Generates a Noir proof using Poseidon as oracle hash
///
/// This function uses the Poseidon hash function for better performance.
/// However, proofs generated with Poseidon cannot be verified
/// on-chain with Solidity verifiers.
///
/// Use this for off-chain verification or when maximum performance is needed.
fn generate_noir_proof_with_poseidon(
    circuit_path: String,
    srs_path: Option<String>,
    inputs: Vec<String>,
    vk: Vec<u8>,
    low_memory_mode: bool,
) -> Result<Vec<u8>, String> {
    let circuit_bytecode = get_bytecode(circuit_path);

    // Setup the SRS
    setup_srs_from_bytecode(circuit_bytecode.as_str(), srs_path.as_deref(), false).unwrap();

    // Set up the witness
    let witness = from_vec_str_to_witness_map(inputs.iter().map(|s| s.as_str()).collect()).unwrap();

    prove_ultra_honk(circuit_bytecode.as_str(), witness, vk, low_memory_mode)
}

/// Verifies a Noir proof generated with Poseidon as oracle hash
///
/// This function verifies proofs that were generated using the Poseidon hash.
/// It cannot verify proofs intended for on-chain verification with Solidity verifiers.
pub fn verify_noir_proof_with_poseidon(
    circuit_path: String,
    proof: Vec<u8>,
    vk: Vec<u8>,
    _low_memory_mode: bool,
) -> bool {
    let _circuit_bytecode = get_bytecode(circuit_path);
    verify_ultra_honk(proof, vk).unwrap()
}

/// Generates a verification key for Poseidon-based Noir proofs
///
/// This verification key can only be used to verify proofs generated
/// with the Poseidon hash function (off-chain proofs).
fn get_noir_verification_poseidon_key(
    circuit_path: String,
    srs_path: Option<String>,
    low_memory_mode: bool,
) -> Result<Vec<u8>, String> {
    let circuit_bytecode = get_bytecode(circuit_path);

    setup_srs_from_bytecode(circuit_bytecode.as_str(), srs_path.as_deref(), false).unwrap();

    let vk = get_ultra_honk_verification_key(circuit_bytecode.as_str(), low_memory_mode).unwrap();
    Ok(vk)
}

/// Generates a Noir proof using Keccak as oracle hash
///
/// This function uses the Keccak hash function which is required for
/// generating proofs that can be verified on-chain with Solidity verifiers.
/// While slightly less performant than Poseidon, it enables on-chain verification.
///
/// Use this when you need to verify proofs on Ethereum or other EVM chains.
fn generate_noir_proof_with_keccak(
    circuit_path: String,
    srs_path: Option<String>,
    inputs: Vec<String>,
    disable_zk: bool,
    vk: Vec<u8>,
    low_memory_mode: bool,
) -> Result<Vec<u8>, String> {
    let circuit_bytecode = get_bytecode(circuit_path);

    // Setup the SRS
    setup_srs_from_bytecode(circuit_bytecode.as_str(), srs_path.as_deref(), false).unwrap();

    // Set up the witness
    let witness = from_vec_str_to_witness_map(inputs.iter().map(|s| s.as_str()).collect()).unwrap();

    prove_ultra_honk_keccak(
        circuit_bytecode.as_str(),
        witness,
        vk,
        disable_zk,
        low_memory_mode,
    )
}

/// Verifies a Noir proof generated with Keccak as oracle hash
///
/// This function verifies proofs that were generated using the Keccak hash,
/// which are compatible with Solidity verifiers for on-chain verification.
fn verify_noir_proof_with_keccak(
    circuit_path: String,
    proof: Vec<u8>,
    disable_zk: bool,
    vk: Vec<u8>,
    _low_memory_mode: bool,
) -> bool {
    let _circuit_bytecode = get_bytecode(circuit_path);
    verify_ultra_honk_keccak(proof, vk, disable_zk).unwrap()
}

/// Generates a verification key for Keccak-based Noir proofs
///
/// This verification key can be used to verify proofs generated with
/// the Keccak hash function, and is compatible with Solidity verifiers
/// for on-chain verification.
fn get_noir_verification_keccak_key(
    circuit_path: String,
    srs_path: Option<String>,
    disable_zk: bool,
    low_memory_mode: bool,
) -> Result<Vec<u8>, String> {
    let circuit_bytecode = get_bytecode(circuit_path);

    // Setup the SRS
    setup_srs_from_bytecode(circuit_bytecode.as_str(), srs_path.as_deref(), false).unwrap();

    // Set up the witness
    let vk = get_ultra_honk_keccak_verification_key(
        circuit_bytecode.as_str(),
        disable_zk,
        low_memory_mode,
    )
    .unwrap();
    Ok(vk)
}

fn get_bytecode(circuit_path: String) -> String {
    // Read the JSON manifest of the circuit
    let circuit_txt = std::fs::read_to_string(circuit_path).unwrap();
    let circuit: serde_json::Value = serde_json::from_str(&circuit_txt).unwrap();

    circuit["bytecode"].as_str().unwrap().to_string()
}
