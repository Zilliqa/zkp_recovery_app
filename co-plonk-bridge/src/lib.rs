extern crate anyhow;
extern crate ark_bn254;
extern crate circom_prover;
extern crate co_circom;
extern crate co_circom_types;

use anyhow::Result;
use ark_bn254::Fr;
use circom_prover::witness::{self, WitnessFn};
use co_circom::Bn254;
use co_circom_types::SharedWitness;
use std::fs::File;
use std::sync::Arc;

pub fn prove_plonk(
    wit_fn: WitnessFn,
    json_input_str: String,
    zkey_path: String,
) -> Result<Vec<u8>> {
    // identical call to what circom-prover's own prove() makes internally
    let wit_thread = witness::generate_witness(wit_fn, json_input_str);
    let witnesses = wit_thread
        .join()
        .map_err(|_e| anyhow::anyhow!("panicked"))?;

    let zkey_file = File::open(zkey_path)?;
    let zkey = Arc::new(
        co_circom::PlonkZKey::from_reader(zkey_file, co_circom::CheckElement::No)?, // zkey file is already trusted, so we can skip the check
    );

    let fr_witness: Vec<Fr> = witnesses.into_iter().map(Fr::from).collect();
    let shared_witness = SharedWitness {
        public_inputs: fr_witness[..=zkey.n_public].to_vec(),
        witness: fr_witness[zkey.n_public + 1..].to_vec(),
    };

    let proof = co_plonk::Plonk::<Bn254>::plain_prove(zkey, shared_witness)
        .map_err(|_e| anyhow::anyhow!("proving"))?;
    Ok(serde_json::to_vec(&proof)?)
}
