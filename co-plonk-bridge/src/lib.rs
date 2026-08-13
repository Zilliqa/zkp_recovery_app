extern crate anyhow;
extern crate ark_bn254;
extern crate ark_ff;
extern crate circom_prover;
extern crate co_circom;
extern crate co_circom_types;
extern crate num_bigint;

use anyhow::Result;
use ark_bn254::Fr;
use ark_ff::ToConstraintField;
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

    Ok((proof, signals))
}

/// Field order matching snarkjs's generated PlonkVerifier.verifyProof(uint256[24], ...)
/// Source: https://github.com/iden3/snarkjs/blob/master/templates/verifier_plonk.sol.ejs
pub fn extract_proof_values(plonk_proof: &PlonkProof<Bn254>) -> Result<Vec<String>> {
    let mut out: Vec<String> = Vec::with_capacity(24);

    for xy in [
        plonk_proof.a,
        plonk_proof.b,
        plonk_proof.c,
        plonk_proof.z,
        plonk_proof.t1,
        plonk_proof.t2,
        plonk_proof.t3,
        plonk_proof.wxi,
        plonk_proof.wxiw,
    ]
    .iter()
    .map(|f| f.to_field_elements().unwrap())
    {
        out.push(xy[0].to_string());
        out.push(xy[1].to_string());
    }

    for s in [
        plonk_proof.eval_a,
        plonk_proof.eval_b,
        plonk_proof.eval_c,
        plonk_proof.eval_s1,
        plonk_proof.eval_s2,
        plonk_proof.eval_zw,
    ] {
        out.push(s.to_string());
    }

    // Safe because we always push exactly 18 + 6 = 24 values above.
    Ok(out)
}
