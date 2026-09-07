#!/usr/bin/env bash
# One-shot anvil e2e for the claim relayer. REQUIRES a local anvil already running on chain id 32769:
#     anvil --chain-id 32769
# Then, from this directory:  ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
# Anvil default account #0 — pays the relayer's gas here (well-known test key, no secrets).
RELAYER_PRIVATE_KEY="${RELAYER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
export RPC_URL RELAYER_PRIVATE_KEY

echo "==> Checking anvil at $RPC_URL (need chain id 32769)"
cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1 || { echo "anvil not reachable — run: anvil --chain-id 32769"; exit 1; }

echo "==> Compiling escrow (forge build)"
( cd ../e2e && forge build >/dev/null )

echo "==> Deploying escrow + lodging for the legacy source address (impersonated)"
node deploy_and_lodge.js
ESCROW_ADDRESS="$(cat .escrow_addr)"; export ESCROW_ADDRESS

echo "==> Running the REAL relay.js against anvil (local calldata source, not the Sheet)"
CURSOR="$(mktemp)"
CALLDATA_FILE=./calldata.txt CURSOR_FILE="$CURSOR" node ../relay.js
rm -f "$CURSOR"

echo "==> Verifying payout"
node verify_payout.js
