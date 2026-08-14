// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
// Ad-hoc checker driven by ../check.sh: the calldata is passed via the CHECK_CALLDATA env var,
// the chosen verifier is deployed in-memory, and verify() is called on the raw calldata.
// No-op during a normal `forge test` (CHECK_VARIANT unset), so it doesn't affect the regression.
import {Groth16Verifier} from "groth16-verifier/verifier.sol";
import {HonkVerifier} from "honk-verifier/verifier.sol";

interface Vm {
    function envOr(string calldata, string calldata) external view returns (string memory);
    function envBytes(string calldata) external view returns (bytes memory);
}

contract CalldataCheck {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function test_check() public {
        string memory variant = vm.envOr("CHECK_VARIANT", string(""));
        if (bytes(variant).length == 0) return; // only runs when driven by check.sh
        bytes memory cd = vm.envBytes("CHECK_CALLDATA");
        address v = keccak256(bytes(variant)) == keccak256("groth16")
            ? address(new Groth16Verifier())
            : address(new HonkVerifier());
        (bool ok, bytes memory r) = v.staticcall(cd);
        require(ok && r.length == 32 && abi.decode(r, (bool)), "verifier REJECTED the calldata");
    }
}
