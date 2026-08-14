// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
// The exact on-chain verifiers the CLI provers generate:
import {Groth16Verifier} from "groth16-verifier/verifier.sol";
import {HonkVerifier} from "honk-verifier/verifier.sol";

interface Vm {
    function readFile(string calldata) external view returns (string memory);
    function parseBytes(string calldata) external pure returns (bytes memory);
}

/// Regression: the *single ABI-encoded calldata blob* the Flutter app produces
/// (ProofResult.abiEncodedHex) must be accepted by the deployed verifier.
/// Fixtures are real proofs; see README.md for how to regenerate them.
contract VerifiersTest {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    Groth16Verifier g16;
    HonkVerifier honk;

    function setUp() public {
        g16 = new Groth16Verifier();
        honk = new HonkVerifier();
    }
    function _cd(string memory f) internal view returns (bytes memory) {
        return vm.parseBytes(vm.readFile(f));
    }
    function _verifies(address v, string memory fixture) internal view returns (bool) {
        (bool ok, bytes memory r) = v.staticcall(_cd(fixture));
        return ok && r.length == 32 && abi.decode(r, (bool));
    }
    // Groth16: app calldata = full verifyProof(uint[2],uint[2][2],uint[2],uint[3]) call.
    function test_groth16_app_calldata_verifies() public view {
        require(_verifies(address(g16), "fixtures/groth16_calldata.hex"), "groth16 app calldata did NOT verify");
    }
    // Noir: app calldata = full verify(bytes,bytes32[]) call (encodeNoirCallData).
    function test_noir_app_calldata_verifies() public view {
        require(_verifies(address(honk), "fixtures/noir_calldata.hex"), "noir app calldata did NOT verify");
    }
}
