# Ceremony transcript — Zilliqa seed-ownership (minimal Groth16 circuit)

## Circuit
- `circuit.r1cs` sha256: `f089bb4a35ac658ba84cceb341e76f130a1bebc891aed2c78b577a18ac034d0e` (SHA-256 of the r1cs file — reproduce by recompiling)
- snarkjs circuit hash (blake2b-512): `f52bc412d10db7c153de1c42a960a33df01984828f45dc56f116f79fc2c86c60aee1053dde7700b15886169edac1efe820e1858555dbedd8825670ee0c289bc8` (what `zkey verify` binds the key to)
- powers-of-tau: `pot.ptau` (blake2b `9aef0573cef4ded9c4a75f148709056bf989f80dad96876aadeb6f1c6d062391f07a394a9e756d16f7eb233198d5b69407cca44594c763ab4a5b67ae73254678`)

## Beacon (pre-committed public future source)
- source: pre-committed (announced before the ceremony) — the finalized hash of the first Ethereum mainnet block with timestamp >= 2026-09-04 14:00:00 UTC; the block is the one whose hash is the value below.
- value: `bb858b7334b94cadf8274a3d84e17bd1f7c2528abf0573ee3640082ed8d20e42`
- iterations: 10

## Final artifacts
- `final.zkey` sha256: `87191dc220d5cb0111442273a3232267d9029755674da0ee76f4a332b456d97d`
- `vk.json` sha256: `bb11e6dc683358b155c076c8b436e4166683a0492d693d5339d9b0af5f6f5391`
- `verifier.sol` sha256: `597995b997419209d3a8d8e456a4373df05003a21ab04e55327eadeef5089b00`

## Contribution chain
Full output of `npx snarkjs zkey verify circuit.r1cs pot.ptau final.zkey` — for every step: the
contribution number, contributor name, and its **contribution hash** (the 4 hex lines), plus the
beacon's generator + iteration count, ending in `ZKey Ok!`. Re-running the command reproduces this
exactly (snarkjs log prefixes removed for readability).

```
contribution #11 final beacon:
		917ebc99 1e732c9d 6b0bd6af 3922ff6b
		47bc0b37 704a5d93 82019584 a5c68723
		470c8717 d39fe51e 061f76c9 578c35de
		59b0bb76 ce77b556 6e2337d0 31dc8d61
Beacon generator: bb858b7334b94cadf8274a3d84e17bd1f7c2528abf0573ee3640082ed8d20e42
Beacon iterations Exp: 10
-------------------------
contribution #10 Patricia.zil:
		a7aa51ae 06a912cd 5efde2d5 6bf6baaf
		55f0f57f 1f26344b deaf91f0 22c0ca07
		6268290b 39e7b735 daac9dbf e9e3b7e4
		d0acebea 47c9388d db9893aa 38a35545
-------------------------
contribution #9 Zilliqa:
		7b5fd897 dc133e89 744067c0 84584f22
		db3255cc 0f71abf1 8452ab7d 5bee7323
		15873628 0f77a9fa e0caa33c e2b756e9
		cda2342d b77cdfb8 557ad0e2 44398d56
-------------------------
contribution #8 stakefish:
		4a76c3d0 a71cb984 c185c067 728c5c5e
		949b7db8 53986cbf a0cceb83 90608232
		52751e31 c6e1a97d ad87d1bc 92cc08e5
		9fe5b623 ca7e937e 7cecffd6 4f18ebea
-------------------------
contribution #7 Luganodes:
		9d645893 153908ae 58eb30bf cf2b1c93
		649333f9 2682e5c8 201a4c98 9148987a
		ceeb6ab4 fdb53787 07d58cde b26ecefc
		a57fcafb 4765bc9b fa61b4b3 b5220584
-------------------------
contribution #6 Kucoin Wallet Team:
		922cb432 dc050cd7 7571099d 887a7286
		6a9b91b9 a83327c8 13b9e113 221db121
		4dfeb425 42379dc2 ca7a90b1 afa8f651
		aa1b726f 3da8a9f3 83e0a688 82f7dc11
-------------------------
contribution #5 Moonlet:
		7fef2a88 d5bbf8b4 c3171820 87595d2c
		0399347e 7d7514be fc76a0ab 86046288
		593fd197 75491db1 40047e37 8bb4a9be
		c6c0be65 db18209c 4592b721 34a115a3
-------------------------
contribution #4 ltin.li:
		a138d18d d77b7b02 15c2b7e3 83b6aeea
		063fd7c4 f3a2429a 204565e7 58e510a8
		9e53b7f3 1f5d70a4 3c487dd0 d1902356
		b5126b3b 5e12675a 5d6bcc94 acb45f51
-------------------------
contribution #3 zillet:
		c608cba7 9e0d6760 2d9c3c22 d01e4b44
		37fe9469 6f48064b ab73e35d 416535ab
		57593a27 b7b9c4c6 c79d067d a983cd2c
		ba3351eb 565a3527 b5851f69 ecea2dcb
-------------------------
contribution #2 plunderswap:
		3f59ca61 a113aec6 3882eaae 19025021
		74af0f03 2b2c4add 50c7543f cb27a6b8
		1e28ce76 041c2452 25198f9c a4728de2
		650052db 365774ff 0c294219 c9f98552
-------------------------
contribution #1 anonymous:
		8fa2ee59 eaff2bcc ccd98a0f 3a778126
		460ed9d3 3f933f33 020a63af 1904e6a6
		6d7527fa 9bb9e7c3 961c9e5e d27711da
		2d8203ea fe353074 4052568e b06c9df3
-------------------------
ZKey Ok!
```

**How to verify:**
- Re-run `npx snarkjs zkey verify circuit.r1cs pot.ptau final.zkey`: you must get `ZKey Ok!` and the
  same contributions, hashes, and order as above.
- **Each contributor** confirms their own step by matching the hash `contribute.sh` printed to them
  against their entry above (same 4-line format) — no need to trust anyone else.
- The **beacon** (the `final beacon` entry) is reproducible: applying `zkey beacon` with the
  `Beacon generator` + `Beacon iterations Exp` shown to the previous contribution's key yields it.
