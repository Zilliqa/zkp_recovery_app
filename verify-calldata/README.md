# verify-calldata

Standalone, offline validator for a Zilliqa ZQ2 escrow `claim()` calldata string — the same calldata the
ZKP app emits (selector `0xcf1c9461`). It checks exactly what the on-chain escrow `claim()` checks, with
no network access and nothing to prepare:

1. **chain-id binding** — `pubSignals[2]` equals the expected chain id (default `32769`, ZQ2 mainnet `0x8001`);
   the escrow's `require(..., "Invalid domain")` gate.
2. **proof validity** — the Groth16 proof verifies against the **production** verification key in `vk.json`,
   whose 26 constants are identical to the deployed escrow `verifier.sol`.

Both must hold for the calldata to be accepted.

## Setup

```bash
npm install          # installs snarkjs (pinned). The bundled vk.json is the production key — no download needed.
```

## Usage

```bash
node verify_calldata.js <0xcf1c9461...calldata>
```

This form needs no setup beyond `npm install` and works for everyone. Options:

- `--domain <chainId>` — expected chain id for the binding check (default `32769`; use `33101` for testnet).
- `--vk <path>` — verify against a different key instead of the bundled production `vk.json`.
- `--json` — emit a single JSON object instead of human-readable text (for scripts; parse with e.g. `jq`).

Exit code: `0` only if the domain binding holds **and** the proof verifies; `1` otherwise; `2` on a usage error.

### Optional: run it by name

The package registers a `verify-calldata` command. To call it by name instead of the file path:

- `npx verify-calldata <calldata>` — works **from inside this folder** after `npm install`.
- `verify-calldata <calldata>` — works **anywhere**, but first link the command onto your PATH once:
  `npm link` (undo later with `npm rm -g verify-calldata`).

> Don't run `npx verify-calldata` from outside this folder unless it's linked — npx would try to fetch an
> unrelated package of that name from the public registry.

### Example

```bash
$ node verify_calldata.js 0xcf1c9461...
old  (proven)  : 0x19a6b57f471808dd8361f4d17415090a2c499da6
new  (bound)   : 0xf12476db80081e3180fcc447ac91618277ea137d
domain (bound) : 32769 == expected 32769  OK
isHardened     : 1
proof valid    : YES (vk: vk.json)
RESULT         : ACCEPT — would pass on-chain claim()
```
