#!/usr/bin/env bash
# Quick prover (mnemonic on the command line — TESTING ONLY, leaks to shell history/ps).
# Produces target/proof + target/public_inputs, then prints submission instructions.
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
[ $# -ge 4 ] || { echo 'usage: ./run-proof.sh "<mnemonic>" <oldAddr> <newAddr> <domain>'; exit 1; }
./setup.sh
[ -d node_modules ] || npm install --no-audit --no-fund @scure/bip32 @scure/bip39 bip39 >/dev/null
node prepare.js "$1" "$2" "$3" "$4"
nargo execute witness
bb write_vk --scheme ultra_honk -b target/noir_prover_min.json -o target --oracle_hash keccak
bb prove   --scheme ultra_honk -b target/noir_prover_min.json -w target/witness.gz -k target/vk -o target --oracle_hash keccak
bb verify  --scheme ultra_honk -k target/vk -p target/proof -i target/public_inputs --oracle_hash keccak \
  && echo "RESULT: PROOF VERIFIED"
node print_submit.js
