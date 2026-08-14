#!/usr/bin/env bash
# Hardened prover. Mnemonic + passphrase via HIDDEN prompts (never argv/env-persisted).
# Prover.toml + witness are SHREDDED on exit.
#
# CAVEAT vs the Groth16 in-memory runner: nargo reads its inputs from Prover.toml, so the
# parent node is briefly written to disk. It is shredded here, but for a REAL seed run this
# on an airgapped, amnesic OS (Tails / fresh live USB), ideally with the folder on tmpfs.
set -e
cd "$(dirname "$0")"
export PATH="$HOME/.nargo/bin:$HOME/.bb:$PATH"
command -v nargo >/dev/null && command -v bb >/dev/null || {
  echo "ERROR: nargo/bb not on PATH. Install the pinned toolchain (see README):"
  echo "  curl -sL https://raw.githubusercontent.com/noir-lang/noirup/main/install | bash   # then in a NEW shell (or after: export PATH=$HOME/.nargo/bin:$PATH): noirup -v 1.0.0-beta.19"
  echo "  curl -sL https://raw.githubusercontent.com/AztecProtocol/aztec-packages/master/barretenberg/bbup/install | bash   # then in a NEW shell (or after: export PATH=$HOME/.bb:$PATH): bbup -v 4.2.0-aztecnr-rc.2"
  echo "  (or add ~/.nargo/bin and ~/.bb to PATH if already installed)"
  exit 1
}
[ $# -ge 3 ] || { echo 'usage: ./run-proof-secure.sh <oldAddr> <newAddr> <domain>   (mnemonic typed at a hidden prompt)'; exit 1; }
./setup.sh
[ -d node_modules ] || npm install --no-audit --no-fund @scure/bip32 @scure/bip39 bip39 >/dev/null
cleanup(){ shred -u Prover.toml target/witness.gz 2>/dev/null || rm -f Prover.toml target/witness.gz; }
trap cleanup EXIT
printf 'Enter mnemonic (hidden): ' 1>&2;                 read -rs MN; echo 1>&2
printf 'BIP-39 passphrase (hidden, empty if none): ' 1>&2; read -rs PP; echo 1>&2
MNEMONIC="$MN" PASSPHRASE="$PP" node prepare.js "$1" "$2" "$3"
MN=; PP=
nargo execute witness
bb write_vk --scheme ultra_honk -b target/noir_prover_min.json -o target --oracle_hash keccak
bb prove   --scheme ultra_honk -b target/noir_prover_min.json -w target/witness.gz -k target/vk -o target --oracle_hash keccak
bb verify  --scheme ultra_honk -k target/vk -p target/proof -i target/public_inputs --oracle_hash keccak \
  && echo "RESULT: PROOF VERIFIED"
node print_submit.js
# target/proof + target/public_inputs reveal nothing about the seed and are safe to move off the airgapped box.
