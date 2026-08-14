// Convert the raw BN254 G1 SRS (.dat, downloaded from crs.aztec.network) into the bincode
// `.srs` format the app bundles (same format mopro's example ships). Used by scripts/fetch-srs.sh.
//
//   cargo run --release --bin gen_srs -- <in.dat> <out.srs>
//
// Points are derived from the .dat size (64 bytes/point); the app only reads the prefix it needs.
use noir_rs::barretenberg::srs::localsrs::LocalSrs;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let dat = args.get(1).map(String::as_str).unwrap_or("flutter/assets/srs_g1.dat");
    let out = args.get(2).map(String::as_str).unwrap_or("flutter/assets/srs_g1.srs");
    let bytes = std::fs::metadata(dat)
        .unwrap_or_else(|_| panic!("input .dat not found: {dat}"))
        .len();
    let points = (bytes / 64) as u32;
    let srs = LocalSrs::from_dat_file(points, Some(dat));
    srs.save(Some(out));
    println!("wrote {out} ({points} points) from {dat}");
}
