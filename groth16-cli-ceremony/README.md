# Groth16 phase-2 trusted-setup ceremony (terminal)

Command-line tooling for the Groth16 phase-2 trusted-setup ceremony of the Zilliqa seed-ownership
circuit. There are two roles, each self-contained in its own folder with its own instructions:

- **[`contributor/`](contributor/)** — if you're contributing randomness to the ceremony. Download
  this folder, follow its `README.md`: download the current key, run `./contribute.sh`, upload the
  result.
- **[`operator/`](operator/)** — if you're running the ceremony. Download this folder, follow its
  `README.md`: initialize the key, verify/promote each contribution, apply the final beacon, and
  publish the transcript.

Only one honest contributor is needed for the whole setup to be secure. A proving key is public
material — no seed or wallet secret is ever involved.
