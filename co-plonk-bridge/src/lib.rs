extern crate anyhow;
extern crate ark_bn254;
extern crate circom_prover;
extern crate co_circom;
extern crate co_circom_types;
extern crate num_bigint;

use anyhow::Result;
use ark_bn254::Fr;
use circom_prover::witness::{self, WitnessFn};
use co_circom::{Bn254, PlonkProof};
use co_circom_types::SharedWitness;
use num_bigint::BigUint;
use std::fs::File;
use std::sync::Arc;

pub fn prove_plonk(
    wit_fn: WitnessFn,
    json_input_str: String,
    zkey_path: String,
) -> Result<(PlonkProof<Bn254>, Vec<BigUint>)> {
    // identical call to what circom-prover's own prove() makes internally
    let wit_thread = witness::generate_witness(wit_fn, json_input_str);
    let witnesses = wit_thread
        .join()
        .map_err(|_e| anyhow::anyhow!("panicked"))?;

    let zkey_file = File::open(zkey_path)?;
    let zkey = Arc::new(
        co_circom::PlonkZKey::from_reader(zkey_file, co_circom::CheckElement::No)?, // zkey file is already trusted, so we can skip the check
    );

    let signals = witnesses[1..=zkey.n_public].to_vec(); // copy the signals
    let fr_witness: Vec<Fr> = witnesses.into_iter().map(Fr::from).collect();
    let shared_witness = SharedWitness {
        public_inputs: fr_witness[..=zkey.n_public].to_vec(),
        witness: fr_witness[zkey.n_public + 1..].to_vec(),
    };

    let proof = co_plonk::Plonk::<Bn254>::plain_prove(zkey, shared_witness)
        .map_err(|_e| anyhow::anyhow!("proving"))?;

    println!("{}", serde_json::to_string(&proof)?);
    Ok((proof, signals))
}

pub fn extract_proof_values(plonk_proof: &PlonkProof<Bn254>) -> Result<Vec<String>> {
    const POINT_FIELDS: [&str; 9] = ["A", "B", "C", "Z", "T1", "T2", "T3", "Wxi", "Wxiw"];
    const EVAL_FIELDS: [&str; 6] = [
        "eval_a", "eval_b", "eval_c", "eval_s1", "eval_s2", "eval_zw",
    ];

    let proof = serde_json::to_value(plonk_proof)?;

    let mut out: Vec<String> = Vec::with_capacity(24);

    for field in POINT_FIELDS {
        let arr = proof
            .get(field)
            .and_then(|v| v.as_array())
            .ok_or_else(|| anyhow::anyhow!("missing point"))?;

        if arr.len() < 2 {
            return Err(anyhow::anyhow!("not a point"));
        }

        for v in arr.iter().take(2) {
            let s = v
                .as_str()
                .ok_or_else(|| anyhow::anyhow!("non-string element"))?;
            out.push(s.to_string());
        }
    }

    for field in EVAL_FIELDS {
        let s = proof
            .get(field)
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow::anyhow!("missing field"))?;
        out.push(s.to_string());
    }

    // Safe because we always push exactly 18 + 6 = 24 values above.
    Ok(out)
}
