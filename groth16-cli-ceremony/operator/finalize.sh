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
# zkey verify lists the contributions by index + name and prints "ZKey Ok!" (it does NOT print
# per-contribution hashes) — capture that ordered name list + the validity line for the transcript.
CHAIN="$(echo "$VERIFY_OUT" | sed 's/^\[INFO\][[:space:]]*snarkJS:[[:space:]]*//' | grep -iE 'contribution #|ZKey Ok' || echo "$VERIFY_OUT")"
# one receipts row per human contributor (names from the chain; the beacon row excluded), sorted #1..#N
RECEIPTS="$(echo "$VERIFY_OUT" | sed 's/^\[INFO\][[:space:]]*snarkJS:[[:space:]]*//' \
  | grep -iE 'contribution #[0-9]+ ' | grep -vi 'final beacon' \
  | sed -E 's/.*contribution #([0-9]+) (.*):.*/\1|\2/' | sort -n \
  | awk -F'|' '{printf "| %s | %s | [reported hash] |\n", $1, $2}')"
{
  echo "# Ceremony transcript — Zilliqa seed-ownership (minimal Groth16 circuit)"
  echo
  echo "## Circuit"
  echo "- \`circuit.r1cs\` sha256: \`$R1CS_SHA\`"
  echo "- powers-of-tau: $PTAU_NAME (blake2b $PTAU_B2)"
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
  echo "From \`snarkjs zkey verify circuit.r1cs pot.ptau final.zkey\` — the ordered contributor list and"
  echo "the \`ZKey Ok!\` line that cryptographically validates the whole chain (verify lists names/order,"
  echo "not per-contribution hashes):"
  echo
  echo '```'
  echo "$CHAIN"
  echo '```'
  echo
  echo "## Contributor receipts (operator: paste the hash each contributor reported from \`contribute.sh\`)"
  echo "| # | contributor (name/org from the chain) | reported contribution hash |"
  echo "|---|---|---|"
  echo "$RECEIPTS"
  echo
  echo "**Verify the chain:** re-run \`snarkjs zkey verify circuit.r1cs pot.ptau final.zkey\` — you must get"
  echo "\`ZKey Ok!\` and the same ordered contributor list as above. **Confirm a specific contribution hash**"
  echo "by hashing the intermediary key at that step (kept on the bucket) — which is why each"
  echo "\`current.zkey\`/\`contribution.zkey\` is retained; a contributor matches the receipt they were shown."
} > transcript.md

echo
echo "================= CEREMONY FINALIZED ================="
echo "Produced: final.zkey (production proving key), vk.json, verifier.sol, transcript.md"
echo "Next: paste each contributor's reported hash into transcript.md's receipts table (replace the [reported hash] cells), then publish on GitHub:"
echo "  - transcript.md  (circuit r1cs sha256, contribution chain, beacon value + iterations)"
echo "  - final.zkey / vk.json / verifier.sol  (keys on the bucket — too large for GitHub)"
echo "circuit.r1cs sha256: $R1CS_SHA"
echo "beacon: $BEACON  ($ITERS iterations)"
echo "====================================================="
