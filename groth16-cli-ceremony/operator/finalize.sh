#!/usr/bin/env bash
# OPERATOR-ONLY finalization — run ONCE, after all contributions are collected.
# This is NOT a normal contribution: it applies a PUBLIC random beacon to the last accepted key,
# verifies the result, and exports the verification key + on-chain verifier contract.
#
# The beacon must come from a PRE-COMMITTED public source whose value is set by a FUTURE event —
# e.g. "drand round R" or "the hash of Bitcoin block H", where R/H still lie in the future when
# contributions close. After contributions are in you pick WHICH future round/height (so you know
# they're complete), but the VALUE must not yet exist at that moment — that's what makes it
# unbiasable: no one, operator included, can grind or cherry-pick a value that isn't known yet.
#
# usage:
#   ./finalize.sh <contribution.zkey> circuit.r1cs pot.ptau <beaconHex64> <iterations>
# outputs (in this folder):
#   final.zkey     -> the production proving key (ships in ../../groth16-prover-min)
#   vk.json        -> verification key
#   verifier.sol   -> on-chain verifier contract
#   transcript.md  -> ready-to-publish ceremony transcript (r1cs hash, beacon, chain)
set -e
cd "$(dirname "$0")"
IN="$1"; R1CS="$2"; PTAU="$3"; BEACON="$4"; ITERS="$5"   # iterations is REQUIRED — no silent default,
# so the operator consciously passes the value pinned in the ceremony announcement (goes into the transcript).

[ -n "$IN" ] && [ -n "$R1CS" ] && [ -n "$PTAU" ] && [ -n "$BEACON" ] && [ -n "$ITERS" ] || {
  echo "usage: ./finalize.sh <contribution.zkey> circuit.r1cs pot.ptau <beaconHex64> <iterations>"; exit 1; }
for f in "$IN" "$R1CS" "$PTAU"; do [ -f "$f" ] || { echo "ERROR: file not found: $f"; exit 1; }; done
[[ "$BEACON" =~ ^[0-9a-fA-F]{64}$ ]] || {
  echo "ERROR: beacon must be 32-byte hex (64 chars). Use a PRE-COMMITTED public source whose value"
  echo "       is set by a FUTURE event (a drand round, or the hash of a future Bitcoin block) so it"
  echo "       is unknowable until after contributions close and cannot be ground/cherry-picked."; exit 1; }
{ [[ "$ITERS" =~ ^[0-9]{1,2}$ ]] && [ "$ITERS" -ge 10 ] && [ "$ITERS" -le 63 ]; } || {
  echo "ERROR: iterations is required — an integer 10..63; pass the value pinned in your ceremony announcement."; exit 1; }

[ -d node_modules ] || { echo "installing snarkjs (first run)..."; npm ci --no-audit --no-fund; }
S="node --max-old-space-size=16384 node_modules/snarkjs/build/cli.cjs"

R1CS_SHA=$(sha256sum "$R1CS" | cut -d' ' -f1)
echo "[0/4] circuit.r1cs sha256: $R1CS_SHA"
echo "[1/4] applying beacon (final, non-secret contribution)..."
$S zkey beacon "$IN" final.zkey "$BEACON" "$ITERS" -n="final beacon"
echo "[2/4] verifying final key against circuit.r1cs + pot.ptau..."
# capture the verify output — it lists the full ordered contribution chain (names + hashes),
# which is exactly what the published transcript needs.
VERIFY_OUT="$($S zkey verify "$R1CS" "$PTAU" final.zkey 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
echo "$VERIFY_OUT" | grep -iE 'contribution #|ZKey Ok|INVALID' || true
echo "$VERIFY_OUT" | grep -qi 'ZKey Ok!' || { echo "ERROR: final key FAILED verification — aborting."; exit 1; }
echo "[3/4] exporting verification key -> vk.json..."
$S zkey export verificationkey final.zkey vk.json
echo "[4/4] exporting on-chain verifier contract -> verifier.sol..."
$S zkey export solidityverifier final.zkey verifier.sol

# assemble a ready-to-publish transcript.md — only the [beacon source] field is left for the operator.
FINAL_SHA=$(sha256sum final.zkey  | cut -d' ' -f1)
VK_SHA=$(sha256sum    vk.json      | cut -d' ' -f1)
VER_SHA=$(sha256sum   verifier.sol | cut -d' ' -f1)
PTAU_NAME=$(basename "$PTAU"); PTAU_B2=$(b2sum "$PTAU" | cut -d' ' -f1)   # ptau fingerprint (auto-filled)
# zkey verify prints, for each step, "contribution #N <name>:" FOLLOWED BY its contribution hash
# (4 hex lines), plus the beacon's generator + iterations, ending in "ZKey Ok!". Capture that whole
# block verbatim (snarkjs log prefixes stripped) — the authoritative, re-runnable per-contribution record.
CHAIN="$(echo "$VERIFY_OUT" | sed 's/^\[INFO\][[:space:]]*snarkJS:[[:space:]]*//' | sed -n '/^contribution #/,/^ZKey Ok/p')"
[ -n "$CHAIN" ] || CHAIN="$VERIFY_OUT"
# snarkjs' own circuit fingerprint (blake2b-512 of the constraint system) — distinct from sha256(r1cs)
CIRCUIT_HASH="$(echo "$VERIFY_OUT" | sed 's/^\[INFO\][[:space:]]*snarkJS:[[:space:]]*//' | awk 'tolower($0) ~ /^circuit hash:/{f=1;next} f&&/^[[:space:]]*[0-9a-f ]+$/{gsub(/[^0-9a-f]/,"");printf "%s",$0;n++;if(n==4){print"";exit}}')"
{
  echo "# Ceremony transcript — Zilliqa seed-ownership (minimal Groth16 circuit)"
  echo
  echo "## Circuit"
  echo "- \`circuit.r1cs\` sha256: \`$R1CS_SHA\` (SHA-256 of the r1cs file — reproduce by recompiling)"
  echo "- snarkjs circuit hash (blake2b-512): \`$CIRCUIT_HASH\` (what \`zkey verify\` binds the key to)"
  echo "- powers-of-tau: \`$PTAU_NAME\` (blake2b \`$PTAU_B2\`)"
  echo
  echo "## Beacon (pre-committed public future source)"
  # keep this rule in sync with the READMEs' "Beacon (pre-committed)" section
  echo "- source: pre-committed (announced before the ceremony) — the finalized hash of the first Ethereum mainnet block with timestamp >= 2026-09-04 14:00:00 UTC; the block is the one whose hash is the value below."
  echo "- value: \`$BEACON\`"
  echo "- iterations: $ITERS"
  echo
  echo "## Final artifacts"
  echo "- \`final.zkey\` sha256: \`$FINAL_SHA\`"
  echo "- \`vk.json\` sha256: \`$VK_SHA\`"
  echo "- \`verifier.sol\` sha256: \`$VER_SHA\`"
  echo
  echo "## Contribution chain"
  echo "Full output of \`npx snarkjs zkey verify circuit.r1cs pot.ptau final.zkey\` — for every step: the"
  echo "contribution number, contributor name, and its **contribution hash** (the 4 hex lines), plus the"
  echo "beacon's generator + iteration count, ending in \`ZKey Ok!\`. Re-running the command reproduces this"
  echo "exactly (snarkjs log prefixes removed for readability)."
  echo
  echo '```'
  echo "$CHAIN"
  echo '```'
  echo
  echo "**How to verify:**"
  echo "- Re-run \`npx snarkjs zkey verify circuit.r1cs pot.ptau final.zkey\`: you must get \`ZKey Ok!\` and the"
  echo "  same contributions, hashes, and order as above."
  echo "- **Each contributor** confirms their own step by matching the hash \`contribute.sh\` printed to them"
  echo "  against their entry above (same 4-line format) — no need to trust anyone else."
  echo "- The **beacon** (the \`final beacon\` entry) is reproducible: applying \`zkey beacon\` with the"
  echo "  \`Beacon generator\` + \`Beacon iterations Exp\` shown to the previous contribution's key yields it."
} > transcript.md

echo
echo "================= CEREMONY FINALIZED ================="
echo "Produced: final.zkey (production proving key), vk.json, verifier.sol, transcript.md"
echo "Next: transcript.md is complete (r1cs + ptau hashes, beacon, full contribution chain with per-contribution hashes) — publish it on GitHub:"
echo "  - transcript.md  (circuit r1cs sha256, contribution chain, beacon value + iterations)"
echo "  - final.zkey / vk.json / verifier.sol  (keys on the bucket — too large for GitHub)"
echo "circuit.r1cs sha256: $R1CS_SHA"
echo "beacon: $BEACON  ($ITERS iterations)"
echo "====================================================="
