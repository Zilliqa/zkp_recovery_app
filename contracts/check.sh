#!/usr/bin/env bash
# check.sh <noir|groth16> 0x<calldata>
#
# Deploys the matching generated verifier (in-memory, via `forge test`) and checks that its
# verify() accepts the calldata you paste (the `abiEncodedHex` the Flutter app shows). No files,
# no anvil — paste the calldata straight from the app as the 2nd argument.
set -uo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.foundry/bin:$PATH"

variant="${1:-}"; calldata="${2:-}"
case "$variant" in noir|groth16) ;; *) echo "usage: bash check.sh <noir|groth16> 0x<calldata>"; exit 2 ;; esac
[ -n "$calldata" ] || { echo "usage: bash check.sh <noir|groth16> 0x<calldata>"; exit 2; }
[[ "$calldata" == 0x* ]] || calldata="0x$calldata"

if CHECK_VARIANT="$variant" CHECK_CALLDATA="$calldata" \
   forge test --match-contract CalldataCheck --match-test test_check >/tmp/check_out.$$ 2>&1; then
  echo "✅ ACCEPTED — the $variant verifier accepts this calldata (verify() = true)"
  rc=0
else
  echo "❌ REJECTED — the $variant verifier does NOT accept this calldata"
  grep -iE 'REJECTED|revert|reason|error|FAIL' /tmp/check_out.$$ | head -3 | sed 's/^/   /'
  rc=1
fi
rm -f /tmp/check_out.$$
exit $rc
