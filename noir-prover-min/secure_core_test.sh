#!/usr/bin/env bash
# Self-test on the throwaway, publicly-known all-zero BIP-39 vector (holds no funds). Proves:
#   1. a correct (old,new,domain) triple produces a proof that verifies, and
#   2. the proof is BOUND: verifying it against a tampered new/domain FAILS.
set -e
cd "$(dirname "$0")"
export PATH="$HOME/.nargo/bin:$HOME/.bb:$PATH"
command -v nargo >/dev/null && command -v bb >/dev/null || {
  echo "ERROR: nargo/bb not on PATH. Install the pinned toolchain (see README):"
  echo "  curl -sL https://raw.githubusercontent.com/noir-lang/noirup/main/install | bash && noirup -v 1.0.0-beta.19"
  echo "  curl -sL https://raw.githubusercontent.com/AztecProtocol/aztec-packages/master/barretenberg/bbup/install | bash && bbup -v 4.2.0-aztecnr-rc.2"
  echo "  (or add ~/.nargo/bin and ~/.bb to PATH if already installed)"
  exit 1
}
./setup.sh
[ -d node_modules ] || npm install --no-audit --no-fund @scure/bip32 @scure/bip39 bip39 >/dev/null
MN='abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'
OLD=$(MNEMONIC="$MN" node -e '
const {HDKey}=require("@scure/bip32"),bip39=require("@scure/bip39"),c=require("crypto");
const m=HDKey.fromMasterSeed(bip39.mnemonicToSeedSync(process.env.MNEMONIC,""));
const a=m.derive("m/44\x27/313\x27/0\x27/0\x27/0\x27");
process.stdout.write("0x"+c.createHash("sha256").update(Buffer.from(a.publicKey)).digest().subarray(12).toString("hex"));')
NEW=0x00112233445566778899aabbccddeeff00112233
echo "test vector: old=$OLD  new=$NEW  domain=32769"
MNEMONIC="$MN" node prepare.js "$OLD" "$NEW" 32769 >/dev/null
nargo execute witness >/dev/null
bb write_vk --scheme ultra_honk -b target/noir_prover_min.json -o target --oracle_hash keccak >/dev/null
bb prove   --scheme ultra_honk -b target/noir_prover_min.json -w target/witness.gz -k target/vk -o target --oracle_hash keccak >/dev/null
printf '1) correct triple verifies : '
bb verify --scheme ultra_honk -k target/vk -p target/proof -i target/public_inputs --oracle_hash keccak >/dev/null 2>&1 && echo OK || { echo FAIL; exit 1; }
# tamper new_addr (public input field #2, byte offset 40) -> must be rejected
node -e 'const f=require("fs");const d=f.readFileSync("target/public_inputs");d[40]^=1;f.writeFileSync("/tmp/pi_t",d);'
printf '2) tampered NEW rejected    : '
if bb verify --scheme ultra_honk -k target/vk -p target/proof -i /tmp/pi_t --oracle_hash keccak >/dev/null 2>&1; then echo "FAIL (accepted!)"; else echo OK; fi
rm -f /tmp/pi_t
shred -u Prover.toml 2>/dev/null || rm -f Prover.toml
echo "SELF-TEST DONE."
