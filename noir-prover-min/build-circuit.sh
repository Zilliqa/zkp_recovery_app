#!/usr/bin/env bash
# Reproducibly compile the Noir circuit and print the verification-key hash (the reproducibility
# anchor, analogous to the circom wasm md5). Pin the toolchain + dependencies below.
#
# Toolchain (install with noirup / bbup):
#   nargo 1.0.0-beta.19                 ->  noirup -v 1.0.0-beta.19
#   bb    4.2.0-aztecnr-rc.2        ->  bbup   -v 4.2.0-aztecnr-rc.2
# Dependencies (see Nargo.toml):
#   bignum        v0.9.0   (git+tag, auto-fetched)
#   noir_bigcurve v0.13.0   (git+tag, auto-fetched)
#   sha256        v0.3.0    (git+tag, auto-fetched)
#   sha512        @ e92ffb473f3264529a0793770f63a09946df50cc  (vendored via setup.sh)
#
# Verified: the keccak VK hash is
#   1bbdaf1c92714c3a99645c7beb5ed5dc2b06c298068518653e42d6248e06bde0
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
./setup.sh
echo "nargo: $(nargo --version | head -1)"
echo "bb   : $(bb --version | head -1)"
nargo compile
bb write_vk --scheme ultra_honk -b target/noir_prover_min.json -o target --oracle_hash keccak
echo "VK hash : $(od -An -v -tx1 target/vk_hash | tr -d ' \n')"
echo "expected: 1bbdaf1c92714c3a99645c7beb5ed5dc2b06c298068518653e42d6248e06bde0"
echo
echo "Regenerate the on-chain verifier with:"
echo "  bb write_solidity_verifier --scheme ultra_honk -k target/vk -o verifier.sol"
